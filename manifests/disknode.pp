#
#class based on the dpm wiki example
#
class dpm::disknode (
  Boolean $configure_vos = $dpm::params::configure_vos,
  Boolean $configure_gridmap = $dpm::params::configure_gridmap,
  Boolean $configure_repos = $dpm::params::configure_repos,
  Boolean $configure_dome = $dpm::params::configure_dome,
  Boolean $configure_domeadapter = $dpm::params::configure_domeadapter,
  Boolean $configure_mountpoints = $dpm::params::configure_mountpoints,
  Boolean $configure_dpm_xrootd_delegation = $dpm::params::configure_dpm_xrootd_delegation,
  Boolean $configure_dpm_xrootd_checksum = $dpm::params::configure_dpm_xrootd_checksum,

  #install and configure legacy stask
  Boolean $configure_legacy = $dpm::params::configure_legacy,
  #repo list
  Hash $repos = $dpm::params::repos,

  #cluster options
  Stdlib::Host $headnode_fqdn = $dpm::params::headnode_fqdn,
  Array[Stdlib::Host] $disk_nodes = $dpm::params::disk_nodes,
  String $localdomain = $dpm::params::localdomain,
  Boolean $webdav_enabled = $dpm::params::webdav_enabled,

  #mount points conf
  Array[Stdlib::Unixpath] $mountpoints = $dpm::params::mountpoints,

  #GridFTP redirection
  Integer[0, 1] $gridftp_redirect = $dpm::params::gridftp_redirect,

  #dpmmgr user options
  Integer $dpmmgr_uid = $dpm::params::dpmmgr_uid,
  Integer $dpmmgr_gid = $dpm::params::dpmmgr_gid,
  String $dpmmgr_user = $dpm::params::dpmmgr_user,

  #Auth options
  String $token_password = $dpm::params::token_password,
  String $xrootd_sharedkey = $dpm::params::xrootd_sharedkey,
  Boolean $xrootd_use_voms = $dpm::params::xrootd_use_voms,

  #VOs parameters
  Array[String] $volist = $dpm::params::volist,
  Hash[String,String] $groupmap = $dpm::params::groupmap,
  Hash[String,String] $localmap = $dpm::params::localmap,

  #Debug Flag
  Boolean $debug = $dpm::params::debug,

  #xrootd monitoring
  Optional[String] $xrd_report = $dpm::params::xrd_report,
  Optional[String] $xrootd_monitor = $dpm::params::xrootd_monitor,
  Optional[String] $xrootd_async = $dpm::params::xrootd_async,

  #xrootd tuning
  Optional[String] $xrd_timeout = $dpm::params::xrd_timeout,
  Boolean $xrootd_jemalloc = $dpm::params::xrootd_jemalloc,
  Optional[String] $xrootd_sec_level = $dpm::params::xrootd_sec_level,
  Optional[String] $xrootd_tpc_options = $dpm::params::xrootd_tpc_options,

  #host dn
  String $host_dn = $dpm::params::host_dn

) inherits dpm::params {

  if size($token_password) < 32 {
    fail('token_password should be longer than 32 chars')
  }

  if size($xrootd_sharedkey) < 32  {
    fail('xrootd_sharedkey should be longer than 32 chars and shorter than 64 chars')
  }

  if size($xrootd_sharedkey) > 64  {
    fail('xrootd_sharedkey should be longer than 32 chars and shorter than 64 chars')
  }

  if ($configure_repos){
    create_resources(yumrepo,$repos)
  }

  $disk_nodes_str=join($disk_nodes,' ')


  if $configure_legacy {
    Class[lcgdm::base::install] -> Class[lcgdm::rfio::install]
  }

  if(is_integer($gridftp_redirect)){
    $_gridftp_redirect = num2bool($gridftp_redirect)
  }else{
    $_gridftp_redirect = $gridftp_redirect
  }

  if($webdav_enabled){
    if $configure_domeadapter {
      Class[dmlite::plugins::domeadapter::install] ~> Class[dmlite::dav::service]
    } else {
      Class[dmlite::plugins::adapter::install] ~> Class[dmlite::dav::service]
    }
  }
  if $configure_domeadapter {
    Class[dmlite::plugins::domeadapter::install] ~> Class[dmlite::gridftp]
  } else {
    Class[dmlite::plugins::adapter::install] ~> Class[dmlite::gridftp]
  }

  if $configure_legacy {
    # lcgdm configuration.
    #
    class{'lcgdm::base':
      uid => $dpmmgr_uid,
      gid => $dpmmgr_gid,
    }
    class{'lcgdm::ns::client':
      flavor  => 'dpns',
      dpmhost => $headnode_fqdn
    }

    #
    # RFIO configuration.
    #
    class{'lcgdm::rfio':
      dpmhost => $headnode_fqdn,
    }

    #
    # Entries in the shift.conf file, you can add in 'host' below the list of
    # machines that the DPM should trust (if any).
    #
    lcgdm::shift::trust_value{
      'DPM TRUST':
        component => 'DPM',
        host      => "${disk_nodes_str} ${headnode_fqdn}";
      'DPNS TRUST':
        component => 'DPNS',
        host      => "${disk_nodes_str} ${headnode_fqdn}";
      'RFIO TRUST':
        component => 'RFIOD',
        host      => "${disk_nodes_str} ${headnode_fqdn}",
        all       => true
    }
    lcgdm::shift::protocol{'PROTOCOLS':
      component => 'DPM',
      proto     => 'rfio gsiftp http https xroot'
    }
  } else {
    class{'dmlite::base':
      uid => $dpmmgr_uid,
      gid => $dpmmgr_gid,
    }
  }
  if($configure_vos){
    $newvolist = reject($volist,'\.')
    dpm::util::add_dpm_voms {$newvolist:}
  }

  if($configure_gridmap){
    #setup the gridmap file
    lcgdm::mkgridmap::file {'lcgdm-mkgridmap':
      configfile   => '/etc/lcgdm-mkgridmap.conf',
      mapfile      => '/etc/lcgdm-mapfile',
      localmapfile => '/etc/lcgdm-mapfile-local',
      logfile      => '/var/log/lcgdm-mkgridmap.log',
      groupmap     => $groupmap,
      localmap     => $localmap
    }
    exec{'/usr/sbin/edg-mkgridmap --conf=/etc/lcgdm-mkgridmap.conf --safe --output=/etc/lcgdm-mapfile':
      require => Lcgdm::Mkgridmap::File['lcgdm-mkgridmap'],
      unless  => '/usr/bin/test -s /etc/lcgdm-mapfile',
    }
  }

  if($configure_mountpoints){
    if $configure_legacy {
      Class[lcgdm::base::config] ->
      file {
        $mountpoints:
          ensure => directory,
          owner => $dpmmgr_user,
          group => $dpmmgr_user,
          mode =>  '0775';
      }
    } else {
      Class[dmlite::base::config] ->
      file {
        $mountpoints:
          ensure => directory,
          owner => $dpmmgr_user,
          group => $dpmmgr_user,
          mode =>  '0775';
      }
    }
  }
  #
  # dmlite plugin configuration.
  class{'dmlite::disk':
    token_password     => $token_password,
    dpmhost            => $headnode_fqdn,
    nshost             => $headnode_fqdn,
    enable_dome        => $configure_dome,
    enable_domeadapter => $configure_domeadapter,
    legacy             => $configure_legacy,
    host_dn            => $host_dn,
  }

  #
  # dmlite frontend configuration.
  #
  if($webdav_enabled){
    class{'dmlite::dav':}
  }

  class{'dmlite::gridftp':
    dpmhost   => $headnode_fqdn,
    data_node => $_gridftp_redirect ? {
      true  => 1,
      false => 0,
    },
    legacy    => $configure_legacy,
  }

  #
  # The simplest xrootd configuration.
  #
  class{'xrootd::config':
    xrootd_user  => $dpmmgr_user,
    xrootd_group => $dpmmgr_user
  }

  if $xrd_report {
    $_xrd_report = $xrd_report
  } else {
    $_xrd_report = undef
  }
  if $xrootd_monitor {
    $_xrootd_monitor = $xrootd_monitor
  } else {
    $_xrootd_monitor = undef
  }
  class{'dmlite::xrootd':
    nodetype               => [ 'disk' ],
    dpmhost                => $headnode_fqdn,
    nshost                 => $headnode_fqdn,
    domain                 => $localdomain,
    dpm_xrootd_debug       => $debug,
    dpm_xrootd_sharedkey   => $xrootd_sharedkey,
    xrd_report             => $_xrd_report,
    xrootd_monitor         => $_xrootd_monitor,
    xrootd_async           => $xrootd_async,
    xrd_timeout            => $xrd_timeout,
    xrootd_jemalloc        => $xrootd_jemalloc,
    xrootd_sec_level       => $xrootd_sec_level,
    xrootd_tpc_options     => $xrootd_tpc_options,
    legacy                 => $configure_legacy,
    dpm_enable_dome        => $configure_dome,
    dpm_xrdhttp_secret_key => $token_password,
    xrootd_use_delegation  => $configure_dpm_xrootd_delegation,
    xrd_checksum_enabled   => $configure_dpm_xrootd_checksum
  }

}


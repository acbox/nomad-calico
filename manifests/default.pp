node 'default' {

  # Install Docker

  include ::docker

  # Install vanilla CNI plugins to get portmap plugin in order to open host ports into containers

  archive { 'cni-plugins-linux-amd64-v0.9.1.tgz':
    path         => "/tmp/cni-plugins-linux-amd64-v0.9.1.tgz",
    source       => "https://github.com/containernetworking/plugins/releases/download/v0.9.1/cni-plugins-linux-amd64-v0.9.1.tgz",
    extract      => true,
    extract_path => '/opt/cni/bin',
    creates      => '/opt/cni/bin/portmap',
    cleanup      => 'true',
  }

  # Install etcd required by Calico

  class { '::etcd':
  } ->

  # Install Calico Felix (aka calico-node container), CNI plugin and calicoctl command

  class { '::calico':
    # Calico CNI plugin binary patched for Nomad support
    cni_binary => 'https://github.com/acbox/cni-plugin/releases/download/v3.18.1-acbox-0/calico-amd64',
    require    => Class['docker'],
  } ->

  # Add a CNI configuration list with Calico CNI plugin pointing to etcdv3
  # and the portmap plugin to create host ports mapped to container ports

  file { '/opt/cni/config/mynetwork.conflist':
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    content => @(CONF/L)
    {
      "name": "mynetwork",
      "cniVersion": "0.3.0",
      "plugins": [
        {
          "type": "calico",
          "log_level": "DEBUG",
          "log_file_path": "/var/log/calico/cni/mynetwork.log",
          "datastore_type": "etcdv3",
          "etcd_endpoints":	"http://127.0.0.1:2379",
          "ipam": {
            "type": "calico-ipam",
            "ipv4_pools": ["myippool"]
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          },
          "snat": true
        }
      ]
    }
    | CONF
  } ->

  # Define Calico resources

  calico_node { 'vagrant.vm':
  } ->

  calico_ip_pool { 'myippool':
    cidr => '10.0.2.0/24', # https://www.virtualbox.org/manual/UserManual.html#nat-address-config
  } ->

  calico_host_endpoint { 'vagrant':
    expectedips => ['10.0.2.15'],
    node        => 'vagrant.vm',
    labels      => { 'role' => 'host' }
  } ->

  calico_global_network_policy { 'web':
    selector => 'all()',
    #selector => 'role == "host"',
    order    => 10,
    types    => [ 'Ingress', 'Egress' ],
    ingress  => [
      {
        action      => 'Allow',
        protocol    => 'TCP',
        source      => { nets => [ '10.0.2.0/24' ] },
        destination => { ports => [ 443 ] },
      }
    ],
    egress   => [
      {
        action      => 'Allow',
        protocol    => 'TCP',
        source      => { nets => [ '0.0.0.0/0' ] },
        destination => { nets => [ '0.0.0.0/0' ] },
      }
    ],
  } ->

  # Install single-node Nomad server/agent

  archive { '/usr/local/bin/nomad':
    ensure => present,
    source => 'https://github.com/acbox/nomad/releases/download/v1.0.4-acbox-0/nomad-amd64',
    user   => 0,
    group  => 0,
  } ->

  exec { 'nomad binary permissions':
    command     => '/bin/chmod +x /usr/local/bin/nomad',
    subscribe   => Archive['/usr/local/bin/nomad'],
    refreshonly => true,
  } ->

  class { '::nomad':
    install_method      => 'none',
    manage_service_file => true,
    bin_dir             => '/usr/local/bin',
    version             => '1.0.1',
    config_hash         => {
      'datacenter' => 'home',
      'log_level' => 'DEBUG',
      'bind_addr' => '0.0.0.0',
      'data_dir' => '/opt/nomad',
      'client' => {
        'enabled' => true,
        'cni_config_dir' => '/opt/cni/config',
        'servers'       => [
          'localhost:4647',
        ],
      },
      'server'          => {
        'enabled' => true,
        'bootstrap_expect' => 1,
      }
    },
  } ->

  file { '/etc/nomad.d/hello-world.hcl':
    owner   => 'root',
    group   => 'root',
    mode    => '0755',
    content => @(JOB/L)
    job "hello-world" {
      datacenters = ["home"]
      group "hello-world" {
        network {
          mode = "cni/mynetwork"
          port "http" {
            static = 4567
            to     = 4567
          }
        }
        meta {
          CALICO_role = "host"
        }
        task "hello-world" {
          driver = "docker"
          config {
            command = "/usr/bin/tail"
            args    = ["-f", "/dev/null"]
            image   = "alpine"
          }
        }
      }
    }
    | JOB
  } ->

  exec { "/usr/bin/timeout 30 sh -c 'until /usr/local/bin/nomad run /etc/nomad.d/hello-world.hcl; do sleep 1; done'":
  }
}

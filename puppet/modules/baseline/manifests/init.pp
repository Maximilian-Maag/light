# Baseline class — enforced on every node every 30 minutes.
# Drift from these settings is automatically corrected by the Puppet agent.
# Values are sourced from Hiera (puppet/data/common.yaml).

class baseline (
  String $checkmk_server  = lookup('baseline::checkmk_server'),
  String $mgmt_zone_cidr  = lookup('baseline::mgmt_zone_cidr'),
  String $puppet_server   = lookup('baseline::puppet_server'),
  Array  $ntp_servers     = lookup('baseline::ntp_servers'),
  Array  $dns_servers     = lookup('baseline::dns_servers'),
) {

  # ── SSH hardening ───────────────────────────────────────────────────────────
  file { '/etc/ssh/sshd_config':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => template('baseline/sshd_config.erb'),
    notify  => Service['ssh'],
  }

  service { 'ssh':
    ensure => running,
    enable => true,
  }

  # ── UFW default policy ──────────────────────────────────────────────────────
  exec { 'ufw-default-deny-incoming':
    command => '/usr/sbin/ufw default deny incoming',
    unless  => '/usr/sbin/ufw status verbose | grep -q "Default: deny (incoming)"',
  }

  exec { 'ufw-default-deny-outgoing':
    command => '/usr/sbin/ufw default deny outgoing',
    unless  => '/usr/sbin/ufw status verbose | grep -q "Default: deny (outgoing)"',
    require => Exec['ufw-default-deny-incoming'],
  }

  exec { 'ufw-enable':
    command => '/usr/sbin/ufw --force enable',
    unless  => '/usr/sbin/ufw status | grep -q "Status: active"',
    require => Exec['ufw-default-deny-outgoing'],
  }

  # Allow SSH inbound from management zone only
  exec { 'ufw-allow-ssh-mgmt':
    command => "/usr/sbin/ufw allow in proto tcp from ${mgmt_zone_cidr} to any port 22",
    unless  => "/usr/sbin/ufw status | grep -q '22/tcp.*${mgmt_zone_cidr}'",
    require => Exec['ufw-enable'],
  }

  # Allow Checkmk agent polling inbound
  exec { 'ufw-allow-checkmk-agent':
    command => "/usr/sbin/ufw allow in proto tcp from ${checkmk_server} to any port 6556",
    unless  => "/usr/sbin/ufw status | grep -q '6556/tcp.*${checkmk_server}'",
    require => Exec['ufw-enable'],
  }

  # Allow outbound to Puppet
  exec { 'ufw-allow-puppet-out':
    command => "/usr/sbin/ufw allow out proto tcp to ${puppet_server} port 8140",
    unless  => "/usr/sbin/ufw status | grep -q '8140/tcp.*${puppet_server}'",
    require => Exec['ufw-enable'],
  }

  # ── NTP via chrony ──────────────────────────────────────────────────────────
  package { 'chrony':
    ensure => installed,
  }

  file { '/etc/chrony/chrony.conf':
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('baseline/chrony.conf.erb'),
    require => Package['chrony'],
    notify  => Service['chrony'],
  }

  service { 'chrony':
    ensure  => running,
    enable  => true,
    require => Package['chrony'],
  }

  # ── Puppet agent cron (30-min pull cycle) ───────────────────────────────────
  cron { 'puppet-agent':
    command => '/opt/puppetlabs/bin/puppet agent --onetime --no-daemonize --logdest syslog 2>&1 | logger -t puppet-agent',
    user    => 'root',
    minute  => ['0', '30'],
  }

  # ── Checkmk agent ───────────────────────────────────────────────────────────
  exec { 'install-checkmk-agent':
    command => "/bin/bash -c 'curl -fsSL http://${checkmk_server}/cmk/agents/check-mk-agent_latest-1_all.deb -o /tmp/cmk-agent.deb && dpkg -i /tmp/cmk-agent.deb && rm /tmp/cmk-agent.deb'",
    unless  => 'dpkg -l check-mk-agent 2>/dev/null | grep -q "^ii"',
    path    => ['/usr/bin', '/usr/sbin', '/bin'],
  }

  service { 'check_mk.socket':
    ensure  => running,
    enable  => true,
    require => Exec['install-checkmk-agent'],
  }
}

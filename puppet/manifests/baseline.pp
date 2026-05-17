# Baseline class — enforced on every node every 30 minutes.
# Drift from these settings is automatically corrected by the Puppet agent.

class baseline {

  # ── SSH hardening ──────────────────────────────────────────────────────────
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

  # ── UFW default policy ─────────────────────────────────────────────────────
  exec { 'ufw-default-deny':
    command => '/usr/sbin/ufw default deny incoming',
    unless  => '/usr/sbin/ufw status verbose | grep -q "Default: deny (incoming)"',
  }

  exec { 'ufw-enable':
    command => '/usr/sbin/ufw --force enable',
    unless  => '/usr/sbin/ufw status | grep -q "Status: active"',
    require => Exec['ufw-default-deny'],
  }

  # ── NTP via chrony ─────────────────────────────────────────────────────────
  package { 'chrony':
    ensure => installed,
  }

  service { 'chrony':
    ensure  => running,
    enable  => true,
    require => Package['chrony'],
  }

  # ── Puppet agent cron (30-min pull cycle) ─────────────────────────────────
  cron { 'puppet-agent':
    command => '/opt/puppetlabs/bin/puppet agent --onetime --no-daemonize --logdest syslog 2>&1 | logger -t puppet-agent',
    user    => 'root',
    minute  => ['0', '30'],
  }

  # ── Checkmk agent ──────────────────────────────────────────────────────────
  package { 'check-mk-agent':
    ensure  => installed,
    require => Exec['add-checkmk-apt-source'],
  }

  exec { 'add-checkmk-apt-source':
    command => "/bin/bash -c 'curl -fsSL http://${facts['checkmk_server']}/cmk/agents/check-mk-agent_latest-1_all.deb -o /tmp/cmk-agent.deb && dpkg -i /tmp/cmk-agent.deb'",
    unless  => 'dpkg -l check-mk-agent 2>/dev/null | grep -q "^ii"',
  }

  service { 'check_mk.socket':
    ensure  => running,
    enable  => true,
    require => Package['check-mk-agent'],
  }
}

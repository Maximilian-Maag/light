#!/usr/bin/env bash
set -euo pipefail

# Configure Puppet agent to point at the Puppet server from env
if [[ -n "${PUPPET_SERVER:-}" ]]; then
    /opt/puppetlabs/bin/puppet config set server "${PUPPET_SERVER}" --section agent
fi

# Start SSH
mkdir -p /run/sshd
exec /usr/sbin/sshd -D

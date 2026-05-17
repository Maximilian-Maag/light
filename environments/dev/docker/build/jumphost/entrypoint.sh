#!/usr/bin/env bash
set -euo pipefail

# Install the operator's public key at runtime
if [[ -f /etc/jumphost/authorized_keys ]]; then
    cp /etc/jumphost/authorized_keys /home/admin/.ssh/authorized_keys
    chown admin:admin /home/admin/.ssh/authorized_keys
    chmod 600 /home/admin/.ssh/authorized_keys
fi

mkdir -p /run/sshd
exec /usr/sbin/sshd -D

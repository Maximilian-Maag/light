# Jumphost — SSH bastion, sole external entry point to both networks.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    fail2ban \
    ufw \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash admin \
    && mkdir -p /home/admin/.ssh \
    && chown admin:admin /home/admin/.ssh \
    && chmod 700 /home/admin/.ssh

# SSH: key-only, no root, no password, only forward to internal hosts
RUN sed -i \
        -e 's/^#*PermitRootLogin.*/PermitRootLogin no/' \
        -e 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' \
        -e 's/^#*AllowAgentForwarding.*/AllowAgentForwarding yes/' \
        -e 's/^#*AllowTcpForwarding.*/AllowTcpForwarding yes/' \
        -e 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' \
        -e 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 0/' \
    /etc/ssh/sshd_config

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]

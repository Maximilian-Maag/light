# Workload node image — identical agent stack to staging/prod VMs.
# A VM running on this image cannot distinguish itself from a cloud/on-prem VM.

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Base packages matching the enterprise baseline
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    sudo \
    curl \
    wget \
    ca-certificates \
    gnupg \
    lsb-release \
    systemd \
    systemd-sysv \
    ufw \
    chrony \
    sssd \
    sssd-ldap \
    libpam-sss \
    libnss-sss \
    cron \
    logwatch \
    netcat-openbsd \
    iproute2 \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Puppet agent
RUN curl -fsSL https://apt.puppet.com/puppet8-release-$(lsb_release -cs).deb \
        -o /tmp/puppet.deb \
    && dpkg -i /tmp/puppet.deb \
    && apt-get update \
    && apt-get install -y puppet-agent \
    && rm -rf /var/lib/apt/lists/* /tmp/puppet.deb

# Checkmk agent
# Installed at runtime via Ansible (pulled from Checkmk server) so the binary
# version always matches the Checkmk server version.

# SSH hardening — matches the Puppet baseline so the agent's first run is a no-op
RUN sed -i \
        -e 's/^#*PermitRootLogin.*/PermitRootLogin no/' \
        -e 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' \
        -e 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
        -e 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' \
        -e 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 0/' \
    /etc/ssh/sshd_config

# UFW default-deny — Puppet will open specific ports
RUN ufw default deny incoming && ufw default allow outgoing

# Puppet agent service runs via cron (every 30 min) — matches pull model in prod
COPY puppet-agent-cron /etc/cron.d/puppet-agent
RUN chmod 0644 /etc/cron.d/puppet-agent

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 6556

ENTRYPOINT ["/entrypoint.sh"]

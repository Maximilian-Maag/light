FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Foreman from the official package repo (includes Apache + Passenger).
# Dynamically detect the latest available version from the repo's InRelease file
# so the image keeps building as new Foreman versions are released.
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        wget ca-certificates curl postgresql-client && \
    wget -qO /etc/apt/trusted.gpg.d/foreman.asc \
        https://deb.theforeman.org/foreman.asc && \
    CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")" && \
    FOREMAN_VER="$(curl -fsSL \
        "https://deb.theforeman.org/dists/${CODENAME}/InRelease" | \
        awk '/^Components:/{for(i=2;i<=NF;i++) print $i}' | \
        grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -1)" && \
    [ -n "${FOREMAN_VER}" ] || \
        { echo "ERROR: no Foreman release found for ${CODENAME}"; exit 1; } && \
    echo "Installing Foreman ${FOREMAN_VER} on ${CODENAME}" && \
    printf 'deb [signed-by=/etc/apt/trusted.gpg.d/foreman.asc] http://deb.theforeman.org/ %s %s\n' \
        "${CODENAME}" "${FOREMAN_VER}" > /etc/apt/sources.list.d/foreman.list && \
    printf 'deb [signed-by=/etc/apt/trusted.gpg.d/foreman.asc] http://deb.theforeman.org/ plugins %s\n' \
        "${FOREMAN_VER}" >> /etc/apt/sources.list.d/foreman.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        foreman \
        libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# Add the pg gem via bundler.d (mirrors what foreman-installer does for PostgreSQL).
# pg-x86_64-linux is a precompiled binary gem already in the vendor cache, so no
# build tools are required — bundle install just extracts it.
RUN echo "gem 'pg'" > /usr/share/foreman/bundler.d/Gemfile.local.rb && \
    cd /usr/share/foreman && \
    RAILS_ENV=production /usr/share/foreman/bin/bundle install --local 2>&1

# Apache runs in the foreground; remove the default site
RUN a2dissite 000-default 2>/dev/null || true

COPY database.yml /etc/foreman/database.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=180s \
    CMD curl -fsk https://localhost/api/v2/status || curl -fs http://localhost/api/v2/status

ENTRYPOINT ["/entrypoint.sh"]

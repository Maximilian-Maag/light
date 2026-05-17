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

# Install pg and puma via bundler.d — both are precompiled binary gems already
# in vendor/cache, so bundle install --local just extracts them, no build tools needed.
RUN printf "gem 'pg'\ngem 'puma'\n" > /usr/share/foreman/bundler.d/Gemfile.local.rb && \
    cd /usr/share/foreman && \
    RAILS_ENV=production /usr/share/foreman/bin/bundle install --local 2>&1

COPY database.yml /etc/foreman/database.yml
COPY puma.rb /usr/share/foreman/config/puma/docker.rb
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=180s \
    CMD curl -fs http://localhost:3000/api/v2/status

ENTRYPOINT ["/entrypoint.sh"]

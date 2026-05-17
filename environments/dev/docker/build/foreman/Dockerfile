FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Foreman 3.9 from the official package repo (includes Apache + Passenger)
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends wget ca-certificates curl postgresql-client && \
    wget -qO /etc/apt/trusted.gpg.d/foreman.asc \
        https://deb.theforeman.org/foreman.asc && \
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/foreman.asc] \
http://deb.theforeman.org/ jammy 3.9" \
        > /etc/apt/sources.list.d/foreman.list && \
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/foreman.asc] \
http://deb.theforeman.org/ plugins 3.9" \
        >> /etc/apt/sources.list.d/foreman.list && \
    apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        foreman \
        ruby-foreman-discovery \
        libpq-dev && \
    rm -rf /var/lib/apt/lists/*

# Apache runs in the foreground; remove the default site
RUN a2dissite 000-default 2>/dev/null || true

COPY database.yml /etc/foreman/database.yml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443

HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=180s \
    CMD curl -fsk https://localhost/api/v2/status || curl -fs http://localhost/api/v2/status

ENTRYPOINT ["/entrypoint.sh"]

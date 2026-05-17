#!/bin/bash
set -e

DB_HOST="${DB_HOST:-foreman-db}"
DB_USER="${DB_USER:-foreman}"
DB_PASSWORD="${DB_PASSWORD:-foreman}"
FOREMAN_ADMIN_USERNAME="${FOREMAN_ADMIN_USERNAME:-admin}"
FOREMAN_ADMIN_PASSWORD="${FOREMAN_ADMIN_PASSWORD:-changeme}"

echo "Waiting for PostgreSQL at ${DB_HOST}..."
until pg_isready -h "${DB_HOST}" -U "${DB_USER}" -q; do
    sleep 3
done
echo "PostgreSQL is ready."

# Write database.yml with concrete values.
# foreman-rake uses 'runuser - foreman' (login shell) which strips the
# environment, so ERB ENV lookups in the template return nil.
cat > /etc/foreman/database.yml <<DBEOF
production:
  adapter: postgresql
  database: foreman
  username: ${DB_USER}
  password: ${DB_PASSWORD}
  host: ${DB_HOST}
  port: 5432
  pool: 25
DBEOF

foreman-rake db:migrate
foreman-rake db:seed || true

# Embed admin creds in the command string so they survive the login-shell
# invocation inside foreman-rake (alphanumeric-only values, safe in quotes).
runuser - foreman -s /bin/bash -c \
    "FOREMAN_ADMIN_USERNAME='${FOREMAN_ADMIN_USERNAME}' \
     FOREMAN_ADMIN_PASSWORD='${FOREMAN_ADMIN_PASSWORD}' \
     RUBYOPT=-W0 RAILS_ENV=production \
     /usr/bin/foreman-ruby /usr/bin/bundle3.0 exec rake permissions:reset" || true

exec apachectl -D FOREGROUND

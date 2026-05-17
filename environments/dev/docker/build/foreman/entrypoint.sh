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

# Set the admin password directly via Rails runner.
# permissions:reset (3.19+) ignores FOREMAN_ADMIN_PASSWORD and generates its
# own random password. Write a temp Ruby script with the values already
# expanded so the runuser login-shell stripping doesn't matter.
cat > /tmp/set_admin.rb <<RBEOF
u = User.unscoped.find_by_login('${FOREMAN_ADMIN_USERNAME}') || User.unscoped.find_by_login('admin')
u.password = '${FOREMAN_ADMIN_PASSWORD}'
u.password_confirmation = '${FOREMAN_ADMIN_PASSWORD}'
u.admin = true
u.save!
puts "Admin user '#{u.login}' password set."
RBEOF
runuser - foreman -s /bin/bash -c \
    "cd /usr/share/foreman && RAILS_ENV=production RUBYOPT=-W0 \
     /usr/bin/foreman-ruby /usr/bin/bundle3.0 exec rails runner /tmp/set_admin.rb" || true

mkdir -p /usr/share/foreman/tmp/sockets /usr/share/foreman/tmp/pids
rm -f /usr/share/foreman/tmp/sockets/pumactl.sock /usr/share/foreman/tmp/puma.state
chown -R foreman: /usr/share/foreman/tmp

cd /usr/share/foreman
exec runuser - foreman -s /bin/bash -c \
    "cd /usr/share/foreman && RAILS_ENV=production RUBYOPT=-W0 \
     exec /usr/bin/foreman-ruby /usr/bin/bundle3.0 exec puma \
     -C config/puma/docker.rb"

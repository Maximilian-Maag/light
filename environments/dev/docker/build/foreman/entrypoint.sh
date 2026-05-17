#!/bin/bash
set -e

DB_HOST="${DB_HOST:-foreman-db}"
DB_USER="${DB_USER:-foreman}"

echo "Waiting for PostgreSQL at ${DB_HOST}..."
until pg_isready -h "${DB_HOST}" -U "${DB_USER}" -q; do
    sleep 3
done
echo "PostgreSQL is ready."

export RAILS_ENV=production

# Run migrations (idempotent)
foreman-rake db:migrate

# Seed initial data (idempotent — skips existing records)
foreman-rake db:seed || true

# Set admin credentials
FOREMAN_ADMIN_USERNAME="${FOREMAN_ADMIN_USERNAME:-admin}" \
FOREMAN_ADMIN_PASSWORD="${FOREMAN_ADMIN_PASSWORD:-changeme}" \
    foreman-rake permissions:reset || true

# Apache + Passenger serve Foreman — run in the foreground
exec apachectl -D FOREGROUND

#!/usr/bin/env bash
# Generate Docker Compose, DNS, and Ansible vars from config/topology.json.
# Called automatically by startup.sh dev if topology.json exists.
# Can also be run standalone to preview what will be generated.
#
# Usage: ./scripts/gen-topology.sh

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${LIGHT_ROOT}/lib/logging.sh"

TOPOLOGY="${LIGHT_ROOT}/config/topology.json"
ENV_CFG="${LIGHT_ROOT}/config/light.env"

[[ -f "${TOPOLOGY}" ]] || log::die "config/topology.json not found"

# Load enough config to pass domain/env/location to the generator
source "${ENV_CFG}" 2>/dev/null || true
ENV="${LIGHT_ENV:-dev}"
LOC="${LIGHT_LOCATION:-local}"
DOM="${LIGHT_DOMAIN:-simple-test.org}"

log::section "Generating topology from config/topology.json"
log::info "Environment: ${ENV} / Location: ${LOC} / Domain: ${DOM}"

python3 "${LIGHT_ROOT}/scripts/lib/gen_topology.py" \
    "${TOPOLOGY}" \
    "${LIGHT_ROOT}" \
    "${ENV}" \
    "${LOC}" \
    "${DOM}" \
    "${ENV_CFG}"

log::ok "Topology generated"
log::info "Docker Compose overlay: environments/dev/docker/docker-compose.topology.yml  (docker mode)"
log::info "Vagrantfile:            environments/dev/vagrant/Vagrantfile.topology         (hybrid mode)"
log::info "DNS additions:          environments/dev/docker/config/dns/zones/db.topology"
log::info "Ansible group_vars:     ansible/group_vars/bubble_*.yml"
log::info "Static inventory:       ansible/inventory/topology.ini"

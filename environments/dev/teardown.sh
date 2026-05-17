#!/usr/bin/env bash
set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${LIGHT_ROOT}/lib/common.sh"

log::section "Tearing down dev environment (runtime: ${LIGHT_RUNTIME})"

case "${LIGHT_RUNTIME}" in
    hybrid)
        docker compose \
            -f "${LIGHT_ROOT}/environments/dev/docker/docker-compose.yml" \
            --env-file "${LIGHT_ROOT}/config/light.env" \
            down -v --remove-orphans
        log::ok "Docker mgmt-zone removed"
        TOPOLOGY_VAGRANTFILE="${LIGHT_ROOT}/environments/dev/vagrant/Vagrantfile.topology"
        if [[ -f "${TOPOLOGY_VAGRANTFILE}" ]]; then
            vagrant destroy -f --vagrantfile "${TOPOLOGY_VAGRANTFILE}" 2>/dev/null || true
            log::ok "Vagrant workload VMs destroyed"
        else
            log::info "No Vagrantfile.topology found — skipping Vagrant teardown"
        fi
        ;;
    docker)
        docker compose \
            -f "${LIGHT_ROOT}/environments/dev/docker/docker-compose.yml" \
            --env-file "${LIGHT_ROOT}/config/light.env" \
            down -v --remove-orphans
        log::ok "Docker stack removed"
        ;;
    vagrant)
        vagrant destroy -f \
            --vagrantfile "${LIGHT_ROOT}/environments/dev/vagrant/Vagrantfile"
        log::ok "Vagrant VMs destroyed"
        ;;
    *)
        log::die "Unknown dev runtime '${LIGHT_RUNTIME}'. Use: hybrid | docker | vagrant"
        ;;
esac

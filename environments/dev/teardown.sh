#!/usr/bin/env bash
set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${LIGHT_ROOT}/lib/common.sh"

log::section "Tearing down dev environment (runtime: ${LIGHT_RUNTIME})"

case "${LIGHT_RUNTIME}" in
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
        log::die "Unknown dev runtime '${LIGHT_RUNTIME}'. Use: docker | vagrant"
        ;;
esac

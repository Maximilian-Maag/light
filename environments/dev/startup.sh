#!/usr/bin/env bash
# Dev environment startup — spins up the full management zone + workload nodes
# locally via Docker or Vagrant. Identical service topology to staging/prod.

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${LIGHT_ROOT}/lib/preflight.sh"

log::section "Starting dev environment (runtime: ${LIGHT_RUNTIME})"

case "${LIGHT_RUNTIME}" in
    docker)
        preflight_dev_docker

        log::section "Bringing up management zone"
        docker compose \
            -f "${LIGHT_ROOT}/environments/dev/docker/docker-compose.yml" \
            --env-file "${LIGHT_ROOT}/config/light.env" \
            up -d --build

        log::section "Waiting for core services"
        wait_for_port "${IP_FOREMAN}"  443 180
        wait_for_port "${IP_PUPPET}"   8140 180
        wait_for_port "${IP_CHECKMK}"  443 120
        wait_for_port "${IP_PULP}"     80  120

        log::section "Running Puppet baseline on all nodes"
        ansible_play baseline.yml --limit all

        log::section "Registering hosts in Foreman"
        ansible_play foreman-register.yml

        log::section "Registering hosts in Checkmk"
        ansible_play checkmk-register.yml
        ;;

    vagrant)
        preflight_dev_vagrant

        log::section "Bringing up management zone via Vagrant"
        vagrant up --provider=virtualbox \
            --vagrantfile "${LIGHT_ROOT}/environments/dev/vagrant/Vagrantfile"

        log::section "Running Puppet baseline"
        ansible_play baseline.yml --limit all

        log::section "Registering hosts in Foreman"
        ansible_play foreman-register.yml

        log::section "Registering hosts in Checkmk"
        ansible_play checkmk-register.yml
        ;;

    *)
        log::die "Unknown dev runtime '${LIGHT_RUNTIME}'. Use: docker | vagrant"
        ;;
esac

log::section "Dev environment ready"
log::info "Domain:    ${LIGHT_DOMAIN}"
log::info "Jumphost:  ssh admin@${IP_JUMPHOST}"
log::info "Foreman:   https://${IP_FOREMAN}"
log::info "Checkmk:   https://${IP_CHECKMK}"
log::info "Pulp:      http://${IP_PULP}"

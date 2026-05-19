#!/usr/bin/env bash
set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${LIGHT_ROOT}/lib/common.sh"

COMPOSE_BASE="${LIGHT_ROOT}/environments/dev/docker/docker-compose.yml"
COMPOSE_TOPO="${LIGHT_ROOT}/environments/dev/docker/docker-compose.topology.yml"
TOPOLOGY="${LIGHT_ROOT}/config/topology.json"
ENV_FILE="${LIGHT_ROOT}/config/light.env"
VAGRANT_DIR="${LIGHT_ROOT}/environments/dev/vagrant"
VAGRANT_TOPO="${VAGRANT_DIR}/Vagrantfile.topology"

log::section "Tearing down dev environment (runtime: ${LIGHT_RUNTIME})"

# ── Helper: run ansible playbook via the controller container ──────────────────
ansible_in_container() {
    local playbook="${1:?}"; shift
    local ans_ctr="${LIGHT_ENV:-dev}-${LIGHT_LOCATION:-local}-srv-ans-001"
    local inventories=()
    if curl -sf --max-time 5 \
           -u "${FOREMAN_ADMIN_USER:-admin}:${FOREMAN_ADMIN_PASS:-changeme}" \
           "http://${IP_FOREMAN:-10.10.0.20}:3000/api/v2/status" \
           -o /dev/null 2>/dev/null; then
        inventories+=(-i /opt/ansible/inventory/foreman.yml)
    fi
    inventories+=(-i /opt/ansible/inventory/topology.ini)
    docker exec \
        "${ans_ctr}" \
        ansible-playbook \
            "${inventories[@]}" \
            "/opt/ansible/playbooks/${playbook}" \
            "$@" 2>/dev/null || true
}

# ── Helper: remove iptables FORWARD rules added for cross-zone VM→mgmt access ─
flush_vm_to_mgmt_rules() {
    local mgmt_cidr="${MGMT_ZONE_CIDR:-10.10.0.0/24}"
    if [[ ! -f "${TOPOLOGY}" ]]; then return; fi
    python3 -c "
import json
with open('${TOPOLOGY}') as f: t = json.load(f)
for b in t.get('bubbles', {}).values():
    if not list(b.keys())[0].startswith('_'):
        print(b['cidr'])
" 2>/dev/null | while read -r cidr; do
        while sudo iptables -D DOCKER-USER \
                -s "${cidr}" -d "${mgmt_cidr}" -j ACCEPT 2>/dev/null; do :; done
    done
    log::ok "iptables cross-zone rules removed"
}

# ── Helper: docker compose down with all relevant files ───────────────────────
dc_down() {
    local files=(-f "${COMPOSE_BASE}")
    [[ -f "${COMPOSE_TOPO}" ]] && files+=(-f "${COMPOSE_TOPO}")
    docker compose "${files[@]}" --env-file "${ENV_FILE}" down -v --remove-orphans
}

case "${LIGHT_RUNTIME}" in

    # ── Hybrid: Docker mgmt zone + Vagrant workload VMs ───────────────────────
    hybrid)
        # Cache sudo credentials upfront so iptables flush doesn't prompt mid-teardown.
        if ! sudo -n true 2>/dev/null; then
            log::info "sudo required for iptables cleanup — enter password once:"
            sudo -v
        fi

        # Deregister bubble hosts while management services are still running
        log::section "Deregistering bubble hosts from Checkmk"
        ansible_in_container checkmk-deregister.yml --limit bubble_all || \
            log::warn "Checkmk deregister failed — continuing"

        log::section "Deregistering bubble hosts from Foreman"
        ansible_in_container foreman-deregister.yml --limit bubble_all || \
            log::warn "Foreman deregister failed — continuing"

        # Destroy workload VMs
        if [[ -f "${VAGRANT_TOPO}" ]]; then
            log::section "Destroying Vagrant workload VMs"
            (
                cd "${VAGRANT_DIR}"
                VAGRANT_VAGRANTFILE=Vagrantfile.topology vagrant destroy -f
            ) || log::warn "Vagrant destroy failed or no VMs running"
            log::ok "Vagrant workload VMs destroyed"
        else
            log::info "No Vagrantfile.topology found — skipping Vagrant teardown"
        fi

        # Stop Docker management zone
        log::section "Removing Docker management zone"
        dc_down
        log::ok "Docker mgmt-zone removed"

        # Clean up host iptables rules added for cross-zone forwarding
        log::section "Cleaning up iptables cross-zone rules"
        flush_vm_to_mgmt_rules
        ;;

    # ── Docker: everything as containers ──────────────────────────────────────
    docker)
        # Deregister while containers are still up
        log::section "Deregistering hosts from Checkmk"
        ansible_in_container checkmk-deregister.yml || \
            log::warn "Checkmk deregister failed — continuing"

        log::section "Deregistering hosts from Foreman"
        ansible_in_container foreman-deregister.yml || \
            log::warn "Foreman deregister failed — continuing"

        log::section "Removing Docker stack"
        dc_down
        log::ok "Docker stack removed"
        ;;

    # ── Vagrant: legacy all-VM mode ────────────────────────────────────────────
    vagrant)
        log::section "Destroying Vagrant VMs"
        vagrant destroy -f \
            --vagrantfile "${LIGHT_ROOT}/environments/dev/vagrant/Vagrantfile"
        log::ok "Vagrant VMs destroyed"
        ;;

    *)
        log::die "Unknown dev runtime '${LIGHT_RUNTIME}'. Use: hybrid | docker | vagrant"
        ;;
esac

log::ok "Dev environment torn down"

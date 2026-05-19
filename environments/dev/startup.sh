#!/usr/bin/env bash
# Dev environment startup.
#
# LIGHT_RUNTIME controls the workload layer:
#   hybrid  (default) — Docker management zone + Vagrant/VirtualBox workload VMs
#   docker             — everything as Docker containers (fast, no VirtualBox needed)
#   vagrant            — everything as VirtualBox VMs (legacy)
#
# Management zone is always Docker in hybrid and docker modes.
# Workload bubble members are always real VMs in hybrid mode.

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${LIGHT_ROOT}/lib/preflight.sh"

COMPOSE_BASE="${LIGHT_ROOT}/environments/dev/docker/docker-compose.yml"
COMPOSE_TOPO="${LIGHT_ROOT}/environments/dev/docker/docker-compose.topology.yml"
TOPOLOGY="${LIGHT_ROOT}/config/topology.json"
ENV_FILE="${LIGHT_ROOT}/config/light.env"
VAGRANT_TOPO="${LIGHT_ROOT}/environments/dev/vagrant/Vagrantfile.topology"

log::section "Starting dev environment (runtime: ${LIGHT_RUNTIME})"

# ── Generate topology artifacts from config/topology.json ─────────────────────
compose_files=(-f "${COMPOSE_BASE}")
BUBBLES=()

if [[ -f "${TOPOLOGY}" ]]; then
    log::section "Generating topology from config/topology.json"
    "${LIGHT_ROOT}/scripts/gen-topology.sh"

    # In docker mode, bubble containers are Docker services — include the overlay.
    # In hybrid mode, bubble members are Vagrant VMs — the overlay is not used.
    if [[ "${LIGHT_RUNTIME}" == "docker" ]]; then
        compose_files+=(-f "${COMPOSE_TOPO}")
    fi

    mapfile -t BUBBLES < <(
        python3 -c "
import json, sys
with open('${TOPOLOGY}') as f: t = json.load(f)
for k in t.get('bubbles', {}):
    if not k.startswith('_'): print(k)
"
    )
    log::info "Service bubbles: ${BUBBLES[*]:-none}"
else
    log::warn "config/topology.json not found — starting management zone only"
fi

# ── Helper: run docker compose with all file flags ─────────────────────────────
dc() {
    docker compose "${compose_files[@]}" --env-file "${ENV_FILE}" "$@"
}

# ── Helper: run ansible via the ansible controller container ───────────────────
# Optional env var BUBBLE_NAME scopes ANSIBLE_ROLES_PATH to include that bubble's roles.
ansible_in_container() {
    local playbook="${1:?}"; shift
    local roles_path="/opt/ansible/roles"
    local ans_ctr="${LIGHT_ENV:-dev}-${LIGHT_LOCATION:-local}-srv-ans-001"
    if [[ -n "${BUBBLE_NAME:-}" ]]; then
        roles_path="${roles_path}:/opt/bubbles/${BUBBLE_NAME}/ansible/roles"
    fi
    # Only add Foreman dynamic inventory when Foreman is reachable and authenticated.
    # Avoids the noisy "401 / Unable to parse" warning on every playbook run.
    local inventories=()
    if curl -sf --max-time 5 \
           -u "${FOREMAN_ADMIN_USER:-admin}:${FOREMAN_ADMIN_PASS:-changeme}" \
           "http://${IP_FOREMAN:-10.10.0.20}:3000/api/v2/status" \
           -o /dev/null 2>/dev/null; then
        inventories+=(-i /opt/ansible/inventory/foreman.yml)
    fi
    inventories+=(-i /opt/ansible/inventory/topology.ini)
    docker exec \
        -e "ANSIBLE_ROLES_PATH=${roles_path}" \
        "${ans_ctr}" \
        ansible-playbook \
            "${inventories[@]}" \
            "/opt/ansible/playbooks/${playbook}" \
            "$@"
}

# ── Helper: inject ip route into a management zone container ──────────────────
# Uses nsenter so the host's iproute2 operates on the container's network namespace,
# avoiding the "ip: executable file not found" error in minimal container images.
inject_route() {
    local container="${1:?}" cidr="${2:?}" via="${3:?}"
    local pid
    pid=$(docker inspect --format '{{.State.Pid}}' "${container}" 2>/dev/null) || return 0
    [[ -z "${pid}" || "${pid}" == "0" ]] && return 0
    nsenter --net="/proc/${pid}/ns/net" -- \
        ip route add "${cidr}" via "${via}" 2>/dev/null || true
}

# ── Helper: allow workload VM subnet to reach the Docker management zone ───────
# Docker's FORWARD chain drops new connections from non-Docker interfaces by
# default. Without this, VMs can't reach DNS/NTP/Puppet/etc. in the mgmt zone.
allow_vm_to_mgmt() {
    local vm_cidr="${1:?}"
    local mgmt_cidr="${MGMT_ZONE_CIDR:-10.10.0.0/24}"
    # Use sudo for both the check and the insert so permission-denied doesn't
    # cause a spurious "rule missing" and an unnecessary interactive sudo prompt.
    sudo iptables -C DOCKER-USER -s "${vm_cidr}" -d "${mgmt_cidr}" -j ACCEPT 2>/dev/null && return 0
    sudo iptables -I DOCKER-USER 1 -s "${vm_cidr}" -d "${mgmt_cidr}" -j ACCEPT 2>/dev/null || \
        log::warn "Could not add iptables FORWARD rule for ${vm_cidr} → ${mgmt_cidr} (cross-zone DNS/NTP will fail)"
}

# ── Helper: get bubble CIDR from topology.json ────────────────────────────────
bubble_cidr() {
    local bubble="${1:?}"
    python3 -c "
import json
with open('${TOPOLOGY}') as f: t = json.load(f)
print(t['bubbles']['${bubble}']['cidr'])
"
}

# ── Helper: wait for SSH on each bubble member ────────────────────────────────
wait_bubble_ssh() {
    local bubble="${1:?}"
    python3 -c "
import json
with open('${TOPOLOGY}') as f: t = json.load(f)
for m in t['bubbles']['${bubble}']['members']:
    print(m['ip'])
" | while read -r ip; do
        wait_for_port "${ip}" 22 120
    done
}

# ── Shared: deploy each bubble via Ansible ────────────────────────────────────
deploy_bubbles() {
    for bubble in "${BUBBLES[@]}"; do
        log::section "Deploying bubble: ${bubble}"

        log::info "Waiting for bubble SSH to be ready"
        wait_bubble_ssh "${bubble}"

        log::info "Running Puppet baseline on bubble ${bubble}"
        ansible_in_container baseline.yml --limit "bubble_${bubble}"

        log::info "Running bubble-deploy playbook for ${bubble}"
        BUBBLE_NAME="${bubble}" ansible_in_container bubble-deploy.yml \
            -e "bubble_name=${bubble}" \
            --limit "bubble_${bubble}"

        log::info "Registering bubble ${bubble} hosts in Foreman"
        ansible_in_container foreman-register.yml --limit "bubble_${bubble}"

        log::info "Registering bubble ${bubble} hosts in Checkmk"
        ansible_in_container checkmk-register.yml --limit "bubble_${bubble}"
    done
}

# ── Shared: bring up Docker management zone ───────────────────────────────────
start_mgmt_zone() {
    log::section "Building images and starting management zone"
    dc up -d --build

    log::section "Waiting for core management services"
    wait_for_port "${IP_PUPPET:-10.10.0.21}"  8140 300
    wait_for_port "${IP_FOREMAN:-10.10.0.20}"  3000 300
    wait_for_port "${IP_CHECKMK:-10.10.0.23}"  5000 240
    wait_for_port "${IP_PULP:-10.10.0.24}"       80 240

    log::section "Reloading DNS to pick up topology records"
    docker exec "${LIGHT_ENV:-dev}-${LIGHT_LOCATION:-local}-srv-dns-001" \
        rndc reload 2>/dev/null || true

    log::section "Running Puppet baseline on management zone"
    ansible_in_container baseline.yml --limit "!bubble_all" || \
        log::warn "No management zone hosts in Foreman yet — skipping baseline"
}

# ── Runtime dispatch ──────────────────────────────────────────────────────────

case "${LIGHT_RUNTIME}" in

    # ── Hybrid (default): Docker mgmt zone + Vagrant workload VMs ────────────
    hybrid)
        preflight_dev_hybrid

        # Cache sudo credentials now so iptables / nsenter calls later don't
        # block in the middle of a long-running step.
        if ! sudo -n true 2>/dev/null; then
            log::info "sudo required for iptables cross-zone rules — enter password once:"
            sudo -v
        fi

        start_mgmt_zone

        if [[ ${#BUBBLES[@]} -gt 0 ]]; then
            # The Docker host bridges both networks:
            #   - mgmt-zone Docker bridge  → 10.10.0.1  (first addr in subnet)
            #   - VirtualBox host-only nets → 10.20.x.1  (per bubble)
            # We inject routes into the three containers that need to reach workload VMs.
            MGMT_GW="${MGMT_GATEWAY:-10.10.0.1}"
            CROSS_ZONE_CONTAINERS=(
                "${LIGHT_ENV:-dev}-${LIGHT_LOCATION:-local}-srv-ans-001"
                "${LIGHT_ENV:-dev}-${LIGHT_LOCATION:-local}-srv-mon-001"
                "${LIGHT_ENV:-dev}-${LIGHT_LOCATION:-local}-srv-vpn-001"
            )

            for bubble in "${BUBBLES[@]}"; do
                cidr="$(bubble_cidr "${bubble}")"
                log::info "Injecting route ${cidr} via ${MGMT_GW} into cross-zone containers"
                for ctr in "${CROSS_ZONE_CONTAINERS[@]}"; do
                    inject_route "${ctr}" "${cidr}" "${MGMT_GW}"
                done
                log::info "Allowing ${cidr} → management zone forwarding in iptables"
                allow_vm_to_mgmt "${cidr}"
            done

            log::section "Starting workload VMs via Vagrant"
            [[ -f "${VAGRANT_TOPO}" ]] || log::die "Vagrantfile.topology not found — run gen-topology.sh first"
            (
                cd "${LIGHT_ROOT}/environments/dev/vagrant"
                VAGRANT_VAGRANTFILE=Vagrantfile.topology vagrant up --provision --no-parallel
            )

            deploy_bubbles
        fi

        log::section "Registering management zone hosts in Foreman"
        ansible_in_container foreman-register.yml --limit "!bubble_all" || \
            log::warn "No management zone hosts registered — skipping Foreman registration"

        log::section "Registering management zone hosts in Checkmk"
        ansible_in_container checkmk-register.yml --limit "!bubble_all" || \
            log::warn "No management zone hosts registered — skipping Checkmk registration"
        ;;

    # ── Docker: everything as Docker containers ───────────────────────────────
    docker)
        preflight_dev_docker
        start_mgmt_zone

        if [[ ${#BUBBLES[@]} -gt 0 ]]; then
            deploy_bubbles
        fi

        log::section "Registering management zone hosts in Foreman"
        ansible_in_container foreman-register.yml --limit "!bubble_all" || \
            log::warn "No management zone hosts registered — skipping Foreman registration"

        log::section "Registering management zone hosts in Checkmk"
        ansible_in_container checkmk-register.yml --limit "!bubble_all" || \
            log::warn "No management zone hosts registered — skipping Checkmk registration"
        ;;

    # ── Vagrant: everything as VirtualBox VMs (legacy) ───────────────────────
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
        log::die "Unknown dev runtime '${LIGHT_RUNTIME}'. Use: hybrid | docker | vagrant"
        ;;
esac

log::section "Dev environment ready"
log::info "Domain:    ${LIGHT_DOMAIN:-simple-test.org}"
log::info "Checkmk:   http://localhost:5000/cmk/"
log::info "Foreman:   http://localhost:9090"
log::info "Pulp:      http://localhost:8080/pulp/api/v3/"
log::info "Jumphost:  ssh -p 2222 admin@localhost"
log::info ""
log::info "Monitor:   ./scripts/dev-status.sh --watch"

if [[ ${#BUBBLES[@]} -gt 0 ]]; then
    log::info ""
    log::info "Service bubbles deployed:"
    for bubble in "${BUBBLES[@]}"; do
        cidr="$(bubble_cidr "${bubble}" 2>/dev/null || echo '?')"
        log::info "  ${bubble}  →  ${cidr}"
        if [[ "${LIGHT_RUNTIME}" == "hybrid" ]]; then
            log::info "              SSH via jumphost: ssh -J admin@localhost:2222 admin@<vm-ip>"
        fi
    done
fi

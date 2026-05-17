#!/usr/bin/env bash
# Show the status of the full dev stack — services, health, access URLs, alerts.
# Usage: ./scripts/dev-status.sh [--logs <service>] [--watch]

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="${LIGHT_ROOT}/environments/dev/docker/docker-compose.yml"
source "${LIGHT_ROOT}/lib/logging.sh"

# ── Parse args ────────────────────────────────────────────────────────────────
SHOW_LOGS=""
WATCH=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --logs) SHOW_LOGS="${2:?'--logs requires a service name'}"; shift 2 ;;
        --watch) WATCH=true; shift ;;
        *) log::die "Unknown option: $1. Use --logs <service> or --watch" ;;
    esac
done

source "${LIGHT_ROOT}/config/light.env" 2>/dev/null || true
DOMAIN="${LIGHT_DOMAIN:-simple-test.org}"
ENV="${LIGHT_ENV:-dev}"
LOC="${LIGHT_LOCATION:-local}"

# ── Colours (no dependency on lib/logging.sh colour wrappers) ─────────────────
green='\e[32m'; red='\e[31m'; yellow='\e[33m'; cyan='\e[36m'; bold='\e[1m'; reset='\e[0m'

status_icon() {
    local state="$1"
    case "${state}" in
        *healthy*)  printf "${green}●${reset}" ;;
        *running*)  printf "${yellow}◐${reset}" ;;
        *starting*) printf "${yellow}◌${reset}" ;;
        *exited*)   printf "${red}✗${reset}" ;;
        *)          printf "${red}?${reset}" ;;
    esac
}

print_status() {
    printf '\n%b══ light dev status — %s ══%b\n' "${bold}${cyan}" "$(date '+%Y-%m-%dT%H:%M:%S')" "${reset}"

    printf '\n%bManagement Zone  (%s)%b\n' "${bold}" "${MGMT_ZONE_CIDR:-10.10.0.0/24}" "${reset}"
    printf '%-6s %-42s %-18s %s\n' "STATE" "CONTAINER" "IP" "UPTIME"
    printf '%s\n' "──────────────────────────────────────────────────────────────────────"

    # Pull container data from docker inspect
    local services=(
        "dns-primary:${IP_DNS_PRIMARY:-10.10.0.30}:DNS"
        "ntp-primary:${IP_NTP_PRIMARY:-10.10.0.32}:NTP"
        "pulp:${IP_PULP:-10.10.0.24}:Pulp"
        "puppet:${IP_PUPPET:-10.10.0.21}:Puppet"
        "foreman:${IP_FOREMAN:-10.10.0.20}:Foreman"
        "ansible:${IP_ANSIBLE:-10.10.0.22}:Ansible"
        "checkmk:${IP_CHECKMK:-10.10.0.23}:Checkmk"
        "jumphost:${IP_JUMPHOST:-10.10.0.10}:Jumphost"
    )

    for entry in "${services[@]}"; do
        IFS=: read -r svc ip label <<< "${entry}"
        container_name="${ENV}-${LOC}-srv"
        # Map service name to function code
        case "${svc}" in
            dns-primary) func="dns-001" ;;
            ntp-primary) func="ntp-001" ;;
            pulp)        func="upd-001" ;;
            puppet)      func="bas-001" ;;
            foreman)     func="frm-001" ;;
            ansible)     func="ans-001" ;;
            checkmk)     func="mon-001" ;;
            jumphost)    func="vpn-001" ;;
        esac
        container="${ENV}-${LOC}-srv-${func}"
        state=$(docker inspect --format '{{.State.Health.Status}}{{if not .State.Health}}{{.State.Status}}{{end}}' \
                "${container}" 2>/dev/null || echo "missing")
        uptime=$(docker inspect --format '{{.State.StartedAt}}' "${container}" 2>/dev/null \
                 | xargs -I{} bash -c 'echo $(( ($(date +%s) - $(date -d "{}" +%s)) / 60 ))m' 2>/dev/null || echo "-")
        icon=$(status_icon "${state}")
        printf '%b  %-40s %-18s %s\n' "${icon}" "${container}" "${ip}" "${uptime}"
    done

    printf '\n%bWorkload Zone  (%s)%b\n' "${bold}" "${WORKLOAD_CIDR:-10.20.0.0/24}" "${reset}"
    printf '%-6s %-42s %-18s %s\n' "STATE" "CONTAINER" "IP" "UPTIME"
    printf '%s\n' "──────────────────────────────────────────────────────────────────────"

    local workloads=(
        "workload-web-001:10.20.0.11"
        "workload-db-001:10.20.0.12"
    )
    for entry in "${workloads[@]}"; do
        IFS=: read -r svc ip <<< "${entry}"
        container="${ENV}-${LOC}-srv-${svc#workload-}"
        state=$(docker inspect --format '{{.State.Health.Status}}{{if not .State.Health}}{{.State.Status}}{{end}}' \
                "${container}" 2>/dev/null || echo "missing")
        uptime=$(docker inspect --format '{{.State.StartedAt}}' "${container}" 2>/dev/null \
                 | xargs -I{} bash -c 'echo $(( ($(date +%s) - $(date -d "{}" +%s)) / 60 ))m' 2>/dev/null || echo "-")
        icon=$(status_icon "${state}")
        printf '%b  %-40s %-18s %s\n' "${icon}" "${container}" "${ip}" "${uptime}"
    done

    printf '\n%bAccess URLs (local port forwards)%b\n' "${bold}" "${reset}"
    printf '  Checkmk  (monitoring)   →  %bhttp://localhost:5000/cmk/%b\n'      "${cyan}" "${reset}"
    printf '  Foreman  (inventory)    →  %bhttps://localhost:9443%b\n'           "${cyan}" "${reset}"
    printf '  Pulp     (pkg mirror)   →  %bhttp://localhost:8080/pulp/api/v3/%b\n' "${cyan}" "${reset}"
    printf '  Puppet   (agent port)   →  %blocalhost:8140%b\n'                   "${cyan}" "${reset}"
    printf '  Jumphost (SSH bastion)  →  %bssh -p 2222 admin@localhost%b\n'      "${cyan}" "${reset}"

    printf '\n%bNetwork isolation check%b\n' "${bold}" "${reset}"
    # Verify workload cannot reach external internet directly
    local web_container="${ENV}-${LOC}-srv-web-001"
    if docker exec "${web_container}" curl -fs --max-time 3 https://1.1.1.1 &>/dev/null 2>&1; then
        printf '  %b✗ WARN%b  workload-web-001 can reach external internet (expected: blocked)\n' "${yellow}" "${reset}"
    else
        printf '  %b● OK%b    workload-web-001 cannot reach external internet (firewall working)\n' "${green}" "${reset}"
    fi
    # Verify workload can reach Pulp
    if docker exec "${web_container}" curl -fs --max-time 5 \
            "http://${IP_PULP:-10.10.0.24}/pulp/api/v3/status/" &>/dev/null 2>&1; then
        printf '  %b● OK%b    workload-web-001 → Pulp mirror reachable\n' "${green}" "${reset}"
    else
        printf '  %b◐ INFO%b  workload-web-001 → Pulp mirror not yet ready\n' "${yellow}" "${reset}"
    fi

    printf '\n%bPuppet last run (workload-web-001)%b\n' "${bold}" "${reset}"
    docker exec "${web_container}" \
        /opt/puppetlabs/bin/puppet agent --last-run-report 2>/dev/null \
        | grep -E 'time|changed|failed' | head -5 || printf '  (not yet run)\n'

    printf '\n'
}

# ── Log tail mode ─────────────────────────────────────────────────────────────
if [[ -n "${SHOW_LOGS}" ]]; then
    log::info "Tailing logs for: ${SHOW_LOGS}"
    docker compose -f "${COMPOSE}" logs -f --tail=50 "${SHOW_LOGS}"
    exit 0
fi

# ── Watch mode ────────────────────────────────────────────────────────────────
if ${WATCH}; then
    while true; do
        clear
        print_status
        sleep 15
    done
fi

print_status

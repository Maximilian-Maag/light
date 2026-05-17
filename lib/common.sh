#!/usr/bin/env bash
# Shared utilities — source this file, do not execute directly.

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=lib/logging.sh
source "${LIGHT_ROOT}/lib/logging.sh"

# ── Config loading ─────────────────────────────────────────────────────────────

load_config() {
    local cfg="${LIGHT_ROOT}/config/light.env"
    [[ -f "${cfg}" ]] || log::die "config/light.env not found. Copy config/light.env.example and fill in your values."
    # set -a exports every variable defined while sourcing the file so that
    # child processes launched via exec also see the full config.
    set -a
    # shellcheck source=/dev/null
    source "${cfg}"
    set +a
    log::info "Config loaded from ${cfg}"
}

# ── Hostname builder ──────────────────────────────────────────────────────────
# Usage: build_hostname <type> <function> <seq>
# Example: build_hostname srv web 001  →  dev-local-srv-web-001

build_hostname() {
    local type="${1:?}" func="${2:?}" seq="${3:?}"
    printf '%s-%s-%s-%s-%s' \
        "${LIGHT_ENV}" "${LIGHT_LOCATION}" "${type}" "${func}" "${seq}"
}

build_fqdn() {
    printf '%s.%s' "$(build_hostname "$@")" "${LIGHT_DOMAIN}"
}

# ── Provider guard ────────────────────────────────────────────────────────────

require_provider() {
    local allowed=("$@")
    local ok=false
    for p in "${allowed[@]}"; do
        [[ "${LIGHT_PROVIDER}" == "${p}" ]] && ok=true && break
    done
    ${ok} || log::die "Provider '${LIGHT_PROVIDER}' not supported for this environment. Allowed: ${allowed[*]}"
}

# ── Command guards ────────────────────────────────────────────────────────────

require_cmd() {
    for cmd in "$@"; do
        command -v "${cmd}" &>/dev/null || log::die "Required command not found: ${cmd}"
    done
}

# ── Terraform wrapper ─────────────────────────────────────────────────────────

tf() {
    local dir="${1:?}"; shift
    log::info "Terraform ${*} in ${dir}"
    terraform -chdir="${dir}" "$@"
}

tf_init_apply() {
    local dir="${1:?}"
    tf "${dir}" init -input=false
    tf "${dir}" apply -auto-approve -input=false
}

tf_destroy() {
    local dir="${1:?}"
    tf "${dir}" init -input=false
    tf "${dir}" destroy -auto-approve -input=false
}

# ── Ansible wrapper ───────────────────────────────────────────────────────────

ansible_play() {
    local playbook="${1:?}"; shift
    log::info "Running playbook ${playbook}"
    ansible-playbook \
        -i "${LIGHT_ROOT}/ansible/inventory/foreman.yml" \
        "${LIGHT_ROOT}/ansible/playbooks/${playbook}" \
        "$@"
}

# ── Wait helper ───────────────────────────────────────────────────────────────

wait_for_port() {
    local host="${1:?}" port="${2:?}" timeout="${3:-120}"
    log::info "Waiting for ${host}:${port} (timeout ${timeout}s)"
    local elapsed=0
    until nc -z "${host}" "${port}" 2>/dev/null; do
        sleep 5; elapsed=$((elapsed + 5))
        [[ ${elapsed} -ge ${timeout} ]] && log::die "Timed out waiting for ${host}:${port}"
    done
    log::ok "${host}:${port} reachable"
}

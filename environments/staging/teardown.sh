#!/usr/bin/env bash
set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${LIGHT_ROOT}/lib/common.sh"

TF_DIR="${LIGHT_ROOT}/environments/staging/terraform/${LIGHT_PROVIDER}"
[[ -d "${TF_DIR}" ]] || log::die "No Terraform config for provider '${LIGHT_PROVIDER}' at ${TF_DIR}"

log::section "Deregistering from Checkmk"
ansible_play checkmk-deregister.yml || log::warn "Checkmk deregister failed — continuing"

log::section "Deregistering from Foreman"
ansible_play foreman-deregister.yml || log::warn "Foreman deregister failed — continuing"

log::section "Destroying infrastructure on ${LIGHT_PROVIDER}"
tf_destroy "${TF_DIR}"

log::ok "Staging environment destroyed"

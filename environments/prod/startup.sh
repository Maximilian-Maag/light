#!/usr/bin/env bash
# Production environment startup — full management zone + workload nodes.
# On-prem uses existing VMware/NSX infrastructure bootstrapped via Terraform
# VMware provider; cloud providers mirror staging topology at production scale.

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${LIGHT_ROOT}/lib/preflight.sh"

preflight_prod

TF_DIR="${LIGHT_ROOT}/environments/prod/terraform/${LIGHT_PROVIDER}"
[[ -d "${TF_DIR}" ]] || log::die "No Terraform config for provider '${LIGHT_PROVIDER}' at ${TF_DIR}"

log::section "Provisioning management zone on ${LIGHT_PROVIDER} (prod)"
tf_init_apply "${TF_DIR}"

log::section "Waiting for management zone services"
wait_for_port "${IP_PUPPET}"  8140 600
wait_for_port "${IP_FOREMAN}" 443  600
wait_for_port "${IP_CHECKMK}" 443  360
wait_for_port "${IP_PULP}"    80   360

log::section "Syncing package repositories (Pulp)"
ansible_play pulp-sync.yml

log::section "Running Puppet baseline on all nodes"
ansible_play baseline.yml --limit all

log::section "Deploying applications"
ansible_play site.yml

log::section "Registering hosts in Foreman"
ansible_play foreman-register.yml

log::section "Registering hosts in Checkmk — configuring alert routing"
ansible_play checkmk-register.yml

log::section "Production environment ready"
log::info "Domain:    ${LIGHT_DOMAIN}"
log::info "Jumphost:  ssh admin@${IP_JUMPHOST} -p 22"
log::info "Foreman:   https://${IP_FOREMAN}"
log::info "Checkmk:   https://${IP_CHECKMK}"
log::warn "All SSH access must go via the Jumphost. Direct VM access is blocked."

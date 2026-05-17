#!/usr/bin/env bash
# Staging environment startup — provisions full management zone + workload nodes
# on a cloud provider (Linode | AWS | GCP) via Terraform + Ansible + Puppet.

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${LIGHT_ROOT}/lib/preflight.sh"

preflight_staging

TF_DIR="${LIGHT_ROOT}/environments/staging/terraform/${LIGHT_PROVIDER}"
[[ -d "${TF_DIR}" ]] || log::die "No Terraform config for provider '${LIGHT_PROVIDER}' at ${TF_DIR}"

log::section "Provisioning management zone on ${LIGHT_PROVIDER}"
tf_init_apply "${TF_DIR}"

log::section "Waiting for management zone services"
wait_for_port "${IP_PUPPET}"  8140 300
wait_for_port "${IP_FOREMAN}" 443  300
wait_for_port "${IP_CHECKMK}" 443  240
wait_for_port "${IP_PULP}"    80   240

log::section "Syncing package repositories (Pulp)"
ansible_play pulp-sync.yml

log::section "Running Puppet baseline on all nodes"
ansible_play baseline.yml --limit all

log::section "Deploying applications"
ansible_play site.yml

log::section "Registering hosts in Foreman"
ansible_play foreman-register.yml

log::section "Registering hosts in Checkmk"
ansible_play checkmk-register.yml

log::section "Staging environment ready"
log::info "Domain:    ${LIGHT_DOMAIN}"
log::info "Jumphost:  ssh admin@${IP_JUMPHOST}"
log::info "Foreman:   https://${IP_FOREMAN}"
log::info "Checkmk:   https://${IP_CHECKMK}"

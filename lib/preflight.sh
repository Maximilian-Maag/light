#!/usr/bin/env bash
# Pre-flight checks — source this file, do not execute directly.

# shellcheck source=lib/common.sh
source "${LIGHT_ROOT}/lib/common.sh"

preflight_common() {
    log::section "Pre-flight checks"
    require_cmd curl nc

    [[ -n "${LIGHT_DOMAIN}" ]]   || log::die "LIGHT_DOMAIN is not set"
    [[ -n "${LIGHT_ENV}" ]]      || log::die "LIGHT_ENV is not set"
    [[ -n "${LIGHT_PROVIDER}" ]] || log::die "LIGHT_PROVIDER is not set"
    [[ -n "${LIGHT_LOCATION}" ]] || log::die "LIGHT_LOCATION is not set"
    # Allow ADMIN_SSH_KEY_PRIVATE to be absent from older light.env files by
    # deriving it from the public key path (strip the .pub suffix).
    export ADMIN_SSH_KEY_PRIVATE="${ADMIN_SSH_KEY_PRIVATE:-${ADMIN_SSH_KEY_PATH%.pub}}"
    [[ -f "${ADMIN_SSH_KEY_PATH}" ]]    || log::die "SSH public key not found: ${ADMIN_SSH_KEY_PATH}"
    [[ -f "${ADMIN_SSH_KEY_PRIVATE}" ]] || log::die "SSH private key not found: ${ADMIN_SSH_KEY_PRIVATE}"

    log::ok "Common checks passed"
}

preflight_dev_docker() {
    preflight_common
    require_cmd docker docker-compose
    docker info &>/dev/null || log::die "Docker daemon is not running"
    log::ok "Dev/docker checks passed"
}

preflight_dev_vagrant() {
    preflight_common
    require_cmd vagrant VBoxManage
    log::ok "Dev/vagrant checks passed"
}

preflight_dev_hybrid() {
    preflight_common
    require_cmd docker
    docker info &>/dev/null || log::die "Docker daemon is not running"
    require_cmd vagrant VBoxManage
    log::ok "Dev/hybrid checks passed"
}

preflight_staging() {
    preflight_common
    require_cmd terraform ansible ansible-playbook

    case "${LIGHT_PROVIDER}" in
        linode) [[ -n "${LINODE_TOKEN}" ]]          || log::die "LINODE_TOKEN is not set" ;;
        aws)    [[ -n "${AWS_ACCESS_KEY_ID}" ]]     || log::die "AWS_ACCESS_KEY_ID is not set"
                [[ -n "${AWS_SECRET_ACCESS_KEY}" ]] || log::die "AWS_SECRET_ACCESS_KEY is not set" ;;
        gcp)    [[ -n "${GCP_PROJECT}" ]]           || log::die "GCP_PROJECT is not set"
                [[ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]] \
                    || log::die "GOOGLE_APPLICATION_CREDENTIALS file not found" ;;
        *)      log::die "Unknown staging provider: ${LIGHT_PROVIDER}" ;;
    esac
    log::ok "Staging checks passed"
}

preflight_prod() {
    preflight_common
    require_cmd terraform ansible ansible-playbook puppet

    case "${LIGHT_PROVIDER}" in
        on-prem) ;;  # on-prem bootstrap is manual — no extra credentials needed here
        aws|gcp|linode) preflight_staging ;;  # reuse cloud checks
        *) log::die "Unknown prod provider: ${LIGHT_PROVIDER}" ;;
    esac
    log::ok "Prod checks passed"
}

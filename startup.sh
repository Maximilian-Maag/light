#!/usr/bin/env bash
# light — startup entry point
#
# Usage:
#   ./startup.sh dev    [docker|vagrant]      (default runtime: docker)
#   ./startup.sh staging [linode|aws|gcp]     (default provider: linode)
#   ./startup.sh prod   [on-prem|aws|gcp|linode]
#
# All environments deploy the full management zone (Jumphost, Foreman, Puppet,
# Ansible, Checkmk, Pulp, DNS, NTP) plus workload nodes — no environment is
# a subset of another.

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIGHT_ROOT}/lib/common.sh"

load_config

LIGHT_ENV="${1:-${LIGHT_ENV}}"
ARG2="${2:-}"

case "${LIGHT_ENV}" in
    dev)
        [[ -n "${ARG2}" ]] && LIGHT_RUNTIME="${ARG2}"
        LIGHT_RUNTIME="${LIGHT_RUNTIME:-docker}"
        LIGHT_PROVIDER="local"
        export LIGHT_ENV LIGHT_PROVIDER LIGHT_RUNTIME
        exec "${LIGHT_ROOT}/environments/dev/startup.sh"
        ;;
    staging)
        [[ -n "${ARG2}" ]] && LIGHT_PROVIDER="${ARG2}"
        LIGHT_PROVIDER="${LIGHT_PROVIDER:-linode}"
        export LIGHT_ENV LIGHT_PROVIDER
        exec "${LIGHT_ROOT}/environments/staging/startup.sh"
        ;;
    prod)
        [[ -n "${ARG2}" ]] && LIGHT_PROVIDER="${ARG2}"
        LIGHT_PROVIDER="${LIGHT_PROVIDER:-on-prem}"
        export LIGHT_ENV LIGHT_PROVIDER
        exec "${LIGHT_ROOT}/environments/prod/startup.sh"
        ;;
    *)
        log::die "Unknown environment '${LIGHT_ENV}'. Use: dev | staging | prod"
        ;;
esac

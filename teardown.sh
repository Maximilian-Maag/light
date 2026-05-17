#!/usr/bin/env bash
# light — teardown entry point
#
# Usage:
#   ./teardown.sh dev    [docker|vagrant]
#   ./teardown.sh staging [linode|aws|gcp]
#   ./teardown.sh prod   [on-prem|aws|gcp|linode]
#
# WARNING: This destroys ALL infrastructure for the given environment.

set -euo pipefail

LIGHT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${LIGHT_ROOT}/lib/common.sh"

load_config

LIGHT_ENV="${1:-${LIGHT_ENV}}"
ARG2="${2:-}"

log::warn "About to DESTROY the '${LIGHT_ENV}' environment. This is irreversible."
read -r -p "Type the environment name to confirm: " confirm
[[ "${confirm}" == "${LIGHT_ENV}" ]] || log::die "Confirmation did not match. Aborting."

case "${LIGHT_ENV}" in
    dev)
        [[ -n "${ARG2}" ]] && LIGHT_RUNTIME="${ARG2}"
        LIGHT_RUNTIME="${LIGHT_RUNTIME:-docker}"
        LIGHT_PROVIDER="local"
        export LIGHT_ENV LIGHT_PROVIDER LIGHT_RUNTIME
        exec "${LIGHT_ROOT}/environments/dev/teardown.sh"
        ;;
    staging)
        [[ -n "${ARG2}" ]] && LIGHT_PROVIDER="${ARG2}"
        LIGHT_PROVIDER="${LIGHT_PROVIDER:-linode}"
        export LIGHT_ENV LIGHT_PROVIDER
        exec "${LIGHT_ROOT}/environments/staging/teardown.sh"
        ;;
    prod)
        [[ -n "${ARG2}" ]] && LIGHT_PROVIDER="${ARG2}"
        LIGHT_PROVIDER="${LIGHT_PROVIDER:-on-prem}"
        export LIGHT_ENV LIGHT_PROVIDER
        exec "${LIGHT_ROOT}/environments/prod/teardown.sh"
        ;;
    *)
        log::die "Unknown environment '${LIGHT_ENV}'. Use: dev | staging | prod"
        ;;
esac

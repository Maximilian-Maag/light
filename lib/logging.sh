#!/usr/bin/env bash
# Logging helpers — source this file, do not execute directly.

readonly _LIGHT_LOG_TS_FMT="%Y-%m-%dT%H:%M:%S"

_ts() { date +"${_LIGHT_LOG_TS_FMT}"; }

log::info()    { printf '\e[32m[INFO ]\e[0m %s %s\n'  "$(_ts)" "$*"; }
log::warn()    { printf '\e[33m[WARN ]\e[0m %s %s\n'  "$(_ts)" "$*" >&2; }
log::error()   { printf '\e[31m[ERROR]\e[0m %s %s\n'  "$(_ts)" "$*" >&2; }
log::section() { printf '\n\e[1;34m══ %s ══\e[0m\n\n' "$*"; }
log::ok()      { printf '\e[32m[  OK ]\e[0m %s %s\n'  "$(_ts)" "$*"; }
log::die()     { log::error "$*"; exit 1; }

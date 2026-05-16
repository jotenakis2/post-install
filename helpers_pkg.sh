#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_EXIST() {
    local cmd
    cmd=$1
    command -v "${cmd}" &>/dev/null && return 0
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_IS_FPPKG_INSTALLED() {
    flatpak info "$@" &>/dev/null || return 1
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_FPPKG_INSTALL() {
    flatpak install -y flathub "$@"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_IS_CARGOPKG_INSTALLED() {
    #echo "${INSTALLED_LIST}" | grep -q "$@"
    local list
    list=$(cargo install --list 2>/dev/null)
    echo "${list}" | grep -q "$@"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_CARGOPKG_INSTALL() {
    local jobs cpu_jobs avail_kib avail_gib ram_jobs

    cpu_jobs=$(( $(nproc) - 1 ))
    (( cpu_jobs < 1 )) && cpu_jobs=1

    avail_kib=$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)
    avail_gib=$(( avail_kib / 1024 / 1024 ))

    ram_jobs=$(( avail_gib / 2 ))
    (( ram_jobs < 1 )) && ram_jobs=1

    jobs=$(( cpu_jobs < ram_jobs ? cpu_jobs : ram_jobs ))
    (( jobs < 1 )) && jobs=1

    _LOG "cargo: ${jobs} job(s), MemAvailable=${avail_gib} GiB"
    TMPDIR=/var/tmp \
    CARGO_TARGET_DIR=/var/tmp/cargo-target \
    CARGO_BUILD_JOBS="${jobs}" \
    RUSTFLAGS='-C codegen-units=1' \
    nice -n 10 cargo binstall --no-confirm "$@"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_GOPKG_INSTALL() {
    local jobs cpu_jobs avail_kib avail_gib ram_jobs

    cpu_jobs=$(( $(nproc) - 1 ))
    (( cpu_jobs < 1 )) && cpu_jobs=1

    avail_kib=$(awk '/^MemAvailable:/ { print $2; exit }' /proc/meminfo)
    avail_gib=$(( avail_kib / 1024 / 1024 ))

    ram_jobs=$(( avail_gib / 2 ))
    (( ram_jobs < 1 )) && ram_jobs=1

    jobs=$(( cpu_jobs < ram_jobs ? cpu_jobs : ram_jobs ))
    (( jobs < 1 )) && jobs=1
    (( jobs > 4 )) && jobs=4

    _LOG "go: ${jobs} job(s), MemAvailable=${avail_gib} GiB"
    GOMAXPROCS="${jobs}" nice -n 10 go install "$@"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_IS_ENABLED() {
    systemctl is-enabled --quiet "$@" 2>>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_IS_ACTIVE() {
    systemctl is-active --quiet "$@" 2>>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_IS_ENABLED_USER() {
    systemctl --user is-enabled --quiet "$@" 2>>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_IS_ACTIVE_USER() {
    systemctl --user is-active --quiet "$@" 2>>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

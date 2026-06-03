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

_USER_SERVICE_EXIST() {
    systemctl list-unit-files --user | grep -q "$@" 2>>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_SERVICE_EXIST() {
    systemctl list-unit-files | grep -q "$@" 2>>"${LOG_FILE:-/dev/null}"
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

_PKG_CONFIG() {
    # shellcheck disable=SC2154
    if [[ "${DISTRO,,}" = "fedora" ]]; then
        local dnf="/etc/dnf/dnf.conf"
        if ! sudo grep -q "defaultyes=True" "${dnf}" 2>/dev/null || ! sudo grep -q "fastestmirror=True" "${dnf}" 2>/dev/null || ! sudo grep -q "max_parallel_downloads=10" "${dnf}" 2>/dev/null || ! sudo grep -q "countme=False" "${dnf}" 2>/dev/null; then
            _BACKUP_FILE "${dnf}"
            _ETC_FILES_ADD "${dnf}"
            _RUNSILENT "" sudo dnf config-manager setopt max_parallel_downloads=15 fastestmirror=True countme=False defaultyes=True
        fi
    else
        _LOG "pas Fedora => je ne fait rien au gestionnaire de paquets pour le moment"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_PKG_INSTALL_SKIP() {
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi
    sudo dnf install --skip-unavailable -y "$@"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_PKG_INSTALL() {
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi
    sudo dnf install -y "$@"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_PKG_DOWNLOAD_THEN_INSTALL() {
    local download_dir
    download_dir=$(mktemp -d ./dnf-packages.XXXXXX)
    echo "${download_dir}"
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi
    if [[ -z "${download_dir:-}" ]]; then
        echo "ERREUR: dossier de téléchargement des paquets non défini."
        exit 1
    fi
    local arch
    arch=$(uname -m)
    echo "Téléchargement depuis les dépôts dans ${download_dir}... "
    # shellcheck disable=SC2154
    _RUNSILENT "" sudo dnf download --skip-unavailable -y --arch "${arch}" --arch noarch --resolve --destdir="${download_dir}" "$@"
    echo "installation depuis le cache local..."
    if ! compgen -G "${download_dir}/*.rpm" > /dev/null; then
        _ERR "Aucun paquet système à installer"
        _RUNSILENT "" sudo rm -rvf -- "${download_dir}"
        return 0
    fi
    _RUNSILENT "" sudo dnf install --skip-unavailable -y "${download_dir}"/*.rpm
    _RUNSILENT "" sudo rm -rvf -- "${download_dir}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_SYS_UPDATE() {
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi
    sudo dnf upgrade -y
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_PKG_REMOVE() {
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi
    sudo dnf remove -y "$@"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_IS_PKG_REMOVED() {
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi
    ! rpm -q "$@" &>>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_IS_PKG_INSTALLED() {
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi
    rpm -q "$@" &>>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_REFRESH_SYS_CACHE() {
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi
    local sentinel="/var/cache/dnf/.last_makecache"
    local max_age=3600
    local now sentinel_mtime age

    now=$(date +%s)
    sentinel_mtime=$(stat -c %Y "${sentinel}" 2>/dev/null || echo 0)
    age=$((now - sentinel_mtime))

    if [[ ${age} -gt ${max_age} ]]; then
        _RUN "Mise à jour du cache des métadonnées des dépôts" sudo dnf makecache --refresh
        sudo touch "${sentinel}"
    else
        _LOG "Cache DNF à jour (${age}s < ${max_age}s)"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

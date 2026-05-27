#!/usr/bin/env bash
set -euo pipefail

########################################################################################################################
# FONCTIONS HELPERS                                                                                                    #
########################################################################################################################
# shellcheck source=./helpers_ui.sh
source ./helpers_ui.sh
# shellcheck source=./helpers_grub.sh
source ./helpers_grub.sh
# shellcheck source=./helpers_pkg.sh
source ./helpers_pkg.sh

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_INSTALL_ETC_FILES() {
    local msg="$1"
    local content="$2"
    local file="$3"
    local rights="$4"
    readonly msg content file rights
    _LOG "${msg^^}"
    if sudo test -f "${file}" && printf '%s' "${content}" | sudo cmp -s - "${file}"; then
        _INFO "${msg^} déjà OK (${file})"
        # shellcheck disable=SC2154
        echo 1 >"${STATUSFILE}"
    else
        _OK "Configuration ${msg} (${file})"
        printf '%s' "${content}" | sudo tee "${file}" >/dev/null
        _RUNSILENT "" sudo chmod -v "${rights}" "${file}"
        _ETC_FILES_ADD "${file}"
        echo 0 >"${STATUSFILE}"
    fi
    {
        sudo ls -l "${file}"
        sudo cat "${file}"
        echo ""
    } >>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_IN_ARRAY() {
    local needle="$1"
    shift
    printf '%s\n' "$@" | grep -qxF "${needle}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_GET_PHYSICAL_IFACE() {
    find /sys/class/net/ -type l ! -lname '*/devices/virtual/net/*' -printf '%f\n'
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_SYMLINK() {
    local src="$1"
    local dst="$2"

    if [[ -L "${dst}" ]]; then
        local current_target
        current_target=$(readlink "${dst}")

        if [[ "${current_target}" = "${src}" ]]; then
            # shellcheck disable=SC2154
            echo 2 >"${LINKFILE}"
        else
            _ERR "Lien ${dst} existe déjà mais pointe vers ${current_target}, pas vers ${src}. Je ne change rien."
            echo 1 >"${LINKFILE}"
        fi
    else
        sudo mkdir -p "$(dirname "${dst}")"
        if sudo ln -s "${src}" "${dst}"; then
            _OK "Lien créé : ${dst} => ${src}"
            echo 0 >"${LINKFILE}"
        else
            _ERR "Échec de création du lien : ${dst} => ${src}"
            echo 1 >"${LINKFILE}"
        fi
    fi
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_PLASMA_EVAL() {
    local script="$1"
    busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "${script}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_PLASMA_GET_PANEL_LOCATION() {
    busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s 'var allPanels = panels(); for (var i = 0; i < allPanels.length; i++) {print(allPanels[i].location);}' | awk '{print $2}' | tr -d '"' || true
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_DETECT_GRUB() {
    # 1. BIOS/Legacy = forcément GRUB
    if [[ ! -d /sys/firmware/efi ]]; then
        echo "true"
        return 0
    fi

    # 2. Interrogation bootctl
    if command -v bootctl >/dev/null 2>&1; then
        local current_product=""
        current_product=$(bootctl status 2>/dev/null | awk '/^Current Boot Loader:/ {flag=1} flag && /Product:/ {print $0; exit}' || true)

        if echo "${current_product}" | grep -qi "systemd-boot"; then
            echo "false"
            return 0
        fi
        if echo "${current_product}" | grep -qi "GRUB"; then
            echo "true"
            return 0
        fi
    fi

    # 3. Analyse binaire
    local efi_payload="/boot/efi/EFI/fedora/grubx64.efi"
    if [[ -f "${efi_payload}" ]] && command -v strings >/dev/null 2>&1; then
        # shellcheck disable=SC2312
        if sudo strings "${efi_payload}" | grep -qi "systemd-boot"; then
            echo "false"
            return 0
        fi
        # shellcheck disable=SC2312
        if sudo strings "${efi_payload}" | grep -qw "GRUB"; then
            echo "true"
            return 0
        fi
    fi

    # Par défaut, si introuvable
    echo "false"
    return 0
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_DIR_IS_SAFE_TO_RESTORE() {
    # renvoie 0 si le dossier testé n'existe pas ou s'il existe mais ne contient aucun fichier non vide
    local dir=$1
    [[ -d "${dir}" ]] || return 0

    local found
    found=$(find "${dir}" -type f ! -empty -print -quit)
    if [[ -z "${found}" ]]; then return 0; else return 1; fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_MANAGE_TABLE() {
    # Usage: _MANAGE_TABLE message <test_cmd> <cmd_execute> val1 val2 val3 ...
    local test_cmd="$1"
    local install_cmd="$2"
    shift 2
    local list
    list="$*"
    if [[ "${list}" != "" ]]; then
        local -a missing=()
        local -a present=()
        local pkg
        for pkg in "$@"; do
            if "${test_cmd}" "${pkg}"; then
                present+=("${pkg}")
            else
                missing+=("${pkg}")
            fi
        done

        local test
        case "${test_cmd}" in
            _IS_PKG_INSTALLED) test="paquet présent" ;;
            _IS_PKG_REMOVED) test="paquet absent" ;;
            _IS_FPPKG_INSTALLED) test="paquet présent" ;;
            _IS_CARGOPKG_INSTALLED) test="paquet présent" ;;
            *) test="${test_cmd}" ;;
        esac
        local treat
        case "${install_cmd}" in
            _PKG_INSTALL*) treat="installation" ;;
            _PKG_DOWNLOAD_THEN_INSTALL) treat="installation" ;;
            _PKG_REMOVE) treat="suppression" ;;
            _CARGOPKG_INSTALL) treat="installation" ;;
            _FPPKG_INSTALL) treat="installation" ;;
            *) treat="${install_cmd}" ;;
        esac

        local all_fmt
        local missing_fmt
        local present_fmt
        if ((${#missing[@]})); then
            missing_fmt=$(_FORMAT_LIST "${missing[@]}")
            present_fmt=$(_FORMAT_LIST "${present[@]}")
            if ((${#present[@]})); then
                _LOG "Paquets à IGNORER car réussissant le test \"${test}\" : "
                local a
                a=$(_PRINT_LIST "${present_fmt}")
                echo "${a}" | tee -a "${LOG_FILE:-/dev/null}" >/dev/null
            fi
            _LOG "Paquets à TRAITER car échouant au test \"${test}\" : "
            _INFO "Paquets à traiter"
            local a b
            a=$(_PRINT_LIST "${missing_fmt}")
            echo "${a}" | tee -a "${LOG_FILE:-/dev/null}"
            _RUN "${treat^} en cours..." "${install_cmd}" "${missing[@]}"
            printf '\e[1A\e[2K' # je remonte d'une ligne et je la vide, pour écraser le "en cours..."

            # on vérifie
            local -a missingconfirm=() missingconfirm_fmt
            for pkg in "$@"; do
                if ! "${test_cmd}" "${pkg}"; then
                    missingconfirm+=("${pkg}")
                fi
            done
            if [[ -z "${missingconfirm[*]}" ]]; then
                _OK "Traitement terminé, ${treat} OK"
            else
                _ERR "Traitement terminé, échec ${treat} pour :"
                missingconfirm_fmt=$(_FORMAT_LIST "${missingconfirm[@]}")
                b=$(_PRINT_LIST "${missingconfirm_fmt}")
                echo "${b}" | tee -a "${LOG_FILE:-/dev/null}"
            fi

        else
            all_fmt=$(_FORMAT_LIST "$@")
            local c
            c=$(_PRINT_LIST "${all_fmt}")
            _INFO "Tout a été traité (${treat}) : "
            echo "${c}" | tee -a "${LOG_FILE:-/dev/null}"
        fi
    else
        _INFO "Rien à traiter, liste transmise vide..."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_ETC_FILES_ADD() {
    local entry="$1"
    local item
    for item in "${ETC_FILES[@]}"; do
        [[ "${item}" == "${entry}" ]] && return 0
    done
    ETC_FILES+=("${entry}")
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_FORMAT_LIST() {
    local -a items=("$@")
    local count result i

    count=${#items[@]}
    result=""
    case ${count} in
    0) echo "" ;;
    1) echo "${items[0]}" ;;
    2) echo "${items[0]} et ${items[1]}" ;;
    *)
        for ((i = 0; i < count - 1; i++)); do
            [[ -n "${result}" ]] && result+=", "
            result+="${items[${i}]}"
        done
        echo "${result} et ${items[-1]}"
        ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_GET_SWAPPINESS() {
    local ram_gb zram_active zswap_active=""

    ram_gb=$(awk '/MemTotal/ { printf "%d", $2 / 1024 / 1024 }' /proc/meminfo)

    # shellcheck disable=SC2154
    if [[ "${ZSWAP,,}" = "yes" ]]; then
        zswap_active="Y"
        zram_active=0
    else
        zram_active=$(zramctl --noheadings 2>/dev/null | wc -l || true)
    fi

    if [[ "${zram_active}" -gt 0 ]]; then
        echo 120
    elif [[ "${zswap_active}" == "Y" ]]; then
        if   [[ "${ram_gb}" -le 4  ]]; then echo 30
        elif [[ "${ram_gb}" -le 8  ]]; then echo 20
        elif [[ "${ram_gb}" -le 16 ]]; then echo 10
        else                                echo 1
        fi
    else
        # swap disque seul
        if   [[ "${ram_gb}" -le 4  ]]; then echo 40
        elif [[ "${ram_gb}" -le 8  ]]; then echo 30
        elif [[ "${ram_gb}" -le 16 ]]; then echo 20
        else                                echo 10
        fi
    fi
}

########################################################################################################################

_GET_SWAP() {
    local filename size_kb size_gb
    local -n swaps="$1"
    while IFS=$'\t ' read -r filename _ size_kb _; do
        [[ "${filename}" == "Filename" ]] && continue
        [[ "${filename}" == /dev/zram* ]] && continue
        size_gb=$(awk "BEGIN {printf \"%.1f\", ${size_kb}/1024/1024}")
        # shellcheck disable=SC2034
        swaps["${filename}"]="${size_gb}"
    done < /proc/swaps
}

########################################################################################################################

_DISABLE_SWAP_FSTAB() { # on va commenter les SWAP éventuels dans fstab
    local fstab_path backup_path temp_path
    local line
    local -a fields

    fstab_path="/etc/fstab"
    temp_path="$(mktemp)"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*# ]]; then
            printf '%s\n' "${line}"
            continue
        fi

        if [[ -z "${line//[[:space:]]/}" ]]; then
            printf '%s\n' "${line}"
            continue
        fi

        fields=()
        read -r -a fields <<< "${line}"

        if [[ "${#fields[@]}" -ge 3 ]] && [[ "${fields[2]}" = "swap" ]]; then
            printf '#commented out by jotenakis post-install script %s\n' "${line}"
        else
            printf '%s\n' "${line}"
        fi
    done < "${fstab_path}" > "${temp_path}"

    if sudo cmp -s -- "${temp_path}" "${fstab_path}"; then
        _LOG "Aucune modification requise dans ${fstab_path}"
    else
        backup_path="${fstab_path}.bak.$(_BAKSUFFIX)"
        _RUNSILENT "" sudo cp -pv -- "${fstab_path}" "${backup_path}"
        _LOG "Sauvegarde: ${backup_path}"
        _RUN "Désactivation des swap comme demandé" sudo sh -c "cat -- \"${temp_path}\" > \"${fstab_path}\""
        dr="yes"
        export dr
    fi
    _RUNSILENT "" sudo rm -fv -- "${temp_path}"

}


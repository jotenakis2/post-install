#!/usr/bin/env bash
set -euo pipefail

########################################################################################################################
# FONCTIONS HELPERS POUR MANIPULER LA CONF DE GRUB                                                                     #
########################################################################################################################


########################################################################################################################
_GRUB_REGENERATE_CONFIG() {
    local mkconfig=""
    local grub_cfg=""

    if _EXIST update-grub; then
        sudo update-grub
        return
    fi

    if _EXIST grub2-mkconfig; then
        mkconfig="grub2-mkconfig"
    elif _EXIST grub-mkconfig; then
        mkconfig="grub-mkconfig"
    else
        _ERR "Impossible de trouver update-grub, grub2-mkconfig ou grub-mkconfig"
        return 0
    fi

    if [[ -f /etc/grub2-efi.cfg || -L /etc/grub2-efi.cfg ]]; then
        grub_cfg="/etc/grub2-efi.cfg"
    elif [[ -f /etc/grub2.cfg || -L /etc/grub2.cfg ]]; then
        grub_cfg="/etc/grub2.cfg"
    elif [[ -d /boot/grub2 ]]; then
        grub_cfg="/boot/grub2/grub.cfg"
    elif [[ -d /boot/grub ]]; then
        grub_cfg="/boot/grub/grub.cfg"
    else
        _ERR "Impossible de déterminer le chemin de grub.cfg"
        return 0
    fi

    sudo "${mkconfig}" -o "${grub_cfg}"
}

########################################################################################################################

_GRUB_GET_CMDLINE() {
    local file=$1

    sed -n 's/^GRUB_CMDLINE_LINUX="\([^\"]*\)"$/\1/p' "${file}" | head -n 1 || true
}

########################################################################################################################

_GRUB_GET_VALUE() {
    local file=$1
    local key=$2

    grep "^${key}=" "${file}" | head -n 1 | cut -d'=' -f2- || true
}

########################################################################################################################

_GRUB_CMDLINE_TO_ARRAY() {
    local cmdline=$1
    local -n __out_ref=$2
    __out_ref=()

    if [[ -z "${cmdline}" ]]; then
        return 0
    fi
    # shellcheck disable=SC2034
    read -r -a __out_ref <<< "${cmdline}"
}

########################################################################################################################

_GRUB_ARRAY_REMOVE_TOKEN() {
    # shellcheck disable=SC2178
    local -n __arr_ref=$1
    local token=$2
    local new_arr=()
    local item

    if [[ -z "${token}" ]]; then
        return 0
    fi

    for item in "${__arr_ref[@]}"; do
        if [[ "${item}" != "${token}" ]]; then
            new_arr+=("${item}")
        fi
    done

    __arr_ref=("${new_arr[@]}")
}

########################################################################################################################

_GRUB_ARRAY_ADD_TOKEN() {
    # shellcheck disable=SC2178
    local -n __arr_ref=$1
    local token=$2

    if [[ -z "${token}" ]]; then
        return 0
    fi
    # shellcheck disable=SC2310
    if ! _GRUB_ARRAY_HAS_TOKEN "${token}" "${__arr_ref[@]}"; then
        __arr_ref+=("${token}")
    fi
}

########################################################################################################################

_GRUB_ARRAY_HAS_TOKEN() {
    local needle=$1
    shift

    local token
    for token in "$@"; do
        if [[ "${token}" == "${needle}" ]]; then
            return 0
        fi
    done

    return 1
}

########################################################################################################################

_GRUB_ARRAY_ADD_FROM_STRING() {
    # shellcheck disable=SC2178
    local -n __arr_ref=$1
    local input=$2
    local tmp=()
    local token

    [[ -z ${input} ]] && return 0

    read -r -a tmp <<< "${input}"
    for token in "${tmp[@]}"; do
        # shellcheck disable=SC2310
        if ! _GRUB_ARRAY_HAS_TOKEN "${token}" "${__arr_ref[@]}"; then
            __arr_ref+=("${token}")
        fi
    done
}

########################################################################################################################

_GRUB_ARRAY_JOIN() {
    # shellcheck disable=SC2178
    local -n __arr_ref=$1
    local joined=""

    if ((${#__arr_ref[@]} == 0)); then
        printf '\n'
        return 0
    fi

    printf -v joined '%s ' "${__arr_ref[@]}"
    printf '%s\n' "${joined% }"
}

########################################################################################################################

_GRUB_SET_KV() {
    local file=$1
    local key=$2
    local value=$3

    if grep -q "^${key}=" "${file}"; then
        sudo sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
    else
        printf '%s=%s\n' "${key}" "${value}" | sudo tee -a "${file}" >/dev/null
    fi
}

########################################################################################################################

_GRUB_SET_CMDLINE() {
    local file=$1
    local value=$2

    if grep -q '^GRUB_CMDLINE_LINUX=' "${file}"; then
        sudo sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${value}\"|" "${file}"
    else
        printf 'GRUB_CMDLINE_LINUX="%s"\n' "${value}" | sudo tee -a "${file}" >/dev/null
    fi
}

########################################################################################################################



########################################################################################################################

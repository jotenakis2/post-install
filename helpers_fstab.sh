#!/usr/bin/env bash
set -euo pipefail
########################################################################################################################
# FONCTIONS HELPERS POUR MANIPULER /etc/fstab                                                                          #
########################################################################################################################



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
        _ETC_FILES_ADD "/etc/fstab"
    fi
    _RUNSILENT "" sudo rm -fv -- "${temp_path}"

}

########################################################################################################################

_NORMALIZE_FSTAB() { # formatage du fichier fstab pour alignements nickels
    local fstab="/etc/fstab"
    local line=
    local work=
    local comment=
    local has_comment=
    local -a fields=()
    local -a rows=()
    local -a widths=(0 0 0 0)
    local i=

    while IFS= read -r line || [[ -n ${line} ]]; do
        rows+=("${line}")

        case ${line} in
            '' | [[:space:]]*'#'*)  continue ;;
            *) true ;;
        esac

        work=${line}
        if [[ ${work} = *'#'* ]]; then
            work=${work%%'#'*}
        fi

        IFS=$' \t' read -r -a fields <<<"${work}"
        ((${#fields[@]} < 6)) && continue

        for i in 0 1 2 3; do
            ((${#fields[i]} > widths[i])) && widths[i]=${#fields[i]}
        done
    done <"${fstab}"

    for line in "${rows[@]}"; do
        case ${line} in
        '')
            printf '\n'
            ;;
        [[:space:]]*'#'*)
            work=${line#"${line%%[![:space:]]*}"}
            work=${work#\#}
            work=${work#[[:space:]]}
            printf '# %s\n' "${work}"
            ;;
        *)
            comment=
            has_comment=
            work=${line}

            if [[ ${work} == *'#'* ]]; then
                comment=${work#*'#'}
                comment=${comment#[[:space:]]}
                work=${work%%'#'*}
                has_comment=1
            fi

            IFS=$' \t' read -r -a fields <<<"${work}"
            if ((${#fields[@]} < 6)); then
                printf '%s\n' "${line}"
                continue
            fi

            printf '%-*s\t%-*s\t%-*s\t%-*s  %s %s' \
                "${widths[0]}" "${fields[0]}" \
                "${widths[1]}" "${fields[1]}" \
                "${widths[2]}" "${fields[2]}" \
                "${widths[3]}" "${fields[3]}" \
                "${fields[4]}" "${fields[5]}"

            [[ -n ${has_comment} ]] && printf '  # %s' "${comment}"
            printf '\n'
            ;;
        esac
    done
}

########################################################################################################################

_BACKUP_FSTAB(){
    local fstab="/etc/fstab"
    local origin="/etc/fstab.origin"
    local bak copied

    # copie originale
    if ! sudo test -f "${origin}"; then
        _RUNSILENT "" sudo cp -pv "${fstab}" "${origin}"
    fi

    # copie timestampée
    bak=$(_BAKSUFFIX)
    copied="/etc/fstab.bak.${bak}"
    if sudo test -f "${copied}"; then
        sleep 2
        bak=$(_BAKSUFFIX)
        copied="/etc/fstab.bak.${bak}"
    fi
    _RUNSILENT "" sudo cp -pv "${fstab}" "${copied}"

    # droits
    _RUNSILENT "" sudo chown -v root:root "${copied}" "${origin}"
    _RUNSILENT "" sudo chmod -v 644 "${copied}" "${origin}"
}

########################################################################################################################

_FS_OPTIMIZE(){ # ajout noatime,lazytime,commit=120,,,si besoin
    local fstab_changed=false tmp_dir
    local fstab="/etc/fstab"
    tmp_dir=$(mktemp -d)
    true >"${tmp_dir}/fstab.new" # on crée un fichier vide temporaire
    # shellcheck disable=SC2154
    echo "# modified by ${SCRIPTNAME} (v${VERSION}) by jotenakis" >>"${tmp_dir}/fstab.new"
    echo "# initial file copied into /etc/fstab.origin" >>"${tmp_dir}/fstab.new"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*# ]] || [[ -z "${line}" ]]; then # commentaire ou ligne vide laissée as is
            echo "${line}" >>"${tmp_dir}/fstab.new"
            continue
        fi

        local dev mp fs opts dump pass
        read -r dev mp fs opts dump pass <<<"${line}"

        if [[ "${fs}" =~ ^(btrfs|ext4|xfs)$ ]]; then # si FS btrfs,ext4,xfs on va ajouter noatime/lazytime si absent
            local orig_opts="${opts}"

            if [[ ! ",${opts}," =~ ,noatime, ]]; then
                opts="${opts},noatime"
            fi
            if [[ ! ",${opts}," =~ ,lazytime, ]]; then
                opts="${opts},lazytime"
            fi
            if [[ "${fs}" = "ext4" ]]; then
                if [[ "${opts}" =~ commit=[0-9]+ ]]; then
                    # shellcheck disable=SC2001
                    opts=$(sed 's/commit=[0-9]*/commit=120/' <<< "${opts}")
                else
                    opts="${opts},commit=120"
                fi
            fi
            if [[ "${orig_opts}" != "${opts}" ]]; then
                fstab_changed=true
                printf "%-40s %-24s %-8s %-32s %-2s %s\n" "${dev}" "${mp}" "${fs}" "${opts}" "${dump}" "${pass}" >>"${tmp_dir}/fstab.new"
                continue
            fi
        fi

        echo "${line}" >>"${tmp_dir}/fstab.new"

    done <"${fstab}"

    if [[ "${fstab_changed}" == "true" ]]; then
        _BACKUP_FSTAB
        _RUN "Optimisations des systèmes de fichier" sudo cp -pv "${tmp_dir}/fstab.new" "${fstab}"
        dr="yes"
        _ETC_FILES_ADD "${fstab}"
    else
        _INFO "Options d'optimisations déjà présentes dans ${fstab}"
    fi
    _RUNSILENT "" sudo rm -rvf -- "${tmp_dir}"
}

########################################################################################################################

_ADD_NFS(){
    local opts
    opts="rw,_netdev,nofail,nodev,nosuid,noexec,noatime,lazytime,x-systemd.automount,x-systemd.mount-timeout=30s"
    local fstab="/etc/fstab"

    # shellcheck disable=SC2154
    if ! grep -q "${NFS_SHARE}" "${fstab}" >/dev/null; then
        if grep -q "${NFS_MP}" "${fstab}" >/dev/null; then
            _INFO "Point de montage demandé (${NFS_MP}) déjà présent dans ${fstab} :"
            grep "${NFS_MP}" "${fstab}"
            _INFO "Abandon de l'installation du partage réseau NFS."
        else
            _BACKUP_FSTAB
            _RUNSILENT "" sudo mkdir -pv "${NFS_MP}"
            echo "${NFS_SHARE}   ${NFS_MP}   nfs   ${opts}      0 0" | sudo tee -a "${fstab}" >/dev/null
            _ETC_FILES_ADD "${fstab}"
            dr="yes"
            _RUN "Montage du partage réseau NFS" bash -c "sudo mount -v \"${NFS_MP}\" && sudo ls -l \"${NFS_MP}\""
        fi
    else
        _INFO "Montage NFS déjà OK"
    fi
}

########################################################################################################################

_ADD_SWAPFILE(){
    local swapdir="/var/swap"
    local swapfile="${swapdir}/swapfile"
    local fstab="/etc/fstab"
    if [[ -f "${swapfile}" ]]; then
        if ! grep -q "${swapfile}" "${fstab}"; then
            _BACKUP_FSTAB
            _RUN "Ajout du swap" bash -c "echo ${swapdir}/swapfile none swap sw,nofail 0 0 | sudo tee -a ${fstab}"
            _ETC_FILES_ADD "${fstab}"
            dr="yes"
        else
            _INFO "Swap déjà présent dans ${fstab}"
        fi
    fi
}

########################################################################################################################

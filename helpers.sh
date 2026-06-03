#!/usr/bin/env bash
set -euo pipefail

########################################################################################################################
# FONCTIONS HELPERS                                                                                                    #
########################################################################################################################
if [[ -f ./helpers_ui.sh ]]; then
    # shellcheck source=./helpers_ui.sh
    source ./helpers_ui.sh
else
    echo "helpers_ui.sh manquant !"
    exit 1
fi
if [[ -f ./helpers_grub.sh ]]; then
    # shellcheck source=./helpers_grub.sh
    source ./helpers_grub.sh
else
    echo "helpers_grub.sh manquant !"
    exit 1
fi
if [[ -f ./helpers_pkg.sh ]]; then
    # shellcheck source=./helpers_pkg.sh
    source ./helpers_pkg.sh
else
    echo "helpers_pkg.sh manquant !"
    exit 1
fi
if [[ -f ./helpers_fstab.sh ]]; then
    # shellcheck source=./helpers_fstab.sh
    source ./helpers_fstab.sh
else
    echo "helpers_fstab.sh manquant !"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_INSTALL_ETC_FILES() {
    local msg="$1"
    local content="$2"
    local file="$3"
    local rights="$4"
    readonly msg content file rights
    _LOG "${msg^^}"
    if sudo test -f "${file}" && printf '%s' "${content}" | sudo cmp -s - "${file}"; then
        _INFO "Déjà OK : ${msg}"
        # shellcheck disable=SC2154
        echo 1 >"${STATUSFILE}"
    else
        _OK "Configuration ${msg} (${file})"
        _BACKUP_FILE "${file}"
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
    list="${*:-}"
    if [[ -n "${list}" ]]; then
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
        local missing_fmt missing_fmt_readable
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
            if [[ "${install_cmd}" = "_FPPKG_INSTALL" ]]; then
                local missing_readable=()
                local missing_fmt_readable
                for pkg in "${missing[@]}"; do
                    missing_readable+=("${pkg##*.}") # pour rendre plus propre la nom des paquets flatpak
                done
                missing_fmt_readable=$(_FORMAT_LIST "${missing_readable[@]}")
                a=$(_PRINT_LIST "${missing_fmt_readable}")
                echo "${a}" | tee -a "${LOG_FILE:-/dev/null}"
            else
                a=$(_PRINT_LIST "${missing_fmt}")
                echo "${a}" | tee -a "${LOG_FILE:-/dev/null}"
            fi

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
            if [[ "${install_cmd}" = "_FPPKG_INSTALL" ]]; then
                local readable=()
                local fmt_readable
                for pkg in "$@"; do
                    readable+=("${pkg##*.}") # pour rendre plus propre la nom des paquets flatpak
                done
                fmt_readable=$(_FORMAT_LIST "${readable[@]}")
                c=$(_PRINT_LIST "${fmt_readable}")
            fi
            _INFO "Déjà OK (${treat}) : "
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

_TUNE_EXT4(){
    # fast_commit pour ext4
    local mounts
    mounts=$(findmnt -rn -t ext4 -o SOURCE,TARGET,FSTYPE)
    while read -r dev mp fs _; do
        if [[ "${fs}" != "ext4" ]]; then continue; fi
        if [[ "${mp}" == "/boot" ]]; then continue; fi
        if sudo tune2fs -l "${dev}" 2>/dev/null | grep -q "fast_commit"; then
            _LOG "fast_commit déjà actif sur ${dev} (montée en ${mp})"
        else
            _RUN "Activation flag \"fast_commit\" sur ${dev} (montée en ${mp})" sudo tune2fs -O fast_commit "${dev}"
        fi
    done <<<"${mounts}"
}

########################################################################################################################

_BAKSUFFIX(){
    date +%d_%m_%Y-%H.%M.%S
}

########################################################################################################################

_BACKUP_FILE(){
    local file=${1:-}

    # si oubli de spécifier le fichier à sauvegarder, on quitte avec message explicite.
    if [[ -z "${file}" ]]; then
        _ERR "Aucun fichier spécifié pour la sauvegarde avec _BACKUP_FILE"
    fi

    if sudo test -f "${file}"; then
        local origin="${file}.origin"
        local bak copied owner group perm

        # droits initiaux
        owner=$(stat -c '%U' -- "${file}")
        group=$(stat -c '%G' -- "${file}")
        perm=$(stat -c '%a' -- "${file}")

        # copie originale
        if ! sudo test -f "${origin}"; then
            _RUNSILENT "" sudo cp -pfv "${file}" "${origin}"
        fi

        # copie timestampée
        bak=$(_BAKSUFFIX)
        copied="${file}.bak.${bak}"
        if sudo test -f "${copied}"; then
            sleep 2
            bak=$(_BAKSUFFIX)
            copied="${file}.bak.${bak}"
        fi
        _RUNSILENT "" sudo cp -pfv "${file}" "${copied}"

        # droits recopiés
        _RUNSILENT "" sudo chown -v "${owner}:${group}" "${copied}" "${origin}"
        _RUNSILENT "" sudo chmod -v "${perm}" "${copied}" "${origin}"
    else
        _LOG "${file} n'existe pas (encore ?), pas de sauvegarde possible."
    fi
}

########################################################################################################################

_ROOT_CHECK(){ # Vérification explicite des droits root
    if [[ "${EUID}" -eq 0 ]]; then
        local reponse
        echo "${SCRIPTNAME} lancé en tant que root, le mode \"SHELL ONLY\" est imposé :"
        echo " - Les dépots GIT seront clonés (programmes non installés)."
        echo " - Le SHELL zsh sera configuré."
        echo " - Les dotfiles clonés seront déployés pour l'utilisateur root."
        echo " - Pour que tout le script soit exécuté il doit être lancé en utilisateur avec droits sudo."
        echo ""
        read -r -p "On continue en mode \"SHELL ONLY\" ? [o/N] " reponse
        # shellcheck disable=SC2034
        case "${reponse,,}" in
            o|oui|y|yes) ROOT="yes" ;;
            *) exit 127 ;;
        esac
    else
        if ! id -nG "${USER}" | grep -qwE 'wheel|sudo'; then
            echo "L'utilisateur ${USER} n'appartient pas au groupe 'wheel' (sudo). Abandon."
            exit 1
        fi
    fi
}

########################################################################################################################

_BASH_CHECK(){
    if [[ -z "${BASH_VERSION:-}" ]]; then
        echo "Ce script requiert bash."
        exit 1
    fi
    if [[ "${BASH_VERSINFO[0]}" -lt 5 ]]; then
        echo "Bash >= 5 requis (actuel : ${BASH_VERSION})."
        exit 1
    fi
}

########################################################################################################################

_SETUP_VCONSOLE_FONT() {
    local font="${VCONSOLE_FONT:-eurlatgr}"
    local vconsole="/etc/vconsole.conf"
    local font_dirs=("/usr/lib/kbd/consolefonts" "/usr/share/kbd/consolefonts")
    local found=0

    for dir in "${font_dirs[@]}"; do
        if ls "${dir}/${font}".* &>/dev/null; then
            found=1
            break
        fi
    done

    if ((found == 0)); then
        _LOG "Police console '${font}' introuvable"
    else
        if grep -q "^FONT=" "${vconsole}" 2>/dev/null; then
            if grep -q "^FONT=${font}" "${vconsole}" 2>/dev/null; then
                _INFO "Déjà OK : police console TTY"
                grep FONT "${vconsole}" >>"${LOG_FILE:-/dev/null}"
            else
                _BACKUP_FILE "${vconsole}"
                _RUNSILENT "" sudo sed -i "s/^FONT=.*/FONT=${font}/" "${vconsole}"
                _OK "Modification de la police console TTY (${vconsole})"
                _ETC_FILES_ADD "${vconsole}"
                _LOG "Police console définie :"
                cat "${vconsole}" 2>/dev/null >>"${LOG_FILE:-/dev/null}"
            fi
        else
            _BACKUP_FILE "${vconsole}"
            printf '%s' "FONT=${font}" | sudo tee -a "${vconsole}" >/dev/null
            _OK "Ajout de la police console TTY (${vconsole})"
            _ETC_FILES_ADD "${vconsole}"
            _LOG "Police console définie :"
            cat "${vconsole}" 2>/dev/null >>"${LOG_FILE:-/dev/null}"
        fi
    fi
}

########################################################################################################################

_SELINUX_CHECK(){
    local sestatus
    sestatus=$(cat /sys/fs/selinux/enforce 2>/dev/null) || true

    case "${sestatus}" in
        1) echo "enforcing" ;;
        0) echo "permissive" ;;
        *) echo "absent" ;;
    esac
}

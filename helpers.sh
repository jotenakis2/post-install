#!/usr/bin/env bash
# shellcheck disable=SC2154

########################################################################################################################
# FONCTIONS HELPERS                                                                                                    #
########################################################################################################################

# _BANNER
# _SECTION
# _HEURE
# _OK
# _ERR
# _INFO
# _DIE
# _LOG
# _IN_ARRAY
# _SYMLINK
# _PLASMA_EVAL
# _PLASMA_GET_PANEL_LOCATION
# _PASS
# _RUNSILENT
# _RUN
# _EXIST
# _DETECT_GRUB !!!!!!!!!!!!!!!!!!
# _DIR_IS_SAFE_TO_RESTORE
# _CONVERT_SECONDS
# _FORMAT_LIST
# _IS_ENABLED
# _IS_ENABLED_USER
# _IS_ACTIVE
# _IS_ACTIVE_USER
# _INIT_COLOR
# _IS_FPPKG_INSTALLED
# _FPPKG_INSTALL
# _MANAGE_TABLE

############################################################################################################################
_BANNER() {
    local color=$1
    shift
    local text="$*"
    local fg cols
    cols="${COLUMNS}"
    case "${color}" in
    red) fg=31 ;; green) fg=32 ;; yellow) fg=33 ;; blue) fg=34 ;;
    magenta) fg=35 ;; cyan) fg=36 ;; white) fg=37 ;; *) fg=39 ;;
    esac
    local w=$((cols - 2))
    ((w < 1)) && return
    local len=${#text}
    ((len > w)) && text=${text:0:w} && len=w
    local padl=$(((w - len) / 2))
    local padr=$((w - len - padl))

    local TL=$'\xE2\x95\x94' TR=$'\xE2\x95\x97'
    local BL=$'\xE2\x95\x9A' BR=$'\xE2\x95\x9D'
    local H=$'\xE2\x95\x90' V=$'\xE2\x95\x91'
    local hline
    hline=$(printf '%*s' "${w}" '' | sed "s/ /${H}/g")

    printf '\033[%sm%s%s%s\033[0m\n' "${fg}" "${TL}" "${hline}" "${TR}"
    printf '\033[%sm%s%*s%s%*s%s\033[0m\n' "${fg}" "${V}" "${padl}" '' "${text}" "${padr}" '' "${V}"
    printf '\033[%sm%s%s%s\033[0m\n' "${fg}" "${BL}" "${hline}" "${BR}"
    echo "${text}" >>"${LOG_FILE}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
# shellcheck disable=SC2034
_ENABLE_COLORS() {
    if [[ -t 1 ]] && command -v tput &>/dev/null && [[ -z "${NO_COLOR:-}" ]]; then
        # texte
        C_BLACK=$(tput setaf 0)
        C_RED=$(tput setaf 1)
        C_GREEN=$(tput setaf 2)
        C_YELLOW=$(tput setaf 3)
        C_BLUE=$(tput setaf 4)
        C_MAGENTA=$(tput setaf 5)
        C_CYAN=$(tput setaf 6)
        C_WHITE=$(tput setaf 7)

        # attribut
        C_BOLD=$(tput bold)
        C_DIM=$(tput dim)
        C_RESET=$(tput sgr0)
        C_UNDERLINE=$(tput smul)
        C_RESET_UNDERLINE=$(tput rmul)

        # background
        BKGND_BLACK=$(tput setab 0)
        BKGND_RED=$(tput setab 1)
        BKGND_GREEN=$(tput setab 2)
        BKGND_YELLOW=$(tput setab 3)
        BKGND_BLUE=$(tput setab 4)
        BKGND_MAGENTA=$(tput setab 5)
        BKGND_CYAN=$(tput setab 6)
        BKGND_WHITE=$(tput setab 7)
    else
        # texte
        C_BLACK=''
        C_RED=''
        C_GREEN=''
        C_YELLOW=''
        C_BLUE=''
        C_MAGENTA=''
        C_CYAN=''
        C_WHITE=''

        # attribut
        C_BOLD=''
        C_DIM=''
        C_RESET=''
        C_UNDERLINE=''
        C_RESET_UNDERLINE=''

        # background
        BKGND_BLACK=''
        BKGND_RED=''
        BKGND_GREEN=''
        BKGND_YELLOW=''
        BKGND_BLUE=''
        BKGND_MAGENTA=''
        BKGND_CYAN=''
        BKGND_WHITE=''
    fi
    local vars=(
        C_BLACK C_RED C_GREEN C_YELLOW C_BLUE C_MAGENTA C_CYAN C_WHITE
        C_BOLD C_DIM C_RESET C_UNDERLINE C_RESET_UNDERLINE
        BKGND_BLACK BKGND_RED BKGND_GREEN BKGND_YELLOW
        BKGND_BLUE BKGND_MAGENTA BKGND_CYAN BKGND_WHITE
    )
    export "${vars[@]}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_INSTALL_ETC_FILES() {
    local msg="$1"
    local content="$2"
    local file="$3"
    local rights="$4"
    local status=1
    readonly msg content file rights
    _LOG "${msg^^}"
    if sudo test -f "${file}" && printf '%s' "${content}" | sudo cmp -s - "${file}"; then
        _INFO "${msg^} déjà configuré (${file})"
    else
        _OK "Configuration du ${msg} (${file})"
        printf '%s' "${content}" | sudo tee "${file}" >/dev/null
        _RUNSILENT "" sudo chmod -v "${rights}" "${file}"
        _ETC_FILES_ADD "${file}"
        status=0
    fi
    {
        sudo ls -l "${file}"
        sudo cat "${file}"
        echo ""
    } >>"${LOG_FILE}"

    if [[ "${status}" -eq 0 ]]; then
        return 0
    elif [[ "${status}" -eq 1 ]]; then
        return 1
    else
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
_IS_ENABLED() {
    systemctl is-enabled --quiet "$@" 2>>"${LOG_FILE}"
}
_IS_ACTIVE() {
    systemctl is-active --quiet "$@" 2>>"${LOG_FILE}"
}
_IS_ENABLED_USER() {
    systemctl --user is-enabled --quiet "$@" 2>>"${LOG_FILE}"
}
_IS_ACTIVE_USER() {
    systemctl --user is-active --quiet "$@" 2>>"${LOG_FILE}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
_IN_ARRAY() {
    local needle="$1"
    shift
    printf '%s\n' "$@" | grep -qxF "${needle}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
_SECTION() {
    local msg="${1^^}"
    local fillertype="${2}"
    local color="${3}"
    [[ $# == 0 ]] && return 1

    declare -i term_cols # Terminal width
    term_cols="${COLUMNS}" || return 1
    echo -e "${color}"

    declare -i str_len="${#msg}" # Length of $msg
    [[ ${str_len} -ge ${term_cols} ]] && {
        echo "${msg}"
        return 0
    }

    declare -i filler_len="$(((term_cols - str_len) / 2))"
    local ch="${fillertype:0:1}"
    local filler=""
    for ((i = 0; i < filler_len; i++)); do
        filler="${filler}${ch}"
    done

    printf "%s%s%s" "${filler}" "${msg}" "${filler}"
    [[ $(((term_cols - str_len) % 2)) -ne 0 ]] && printf "%s" "${ch}"
    printf "\n"
    echo -e "${C_RESET}"
    echo -e "\n>>>>>>>>>> ${msg}" >>"${LOG_FILE}"
    return 0
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_HEURE() {
    local date heure
    date=$(date '+%T')
    heure=$(date '+%A %d %B %Y')
    echo "${date}, le ${heure}" | tee -a "${LOG_FILE}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_OK() {
    local msg
    msg="$*"
    echo "${C_GREEN} ✓ ${C_RESET} ${msg}"
    echo "[OK] ${msg}" >>"${LOG_FILE}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_INFO() {
    local msg
    msg="$*"
    echo "${C_GREEN}${C_BOLD} → ${C_RESET} ${msg}"
    echo "[INFO] ${msg}" >>"${LOG_FILE}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_ERR() {
    local msg
    msg="$*"
    echo "${C_RED} ✗ ${C_RESET} ${msg}"
    echo "[ERROR] ${msg}" >>"${LOG_FILE}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_DIE() {
    _ERR "$*"
    exit 1
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_LOG() {
    local msg="$*"
    echo -e "\n${msg}" >>"${LOG_FILE}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_SYMLINK() {
    local src="$1"
    local dst="$2"
    declare -g STATUSSYMLINK

    if [[ -L "${dst}" ]]; then
        local current_target
        current_target=$(readlink "${dst}")

        if [[ "${current_target}" = "${src}" ]]; then
            STATUSSYMLINK=2
        else
            _ERR "Lien ${dst} existe déjà mais pointe vers '${current_target}', pas vers '${src}'. Je ne change rien."
            STATUSSYMLINK=1
        fi
    else
        mkdir -p "$(dirname "${dst}")"
        if sudo ln -s "${src}" "${dst}"; then
            _OK "Lien créé : ${dst} → ${src}"
            STATUSSYMLINK=0
        else
            _ERR "Échec de création du lien : ${dst} → ${src}"
            STATUSSYMLINK=1
        fi
    fi
    export STATUSSYMLINK
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

_PASS() {
    # On vérifie silencieusement si l'autorisation est requise, si oui on gère un joli prompt
    if ! sudo -n true 2>/dev/null; then
        printf "\n%b[🔐 SUDO]%b Autorisation requise pour %b%s%b : " "${C_RED}" "${C_RESET}" "${C_BOLD}" "${USER}" "${C_RESET}"
        sudo -v -p ""
    fi
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_RUNSILENT() {
    local msg="$1"
    shift
    [[ -n "${msg}" ]] && _OK "${msg}"

    # Log tout,mais affiche juste les premières lignes si erreur
    local tmperr
    tmperr=$(mktemp)
    # shellcheck disable=SC2312
    "$@" 2>&1 | tee -a "${LOG_FILE}" >"${tmperr}"
    local rc="${PIPESTATUS[0]}"

    if ((rc != 0)); then
        head -5 "${tmperr}" >&2
        echo "Échec de la commande : '$*'" >&2
        echo "(voir ${LOG_FILE})" >&2
    fi

    rm -f "${tmperr}"
    return "${rc}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
_SPIN() {
    local SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local pid="$1" msg="$2" i=0
    while kill -0 "${pid}" 2>/dev/null; do
        printf "\r %b%s%b %s" "${C_RED}" "${SPIN_FRAMES[$((i % 10))]}" "${C_RESET}" "${msg}"
        sleep 0.05
        ((i++)) || true
    done
    printf '\r\033[2K'
}

_RUN() {
    local msg="$1"
    shift
    tput civis || true # Hide cursor, ignore errors if unsupported
    "$@" >>"${LOG_FILE}" 2>&1 &
    local pid=$!
    _SPIN "${pid}" "${msg}"
    if wait "${pid}"; then
        tput cvvis || true # Show cursor, ignore errors if unsupported
        _OK "${msg}"
    else
        tput cvvis || true # Show cursor, ignore errors if unsupported
        _ERR "${msg}"
        tail -n5 "${LOG_FILE}"
        _DIE "Échec — détails : ${LOG_FILE}"
    fi
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_EXIST() {
    local cmd
    cmd=$1
    command -v "${cmd}" &>/dev/null && return 0
    return 1
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
    [[ -z "${found}" ]]
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_CONVERT_SECONDS() {
    local total=${1:-0}
    local days hours mins secs

    ((total < 0)) && total=0

    days=$((total / 86400))
    hours=$(((total % 86400) / 3600))
    mins=$(((total % 3600) / 60))
    secs=$((total % 60))

    if ((days > 0)); then
        printf '%sj %sh %sm %ss\n' "${days}" "${hours}" "${mins}" "${secs}"
    elif ((hours > 0)); then
        printf '%sh %sm %ss\n' "${hours}" "${mins}" "${secs}"
    elif ((mins > 0)); then
        printf '%sm %ss\n' "${mins}" "${secs}"
    else
        printf '%ss\n' "${secs}"
    fi
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
        _IS_PKG_INSTALLED) test="paquet présent ?" ;;
        _IS_PKG_REMOVED) test="paquet absent ?" ;;
        _IS_FPPKG_INSTALLED) test="paquet présent ?" ;;
        _IS_CARGOPKG_INSTALLED) test="paquet présent ?" ;;
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
            ((${#present[@]})) && {
                _INFO "Paquets à IGNORER car réussissant le test \"${test}\" : "
                _PRINT_LIST "${present_fmt}" | tee -a "${LOG_FILE}" || true
            }
            _INFO "Paquets à TRAITER car échouant au test \"${test}\" : "
            _PRINT_LIST "${missing_fmt}" | tee -a "${LOG_FILE}" || true
            _RUN "${treat^} en cours..." "${install_cmd}" "${missing[@]}"
            printf '\e[1A\e[2K' # je remonte d'une ligne et je la vide, pour écraser le "en cours..."
            _OK "Traitement terminé, ${treat} OK."
        else
            all_fmt=$(_FORMAT_LIST "$@")
            _INFO "Tout a été traité (${treat}) : "
            _PRINT_LIST "${all_fmt}" | tee -a "${LOG_FILE}" || true
        fi
    else
        _INFO "Rien à traiter (${treat}), liste transmise vide..."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_ETC_FILES_ADD() {
    local entry="$1"
    local item=""
    for item in "${ETC_FILES[@]}"; do
        [[ "${item}" == "${entry}" ]] && return 0
    done
    ETC_FILES+=("${entry}")
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_PRINT_ETC_FILES() {
    local item list file hr
    file="list-of-system-files-created-or-modified-by-${SCRIPTNAME}"
    list=$(_FORMAT_LIST "${ETC_FILES[@]}")
    hr="$(date +%Y%m%d-%H%M%S)"
    _INFO "Fichiers système crées ou modifiés : "
    echo "${list}" | tee -a "${LOG_FILE}"
    if [[ -f "${HOME}/${file}" ]]; then
        echo "" >>"${HOME}/${file}"
    else
        true >"${HOME}/${file}" # création fichier vide
    fi
    for item in "${ETC_FILES[@]}"; do
        echo "${hr} : ${item}" >>"${HOME}/${file}"
    done
    _RUNSILENT "" sudo cp -f "${HOME}/${file}" "/root/${file}"
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

########################################################################################################################

# print_list STRING
# Affiche STRING sur stdout en wrappant à la largeur du terminal.
# Toutes les lignes sont indentées de 5 espaces.
# Les coupures se font uniquement sur les espaces (jamais en plein mot).
# Les espaces multiples sont préservés.
# print_list STRING
# Affiche STRING sur stdout en wrappant à la largeur du terminal.
# Toutes les lignes sont indentées de 5 espaces.
# Les coupures se font uniquement sur les espaces (jamais en plein mot).
# Les espaces multiples sont préservés sur la même ligne, ignorés en début de continuation.
_PRINT_LIST() {
    local list="${1:?print_list: argument manquant}"
    local width
    width=$(tput cols 2>/dev/null) || width=80
    local indent="         "
    local line="${indent}"
    local chunk=""
    local char
    local i
    local in_space=0

    for ((i = 0; i < ${#list}; i++)); do
        char="${list:i:1}"
        if [[ "${char}" == ' ' ]]; then
            if ((!in_space)); then
                if [[ "${line}" == "${indent}" ]]; then
                    line="${indent}${chunk}"
                elif ((${#line} + ${#chunk} <= width)); then
                    line="${line}${chunk}"
                else
                    printf '%s\n' "${line}"
                    line="${indent}"
                    chunk=""
                    in_space=1
                fi
                chunk=""
                in_space=1
            fi
            [[ "${line}" != "${indent}" ]] && chunk="${chunk}${char}"
        else
            in_space=0
            chunk="${chunk}${char}"
        fi
    done

    # Dernier token
    if [[ -n "${chunk}" ]]; then
        if [[ "${line}" == "${indent}" ]]; then
            line="${indent}${chunk}"
        elif ((${#line} + ${#chunk} <= width)); then
            line="${line}${chunk}"
        else
            printf '%s\n' "${line}"
            line="${indent}${chunk}"
        fi
    fi

    [[ "${line}" != "${indent}" ]] && printf '%s\n' "${line}"
}

########################################################################################################################

_IS_FPPKG_INSTALLED() {
    sudo flatpak info "$@" &>/dev/null || return 1
}

_FPPKG_INSTALL() {
    sudo flatpak install -y flathub "$@"
}

_IS_CARGOPKG_INSTALLED() {
    echo "${installed_list}" | grep -q "$@"
}

_CARGOPKG_INSTALL() {
    cargo binstall --no-confirm "$@"
}

_GOPKG_INSTALL() {
    go install "$@"
}

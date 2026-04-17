#!/usr/bin/env bash
# shellcheck disable=SC2154
#_BANNER
#_SECTION
#_HEURE
#_OK
#_ERR
#_INFO
#_DIE
#_SYMLINK
#_PLASMA_EVAL
#_PASS
#_RUNSILENT
#_RUN
#_EXIST
#_DETECT_GRUB !!!!!!!!!!!!!!!!!!
#_DIR_IS_SAFE_TO_RESTORE
#_CONVERT_SECONDS


########################################################################################################################
# FONCTIONS HELPERS                                                                                                    #
########################################################################################################################
_BANNER() {
    local color=$1
    shift
    local text="$*"
    local fg cols
    cols="${COLUMNS}"
    case "${color}" in
        red) fg=31;; green) fg=32;; yellow) fg=33;; blue) fg=34;;
        magenta) fg=35;; cyan) fg=36;; white) fg=37;; *) fg=39;;
    esac
    local w=$((cols - 2))
    (( w < 1 )) && return
    local len=${#text}
    (( len > w )) && text=${text:0:w} && len=w
    local padl=$(( (w - len) / 2 ))
    local padr=$(( w - len - padl ))

    local TL=$'\xE2\x95\x94' TR=$'\xE2\x95\x97'
    local BL=$'\xE2\x95\x9A' BR=$'\xE2\x95\x9D'
    local H=$'\xE2\x95\x90' V=$'\xE2\x95\x91'
    local hline
    hline=$(printf '%*s' "${w}" '' | sed "s/ /${H}/g")

    printf '\033[%sm%s%s%s\033[0m\n' "${fg}" "${TL}" "${hline}" "${TR}" | tee -a "${LOG_FILE}"
    printf '\033[%sm%s%*s%s%*s%s\033[0m\n' "${fg}" "${V}" "${padl}" '' "${text}" "${padr}" '' "${V}" | tee -a "${LOG_FILE}"
    printf '\033[%sm%s%s%s\033[0m\n' "${fg}" "${BL}" "${hline}" "${BR}" | tee -a "${LOG_FILE}"

    return 0
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

_OK()       { printf " %b✓%b %s\n" "${C_GREEN}"  "${C_RESET}" "$*" | tee -a "${LOG_FILE}"; }
_ERR()      { printf " %b✗%b %s\n" "${C_RED}"    "${C_RESET}" "$*" | tee -a "${LOG_FILE}" >&2; }
_INFO()     { printf " %b→%b %s\n" "${C_YELLOW}"   "${C_RESET}" "$*" | tee -a "${LOG_FILE}"; }
_DIE()      { _ERR "$*"; exit 1; }
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_SYMLINK() {
    local src="$1"
    local dst="$2"

    if [[ -L "${dst}" ]]; then
        local current_target
        current_target=$(readlink "${dst}")

        if [[ "${current_target}" = "${src}" ]]; then
            _OK "Lien déjà présent : ${dst} → ${src} (pas de changement)"
        else
            _ERR "Lien ${dst} existe déjà mais pointe vers '${current_target}', pas vers '${src}'. Je ne change rien."
            return 1
        fi
    else
        mkdir -p "$(dirname "${dst}")"
        if sudo ln -s "${src}" "${dst}"; then
            _OK "Lien créé : ${dst} → ${src}"
        else
            _ERR "Échec de création du lien : ${dst} → ${src}"
        fi
    fi
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_PLASMA_EVAL() {
    local script="$1"
    busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "${script}"
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
    local msg="$1"; shift
    [[ -n "${msg}" ]] && _OK "${msg}"

    # Log tout,mais affiche juste les premières lignes si erreur
    local tmperr
    tmperr=$(mktemp)
    # shellcheck disable=SC2312
    "$@" 2>&1 | tee -a "${LOG_FILE}" > "${tmperr}"
    local rc="${PIPESTATUS[0]}"

    if (( rc != 0 )); then
        head -5 "${tmperr}" >&2
        echo "Échec de la commande : '$*'" >&2
        echo "(voir ${LOG_FILE})" >&2
    fi

    rm -f "${tmperr}"
    return "${rc}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_RUN() {
    local msg="$1"; shift

    _SPIN() {
        local SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local pid="$1" msg="$2" i=0
        while kill -0 "${pid}" 2>/dev/null; do
            printf "\r %b%s%b %s" "${C_RED}" "${SPIN_FRAMES[$((i % 10))]}" "${C_RESET}" "${msg}"
            sleep 0.05
            (( i++ )) || true
        done
        printf '\r\033[2K'
    }

    "$@" >> "${LOG_FILE}" 2>&1 &
    local pid=$!
    _SPIN "${pid}" "${msg}"
    if wait "${pid}"; then
        _OK "${msg}"
    else
        _ERR "${msg}"
        _DIE "Échec — détails : ${LOG_FILE}"
    fi
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_EXIST(){
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

    (( total < 0 )) && total=0

    days=$(( total / 86400 ))
    hours=$(( (total % 86400) / 3600 ))
    mins=$(( (total % 3600) / 60 ))
    secs=$(( total % 60 ))

    if (( days > 0 )); then
        printf '%sj %sh %sm %ss\n' "${days}" "${hours}" "${mins}" "${secs}"
    elif (( hours > 0 )); then
        printf '%sh %sm %ss\n' "${hours}" "${mins}" "${secs}"
    elif (( mins > 0 )); then
        printf '%sm %ss\n' "${mins}" "${secs}"
    else
        printf '%ss\n' "${secs}"
    fi
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_FORMAT_LIST() {
    local -a items=("$@")
    local count=${#items[@]}

    case ${count} in
        0) echo "" ;;
        1) echo "${items[0]}" ;;
        2) echo "${items[0]} et ${items[1]}" ;;
        *)
            local all_but_last
            all_but_last=$(IFS=', '; echo "${items[*]::count-1}")
            echo "${all_but_last} et ${items[-1]}"
            ;;
    esac
}

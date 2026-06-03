#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
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
    if ((w < 1)); then return 0; fi
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
    echo "${text}" >>"${LOG_FILE:-/dev/null}"
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

_SECTION() {
    local msg="${1^^}"
    local fillertype="${2}"
    local color="${3}"
    [[ $# == 0 ]] && return 1

    declare -i term_cols # Terminal width
    if ! term_cols="${COLUMNS}"; then return 1; fi
    echo -e "${color}"
    term_cols=$(( term_cols - 2 ))

    declare -i str_len="${#msg}" # Length of $msg
    if [[ ${str_len} -ge ${term_cols} ]]; then echo "${msg}"; return 0; fi

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
    echo -e "\n>>>>>>>>>> ${msg}" >>"${LOG_FILE:-/dev/null}"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_OK() {
    local msg
    msg="$*"
    echo "${C_GREEN} ✓ ${C_RESET} ${msg}"
    echo "[OK] ${msg}" >>"${LOG_FILE:-/dev/null}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_INFO() {
    local msg
    msg="$*"
    echo "${C_GREEN}${C_BOLD} → ${C_RESET} ${msg}"
    echo "[INFO] ${msg}" >>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_ERR() {
    local msg
    msg="$*"
    echo "${C_RED} ✗ ${C_RESET} ${msg}"
    echo "[ERROR] ${msg}" >>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_DIE() {
    _ERR "$*"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_LOG() {
    local msg="$*"
    echo -e "\n${msg}" >>"${LOG_FILE:-/dev/null}"
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_HEURE() {
    local date heure
    date=$(date '+%T')
    heure=$(date '+%A %d %B %Y')
    echo "${date}, le ${heure}" | tee -a "${LOG_FILE:-/dev/null}"
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
    local msg="${1:?message manquant}"
    shift
    local log
    log=${LOG_FILE:-/dev/null}

    [[ -n "${msg}" ]] && _OK "${msg}"

    # Log tout,mais affiche juste les premières lignes si erreur
    local tmperr
    tmperr=$(mktemp)
    # shellcheck disable=SC2312
    "$@" 2>&1 | tee -a "${log}" >"${tmperr}"
    local rc="${PIPESTATUS[0]}"

    if ((rc != 0)); then
        head -5 "${tmperr}" >&2
        echo "Échec de la commande : '$*'" >&2
        echo "(voir ${log})" >&2
    fi

    rm -f -- "${tmperr}"
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

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_RUN() {
    local msg="${1:?message manquant}"
    shift
    local log
    log=${LOG_FILE:-/dev/null}
    tput civis 2>/dev/null || true # Hide cursor, ignore errors if unsupported
    "$@" >>"${log}" 2>&1 &
    local pid=$!
    _SPIN "${pid}" "${msg}"
    if wait "${pid}"; then
        tput cnorm 2>/dev/null || true # Show cursor, ignore errors if unsupported
        _OK "${msg}"
    else
        tput cnorm 2>/dev/null || true # Show cursor, ignore errors if unsupported
        _ERR "${msg}"
        tail -n5 "${log}"
        _DIE "Échec — détails : ${log}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_CONVERT_SECONDS() {
    local total=${1:-0}
    local days hours mins secs

    if ((total < 0)); then total=0; fi

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

# _PRINT_LIST() {
#     local list="${1:-}"
#     local width
#     width=$(tput cols 2>/dev/null) || width=80
#     local indent="         "
#     local line="${indent}"
#     local chunk=""
#     local char
#     local i
#     local in_space=0
#
#     if [[ -n "${list}" ]]; then
#         for ((i = 0; i < ${#list}; i++)); do
#             char="${list:i:1}"
#             if [[ "${char}" == ' ' ]]; then
#                 if ((!in_space)); then
#                     if [[ "${line}" == "${indent}" ]]; then
#                         line="${indent}${chunk}"
#                     elif ((${#line} + ${#chunk} <= width)); then
#                         line="${line}${chunk}"
#                     else
#                         printf '%s\n' "${line}"
#                         line="${indent}"
#                         chunk=""
#                         in_space=1
#                     fi
#                     chunk=""
#                     in_space=1
#                 fi
#                 if [[ "${line}" != "${indent}" ]]; then
#                     chunk="${chunk}${char}"
#                 fi
#             else
#                 in_space=0
#                 chunk="${chunk}${char}"
#             fi
#         done
#
#         # Dernier token
#         if [[ -n "${chunk}" ]]; then
#             if [[ "${line}" == "${indent}" ]]; then
#                 line="${indent}${chunk}"
#             elif ((${#line} + ${#chunk} <= width)); then
#                 line="${line}${chunk}"
#             else
#                 printf '%s\n' "${line}"
#                 line="${indent}${chunk}"
#             fi
#         fi
#
#         if [[ "${line}" != "${indent}" ]]; then
#             printf '%s\n' "${line}"
#         fi
#         return 0
#     fi
# }

_PRINT_LIST() {
    local list="${1:-}"
    local width
    width=$(tput cols 2>/dev/null) || width=80
    local indent="     "
    local line="${indent}"
    local word

    [[ -z "${list}" ]] && return 0

    for word in ${list}; do
        if [[ "${line}" = "${indent}" ]]; then
            line="${indent}${word}"
        elif ((${#line} + 1 + ${#word} <= width)); then
            line="${line} ${word}"
        else
            printf '%s\n' "${line}"
            line="${indent}${word}"
        fi
    done

    [[ "${line}" != "${indent}" ]] && printf '%s\n' "${line}"
}


# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

_PRINT_ETC_FILES() {
    if [[ -n "${ETC_FILES[*]}" ]]; then
        local item list file hr
        # shellcheck disable=SC2154
        file="list-of-system-files-created-or-modified-by-${SCRIPTNAME}.log"
        list=$(_FORMAT_LIST "${ETC_FILES[@]}")
        hr="$(date +%d_%m_%Y-%H.%M.%S)"
        _INFO "Fichiers système crées ou modifiés : "
        _PRINT_LIST "${list}"
        echo "${list}" >> "${LOG_FILE:-/dev/null}"
        for item in "${ETC_FILES[@]}"; do
            echo "${hr} : ${item}" >>"${HOME}/${file}"
        done
        echo >>"${HOME}/${file}"
        _RUNSILENT "" sudo cp -f "${HOME}/${file}" "/root/${file}"
    else
        _OK "Aucun fichier système crée ou modifié"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

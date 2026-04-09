#!/usr/bin/env bash
set -euo pipefail
readonly SCRIPTNAME="${0##*/}"
readonly VER=5.6
# TODO : git privé (clé ssh, ...)
#        psd
#        revoir log

# variables globales en MAJ, locales en min
# fonctions globales en MAJ, locales en min
# fonctions helpers commencent par _  (_RUN, _SECTION, ...)

# paramètres customisables définies dans settings.sh.
source settings.sh

# ─── MAIN ────────────────────────────────────────────────────────────────────────────────────────────────────────────
MAIN() {
    # intercept errors
    trap '_ERR "Interruption ligne ${LINENO}"; _DIE "Log : ${LOG_FILE}"' ERR

    # Start
    INITIALIZE
    CHECK_ENV

    # tâches paquets
    _RUN "Mise à jour forcée du système" sudo dnf upgrade --refresh -y
    REMOVE_RPM_PACKAGES
    INSTALL_REPOS
    INSTALL_RPM_PACKAGES
    INSTALL_FONTS
    INSTALL_CODECS
    INSTALL_CARGO_PACKAGES
    INSTALL_GO_PACKAGES
    INSTALL_FLATPAK_PACKAGES

    # tâches config
    CLONE_GIT
    SETUP_SHELL
    SETUP_DOTFILES
    SETUP_ETC
     SETUP_SYSTEMD
     SETUP_FIREWALL
     SETUP_SWAP
    SETUP_FSTAB
    SETUP_GRUB
    SETUP_KDE_PLASMA
     SETUP_PLM
    SETUP_SUDO_RS

    # Fin
    printf "\n%b%b  ✓ Terminé — REDÉMARREZ pour appliquer les modifications.%b\n" "${C_GREEN}" "${C_BOLD}" "${C_RESET}"
    printf "%b  Log complet : %s%b\n\n" "${C_MAGENTA}" "${LOG_FILE}" "${C_RESET}"
    _RUNSILENT "" sudo rm -fv "${SUDOTMP}"
    _HEURE >> "${LOG_FILE}"
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────





########################################################################################################################
# FONCTIONS HELPERS                                                                                                    #
########################################################################################################################
_BANNER() {
    local color=$1
    shift
    local text="$*"
    local fg cols
    cols=100
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

_SECTION() { # CYAN
    local text fg cols w len padl padr V
    text="$*" fg=36 cols=50 w=$((cols - 2)) len=${#text} V="━━━━━━━"
    (( w < 1 )) && return
    (( len > w )) && text=${text:0:w} && len=w
    padl=$(( (w - len) / 2 ))
    padr=$(( w - len - padl ))
    printf '\033[%sm%s%*s%s%*s%s\033[0m\n' "${fg}" "${V}" "${padl}" '' "${text^^}" "${padr}" '' "${V}" | tee -a "${LOG_FILE}"
    return 0
}

_HEURE() {
    local date heure
    date=$(date '+%T')
    heure=$(date '+%A %d %B %Y')
    echo "${date}, le ${heure}" | tee -a "${LOG_FILE}"
}

_OK()       { printf " %b✓%b %s\n" "${C_GREEN}"  "${C_RESET}" "$*" | tee -a "${LOG_FILE}"; }
_ERR()      { printf " %b✗%b %s\n" "${C_RED}"    "${C_RESET}" "$*" | tee -a "${LOG_FILE}" >&2; }
_INFO()     { printf " %b→%b %s\n" "${C_YELLOW}"   "${C_RESET}" "$*" | tee -a "${LOG_FILE}"; }
_DIE()      { _ERR "$*"; exit 1; }

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
        if ln -s "${src}" "${dst}"; then
            _OK "Lien créé : ${dst} → ${src}"
        else
            _ERR "Échec de création du lien : ${dst} → ${src}"
        fi
    fi
}

_PASS() {
    # On vérifie silencieusement si l'autorisation est requise, si oui on gère un joli prompt
    if ! sudo -n true 2>/dev/null; then
        printf "\n%b[🔐 SUDO]%b Autorisation requise pour %b%s%b : " "${C_RED}" "${C_RESET}" "${C_BOLD}" "${USER}" "${C_RESET}"
        sudo -v -p ""
    fi
}
_RUNSILENT() {
    local msg="$1"; shift
    [[ -n "${msg}" ]] && _OK "${msg}"

    # Log tout,mais affiche juste les premières lignes si erreur
    local tmperr
    tmperr=$(mktemp)

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

_RUN() {
    local msg="$1"; shift

    spin() {
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
    spin "${pid}" "${msg}"
    if wait "${pid}"; then
        _OK "${msg}"
    else
        _ERR "${msg}"
        _DIE "Échec — détails : ${LOG_FILE}"
    fi
}

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
        if sudo strings "${efi_payload}" | grep -qi "systemd-boot"; then
            echo "false"
            return 0
        fi

        if sudo strings "${efi_payload}" | grep -qw "GRUB"; then
            echo "true"
            return 0
        fi
    fi

    # Par défaut, si introuvable
    echo "false"
    return 0
}
########################################################################################################################




########################################################################################################################
# FONCTIONS PRINCIPALES                                                                                                #
########################################################################################################################
INITIALIZE() {
    C_RESET='' C_RED='' C_GREEN='' C_YELLOW='' C_MAGENTA='' #C_CYAN=''
    C_BOLD=''
    if [[ -t 1 ]]; then
        C_RESET='\e[0m'
        C_BOLD='\e[1m'
        C_RED='\e[1;31m'
        C_GREEN='\e[1;32m'
        C_YELLOW='\e[1;33m'
        C_MAGENTA='\e[1;35m'
        #C_CYAN='\e[1;36m'
    fi
    _PASS
    LOG_DIR="${HOME}/.local/log"
    LOG_FILE="${LOG_DIR}/post-install-fedora-$(date +%Y%m%d-%H%M%S).log"
    INSTALL_DIR="${HOME}/.local/bin"
    # RUST
    export RUSTUP_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/rustup"
    export CARGO_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/cargo"
    # GO
    export GOPATH="${XDG_DATA_HOME:-${HOME}/.local/share}/go"
    export GOBIN="${XDG_BIN_HOME:-${HOME}/.local/bin}"

    # Dossiers utilisateur requis
    _RUNSILENT "" mkdir -pv "${LOG_DIR}" "${INSTALL_DIR}" "${RUSTUP_HOME}" "${CARGO_HOME}" "${GOPATH}" "${GOBIN}" "${HOME}/.local/share/zsh" "${HOME}/.local/share/icons/default" "${HOME}/.local/share/color-schemes" "${HOME}/.local/share/themes"
    # Dossiers système requis
    _RUNSILENT "" sudo mkdir -pv /usr/local/bin /etc/sudoers.d /etc/udev.d/rules.d /etc/NetworkManager/conf.d /etc/systemd/resolved.conf.d /etc/sysctl.d/ /etc/brave/policies/managed/

    # Préparation d'une session sudo confortable et longue pour l'installation
    SUDOTMP="/etc/sudoers-rs.d/99_POST-INSTALL" # pour delete à la fin
    local sudotmp="/etc/sudoers.d/99_POST-INSTALL"

    _RUNSILENT "" sudo bash -c "echo 'Defaults pwfeedback,timestamp_timeout=180' > '${sudotmp}'"
    _RUNSILENT "" sudo chmod -v 0440 "${sudotmp}"

    SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    _HEURE >> "${LOG_FILE}"

    # aussitôt je conf dnf si besoin pour accélérer les download de paquets
    if ! rpm -q crudini >/dev/null 2>&1; then
        _RUN "Préparation" sudo dnf install -y crudini
    fi
    if command -v crudini &>/dev/null; then
        _RUNSILENT "" sudo crudini --verbose --set /etc/dnf/dnf.conf main defaultyes true
        _RUNSILENT "" sudo crudini --verbose --set /etc/dnf/dnf.conf main max_parallel_downloads 10
    fi

    # PATH
    export PATH="${GOBIN}:${CARGO_HOME}/bin:${INSTALL_DIR}:${PATH}"


    #
    clear
    _BANNER "blue" "${SCRIPTNAME} (${VER})"
}

########################################################################################################################
CHECK_ENV() {
    _SECTION "Vérification environnement"

    [[ -n "${BASH_VERSION:-}" ]]       || _DIE "Ce script requiert bash."
    [[ "${BASH_VERSINFO[0]}" -ge 5 ]]  || _DIE "Bash >= 5 requis (actuel : ${BASH_VERSION})."
    [[ "${EUID}" -ne 0 ]]              || _DIE "Ne pas lancer en root. Le script gère sudo lui-même."
    [[ -f /etc/fedora-release ]]       || _DIE "Fedora uniquement."

    # Vérification explicite des droits sudo (groupe wheel)
    if ! id -nG "${USER}" | grep -qw "wheel"; then
        _DIE "L'utilisateur ${USER} n'appartient pas au groupe 'wheel' (sudo). Abandon."
    fi

    _RUN "Contrôle des dépendances obligatoires" sudo dnf install -y curl git stow pciutils dnf-plugins-core binutils policycoreutils-python-utils

    local fedora_rel
    fedora_rel=$(cat /etc/fedora-release)
    _OK "Environnement valide — ${fedora_rel}, utilisateur ${USER} avec droits sudo"

}

########################################################################################################################
REMOVE_RPM_PACKAGES() {
    _SECTION "Suppression paquets indésirables"

    local pkg wants_systemd_networkd_removal
    wants_systemd_networkd_removal=0

    for pkg in "${DNF_REMOVE[@]}"; do
        if [[ "${pkg}" == "systemd-networkd" ]]; then
            wants_systemd_networkd_removal=1
            continue
        fi
        if rpm -q "${pkg}" &>/dev/null; then
            _RUN "Suppression ${pkg}" sudo dnf remove -y "${pkg}"
        else
            _OK "${pkg} absent — ignoré."
        fi
    done

    if (( wants_systemd_networkd_removal )); then # par sécurité (si demandé) on ne dégage systemd-networkd qu'après assurance que NM est présent et actif
        if systemctl is-active --quiet NetworkManager; then
            if rpm -q systemd-networkd &>/dev/null; then
                _RUN "Suppression systemd-networkd (NetworkManager actif)" sudo dnf remove -y systemd-networkd
            else
                _OK "systemd-networkd absent — ignoré."
            fi
        else
            _INFO "NetworkManager inactif — systemd-networkd conservé."
        fi
    fi
}

########################################################################################################################
INSTALL_REPOS() {
    _SECTION "Dépôts RPM"

    local fedora_ver cache=0
    fedora_ver=$(rpm -E '%fedora')

    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        _RUN "RPM Fusion free (f${fedora_ver})" sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"${fedora_ver}".noarch.rpm
        _RUN "RPM Fusion free tainted (f${fedora_ver})" sudo dnf install -y rpmfusion-free-release-tainted
        cache=1
    else
        _OK "RPM Fusion free déjà présent."
    fi

    if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
        _RUN "RPM Fusion nonfree (f${fedora_ver})" sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"${fedora_ver}".noarch.rpm
        _RUN "RPM Fusion nonfree tainted (f${fedora_ver})" sudo dnf install -y rpmfusion-nonfree-release-tainted
        cache=1
    else
        _OK "RPM Fusion nonfree déjà présent."
    fi

    if rpm -q rpmfusion-free-appstream-data &>/dev/null; then
        _RUN "suppression métadonnées appstream free" sudo dnf remove -y rpmfusion-free-appstream-data
    fi
    if rpm -q rpmfusion-nonfree-appstream-data &>/dev/null; then
        _RUN "suppression métadonnées appstream nonfree" sudo dnf remove -y rpmfusion-nonfree-appstream-data
    fi

    if ! rpm -q terra-release &>/dev/null; then
        # shellcheck disable=SC2016
        _RUN "Terra (f${fedora_ver})" sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
        cache=1
    else
        _OK "Terra déjà présent."
    fi

    if ! dnf repolist 2>/dev/null | grep -q "bigmenpixel:profile-sync-daemon"; then
        _RUN "COPR profile-sync-daemon" sudo dnf copr enable -y bigmenpixel/profile-sync-daemon
        cache=1
    else
        _OK "COPR profile-sync-daemon déjà présent."
    fi

    if ! dnf repolist 2>/dev/null | grep -q "brave-browser"; then
        _RUN "Brave Browser Repo" sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        cache=1
    else
        _OK "Brave Browser Repo déjà présent."
    fi
    if [[ "${cache}" -eq 1 ]]; then
        _RUN "Rafraîchissement des métadonnées" sudo dnf makecache
    fi
}

########################################################################################################################
INSTALL_FONTS() {
    _SECTION "Nerd Fonts"

    local font
    for font in "${FONTS[@]}"; do
        if ! rpm -q "${font}" &>/dev/null; then
            _RUN "Installation ${font}" sudo dnf install -y "${font}"
        else
            _OK "${font} déjà présente."
        fi
    done
}

########################################################################################################################
INSTALL_CODECS() {
    _SECTION "Codecs multimédia"

    # codecs
    if ! rpm -q ffmpeg &>/dev/null; then
        _RUN "Swap ffmpeg-free →  ffmpeg" sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
        _RUNSILENT "Mise à jour groupe multimedia." sudo dnf group upgrade multimedia --exclude=PackageKit-gstreamer-plugin -y
    else
        _OK "ffmpeg (rpmfusion) déjà présent."
        _OK "Groupe multimedia déjà à jour."
    fi
    if ! dnf repolist --enabled | grep -q '^fedora-cisco-openh264'; then
        _RUNSILENT "Activation Cisco h264." sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 -y
    else
        _OK "Cisco h264 déjà activé."
    fi

    # mesa swap
    local gpu_vendor
    gpu_vendor=$(lspci | grep -iE 'VGA|3D' | head -1 | tr '[:upper:]' '[:lower:]')
    _INFO "GPU détecté : ${gpu_vendor}"

    if echo "${gpu_vendor}" | grep -q "amd\|radeon\|advanced micro"; then
        if ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
            _RUN "Swap mesa-va-drivers → freeworld (AMD)" sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
        else
            _OK "Mesa freeworld déjà présent."
        fi
    elif echo "${gpu_vendor}" | grep -q "intel"; then
        if ! rpm -q intel-media-driver &>/dev/null; then
            _RUN "intel-media-driver" sudo dnf install -y intel-media-driver
        else
            _OK "intel-media-driver déjà présent."
        fi
    else
        _INFO "GPU non AMD/Intel — Mesa swap ignoré."
    fi
}

########################################################################################################################
INSTALL_RPM_PACKAGES() {
    _SECTION "Paquets RPM"
    local pkg arch download_dir
    local -a missing_packages
    arch=$(uname -m)
    download_dir="./dnf-packages$$"
    missing_packages=()

    for pkg in "${DNF_PACKAGES[@]}"; do
        if ! rpm -q "${pkg}" &>/dev/null; then
            missing_packages+=("${pkg}")
        else
            _OK "${pkg} est déjà installé — ignoré."
        fi
    done

    if ((${#missing_packages[@]})); then
        _RUNSILENT "" mkdir -pv "${download_dir}"
        _OK "Paquets manquants : ${missing_packages[*]}."
        _RUN "Téléchargement des paquets et dépendances manquants" sudo dnf download --arch "${arch}" --arch noarch --resolve --destdir="${download_dir}" -y "${missing_packages[@]}"
        _RUN "Installation des paquets manquants depuis le cache de téléchargement" sudo dnf install -y "${download_dir}"/*.rpm
        _RUNSILENT "" rm -rvf "${download_dir}"
    else
        _INFO "Tous les paquets RPM sont déjà installés."
    fi
}

########################################################################################################################
INSTALL_FLATPAK_PACKAGES() {
    _SECTION "Paquets Flatpak"

    # 1. Vérification et installation de Flatpak
    if ! command -v flatpak >/dev/null 2>&1; then
        _RUN "Installation de Flatpak" sudo dnf install -y flatpak
    else
        _OK "Flatpak est déjà installé."
    fi

    # 2. Ajout de Flathub s'il n'existe pas
    _RUN "Ajout du dépôt Flathub" sudo flatpak --verbose remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    # 3. Activation de Flathub sans filtre
    _RUNSILENT "" sudo flatpak --verbose remote-modify --no-filter --enable flathub

    # 4. Vérification et suppression du dépôt Fedora
    if flatpak remotes --columns=name | grep -q "^fedora$"; then
        _RUN "Suppression du dépôt Fedora Flatpak" sudo flatpak --verbose remote-delete --force fedora
    else
        _OK "Le dépôt Fedora Flatpak n'est pas présent."
    fi

    # 5. Installation des paquets depuis Flathub (System-wide par défaut avec sudo)
    if [[ ${#FLATPAK_PKGS[@]} -gt 0 ]]; then
        for pkg in "${FLATPAK_PKGS[@]}"; do
            if flatpak info "${pkg}" >/dev/null 2>&1; then
                _OK "Flatpak '${pkg}' est déjà installé."
            else
                _RUN "Installation de ${pkg}" sudo flatpak --verbose install -y flathub "${pkg}"
            fi
        done
    else
        _INFO "Aucun paquet Flatpak à installer."
    fi

    # 7. Petit nettoyage des runtimes inutilisés
    _RUN "Nettoyage des runtimes Flatpak orphelins" sudo flatpak --verbose uninstall --unused -y
}

########################################################################################################################
INSTALL_CARGO_PACKAGES() {
    _SECTION "Paquets Cargo"

    # 0. toolchain rust
    if command -v rustup &>/dev/null; then
        _RUN "Mise à jour de la toolchain rust" rustup update stable
    else
        _RUN "Installation de la toolchain rust" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable'
    fi

    # 1. Installation de cargo-binstall sans compilation
    if ! command -v cargo-binstall &>/dev/null; then
        _RUN "Installation de cargo-binstall" bash -c "curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash"
    else
        _OK "cargo-binstall est déjà installé."
    fi
    _RUNSILENT "" sudo ln -svf "${CARGO_HOME}/bin/cargo-binstall" "/usr/local/bin/"

    local cmd
    for cmd in "${CARGO_PACKAGES[@]}"; do

        # 1. Installation du paquet via Cargo (binstall)
        if cargo install --list | grep -q "^${cmd} "; then
            _OK "${cmd} déjà installé."
        else
            _RUN "Installation de ${cmd}" cargo binstall --no-confirm "${cmd}"
        fi

        # 2. Création des liens symboliques dans /usr/local/bin
        local bins_to_link
        if [[ -n "${BIN_MAPPING[${cmd}]:-}" ]]; then
            # il existe une correpondance paquet <=> binaire, on l'utilise
            bins_to_link="${BIN_MAPPING[${cmd}]}"
        else
            # paquet = binaire
            bins_to_link="${cmd}"
        fi

        local bin_name src_bin dest_link current_target
        for bin_name in ${bins_to_link}; do
            src_bin="${CARGO_HOME}/bin/${bin_name}"
            dest_link="/usr/local/bin/${bin_name}"

            if [[ -x "${src_bin}" ]]; then
                current_target=""
                if [[ -L "${dest_link}" ]]; then
                    current_target=$(readlink -f "${dest_link}" || true)
                fi
                if [[ "${current_target}" != "${src_bin}" ]]; then
                    _RUNSILENT "" sudo ln -svf "${src_bin}" "${dest_link}"
                fi
            else
                _ERR " Binaire introuvable : ${src_bin}"
            fi
        done
    done

    # 3. Ajustement des permissions pour l'accès global
    _RUNSILENT "" chmod a+x -v "${HOME}" "${HOME}/.local" "${HOME}/.local/share" "${CARGO_HOME}" "${CARGO_HOME}/bin"
}

########################################################################################################################
INSTALL_GO_PACKAGES() {
    _SECTION "Paquets GO"
    local pkg current="" latest="" arch="" os="" gofile
    export PATH="/usr/local/go/bin:${PATH}"
    if command -v go &>/dev/null; then
         current="$(go version | grep -oP 'go\K\d+\.\d+\.\d+' || true)"
    fi

    latest=$(curl -s https://go.dev/dl/ | grep -oP 'go\K\d+\.\d+\.\d+' | head -1 || true)
    arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/' || true)
    os=$(uname | tr '[:upper:]' '[:lower:]' || true)
    gofile="go${latest}.${os}-${arch}.tar.gz"

    if [[ "${current}" == "${latest}" ]] && command -v go &>/dev/null; then
        _OK "Toolchain GO à jour et accessible"
    else
        _RUN "Téléchargement de la toolchain Go v${latest}" wget "https://go.dev/dl/${gofile}"
        _RUNSILENT "" sudo rm -rvf /usr/local/go
        _RUN "Installation de la toolchain Go v${latest}" sudo tar -C /usr/local -xzf "${gofile}"
        _RUNSILENT "" rm -vf "${gofile}"
    fi

    if command -v go &>/dev/null; then
        for pkg in "${!GO_PACKAGES[@]}"; do # on parcourt les clés du tableau associatif
            local url
            url="${GO_PACKAGES[${pkg}]}"
            if ! command -v "${pkg}" &>/dev/null; then
                _RUN "Installation de ${pkg}" go install "${url}"
            else
                _RUN "Mise à jour de ${pkg}" go install "${url}"
            fi
            _RUNSILENT "" sudo ln -svf "${GOBIN}/${pkg}" "/usr/local/bin"
        done
    fi
}

########################################################################################################################
CLONE_GIT() {
    _SECTION "dépôts Git personnels"

    local repo_entry repo_url dest_dir repo_name backup_dir

    for repo_entry in "${GIT_REPOS[@]}"; do
        # Extraction de l'URL et de la destination (séparées par '|')
        repo_url="${repo_entry%%|*}"
        dest_dir="${repo_entry##*|}"

        # Récupération du nom du dépôt pour l'affichage (ex: "scripts")
        repo_name=$(basename "${repo_url}" .git)

        if [[ -d "${dest_dir}/.git" ]]; then
            # C'est un dépôt Git valide, on le met à jour
            _RUN "Mise à jour de ${repo_name}" git -C "${dest_dir}" pull --ff-only
        else
            # Le chemin existe MAIS n'est pas un dépôt Git (ou c'est un fichier)
            if [[ -e "${dest_dir}" ]]; then
                backup_dir="${dest_dir}_backup_$(date +%Y%m%d%H%M%S)"
                _RUN "Sauvegarde de l'existant non-git (${repo_name})" mv "${dest_dir}" "${backup_dir}"
                _INFO "Ancien '${dest_dir}' sauvegardé dans '${backup_dir}'"
            fi

            # La voie est libre, on clone
            _RUN "Téléchargement de ${repo_name}" git clone "${repo_url}" "${dest_dir}"
        fi
    done

    _OK "Tous les dépôts Git sont à jour."
}

########################################################################################################################
SETUP_SHELL() {
    _SECTION "Shell"

    # 1- zsh
    local zsh_bin
    zsh_bin=$(command -v zsh)

    if ! grep -qxF "${zsh_bin}" /etc/shells; then
        echo "${zsh_bin}" | sudo tee -a /etc/shells > /dev/null
    fi

    local user uid current_shell
    while IFS=: read -r user _ uid _ _ _ _; do
        if [[ ( "${uid}" -ge 1000 && "${uid}" -lt 2000 ) || "${uid}" -eq 0 ]]; then # root et users normaux
            current_shell=$(getent passwd "${user}" | cut -d: -f7)
            if [[ "${current_shell}" != "${zsh_bin}" ]]; then
                _RUN "chsh ${user} → zsh" sudo chsh -s "${zsh_bin}" "${user}"
            else
                _OK "${user} utilise déjà zsh."
            fi
        fi
    done < /etc/passwd

    # 2- Oh-my-posh prompt
    local arch
    arch=$(uname -m)
    local omp_target=""

    case "${arch}" in
        x86_64|amd64)
            omp_target="posh-linux-amd64"
            ;;
        aarch64|arm64)
            omp_target="posh-linux-arm64"
            ;;
        armv7l)
            omp_target="posh-linux-arm"
            ;;
        *)
            _DIE "Architecture non supportée pour Oh My Posh : ${arch}"
            ;;
    esac

    local omp_url="https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/${omp_target}"
    local omp_bin="${INSTALL_DIR}/oh-my-posh"
    if command -v oh-my-posh >/dev/null 2>&1; then
        _RUN "Mise à jour de Oh-My-Posh" oh-my-posh upgrade
    else
        _RUN "Téléchargement du binaire Oh-My-Posh (${omp_target})" curl -fsSL "${omp_url}" -o "${omp_bin}"
        _RUNSILENT "" chmod 777 -v "${omp_bin}"
    fi

    # 3- symlinks
    # _RUNSILENT "Liens symboliques dans ${HOME}" ln -sfv "${HOME}/.local/share/icons" "${HOME}/.icons"
    # _RUNSILENT "" ln -sfv "${HOME}/.local/share/themes" "${HOME}/.themes"
    # _RUNSILENT "" ln -sv "${HOME}/.config/mozilla/firefox" "${HOME}/.mozilla"
    _SYMLINK "${HOME}/.local/share/icons" "${HOME}/.icons"
    _SYMLINK "${HOME}/.local/share/themes" "${HOME}/.themes"
    _SYMLINK "${HOME}/.config/mozilla/firefox" "${HOME}/.mozilla/firefox"
}

########################################################################################################################
SETUP_DOTFILES() {
    _SECTION "Dotfiles"
    if [[ ! -d "${DOTFILES_DIR}" ]]; then
        _ERR "Le dossier ${DOTFILES_DIR} est introuvable. Stow ignoré."
        return
    fi

    # 1- nettoyage avant stow pour éviter erreurs.
    local skel_files=(".bashrc" ".bash_logout" ".zshenv" ".zshrc" ".config/plasma-org.kde.plasma.desktop-appletsrc" ".config/konsolerc" ".config/user-dirs.dirs" ".config/user-dirs.locale")
    local file
    for file in "${skel_files[@]}"; do
        if [[ -f "${HOME}/${file}" && ! -L "${HOME}/${file}" ]]; then
            _RUNSILENT "" rm -vf "${HOME}/${file}"
        fi
    done

    # 2- stow pour déployer dotfiles depuis dépôt git
    local pkg name
    for pkg in "${DOTFILES_DIR}"/*/; do
        name=$(basename "${pkg}")
        _RUN "stow : ${name}" stow --dir="${DOTFILES_DIR}" --target="${HOME}" --restow "${name}"
    done
    _INFO "Les dotfiles ne sont déployés que pour l'utilisateur qui lance le script (ici : ${USER})"

}

########################################################################################################################
SETUP_ETC() {
    _SECTION "Configuration Système (/etc)"

    # --- NetworkManager & systemd-resolved ---
    local nm_dns_conf resolved_10_conf restart=0
    nm_dns_conf=$'[main]\ndns=systemd-resolved\n'
    resolved_10_conf=$'[Resolve]\nLLMNR=no\n'
    readonly nm_dns_conf resolved_10_conf

    if ! grep -rq "dns=systemd-resolved" /etc/NetworkManager/conf.d; then
        _RUN "Configuration de NetworkManager pour systemd-resolved" sudo bash -c "
        echo '${nm_dns_conf}' | install -m 644 -o root -g root /dev/stdin /etc/NetworkManager/conf.d/99-global-dns.conf
        "
        restart=1
    else
        _OK "NetworkManager déjà configuré pour utiliser systemd-resolved."
    fi

    _RUNSILENT "" sudo ln -svf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf # pas sécurité on force

    if [[ ! -f /etc/systemd/resolved.conf.d/dns_servers.conf ]] || [[ ! -f /etc/systemd/resolved.conf.d/10-disable-llmnr.conf ]]; then
        _RUN "Déploiement de la configuration DNS (systemd-resolved)" sudo bash -c "echo '${RESOLVED_DNS_SERVERS}' | install -m 644 -o root -g root /dev/stdin /etc/systemd/resolved.conf.d/dns_servers.conf ; echo '${resolved_10_conf}' | install -m 644 -o root -g root /dev/stdin /etc/systemd/resolved.conf.d/10-disable-llmnr.conf"
        restart=1
    else
        _OK "Configuration DNS (systemd-resolved) déjà présente."
    fi
    if [[ ${restart} -eq 1 ]]; then
        _RUN "Redémarrage de NetworkManager & systemd-resolved" sudo systemctl restart systemd-resolved NetworkManager
    fi

    # --- Optimisations Kernel (Sysctl) ---
    local sysctlfile sysctl_header full_sysctl_content
    sysctlfile="/etc/sysctl.d/90-jotenakis.conf"
    sysctl_header="# =======================================================================
# WARNING: Do not modify this file!
# It is automatically generated and managed by ${SCRIPTNAME}.
#
# To override these settings, create a new drop-in file with a
# higher priority number (e.g., /etc/sysctl.d/99-custom.conf).
# ======================================================================="
    readonly sysctlfile sysctl_header
    # on concatène le header et la variable globale SYSCTL_CONF
    full_sysctl_content="${sysctl_header}
    ${SYSCTL_CONF}"

    if [[ -f "${sysctlfile}" ]] && echo "${full_sysctl_content}" | sudo cmp -s - "${sysctlfile}"; then
        _OK "Configuration noyau déjà à jour (${sysctlfile})."
    else
        _RUN "Déploiement de la configuration du noyau (${sysctlfile})" sudo install -m 644 -o root -g root /dev/stdin "${sysctlfile}" <<< "${full_sysctl_content}"
        _RUNSILENT "" sudo sysctl -p "${sysctlfile}"
    fi

    # --- Configuration Brave Browser (Policies debloat) ---
    local brave_policy_file full_brave_policies
    brave_policy_file="/etc/brave/policies/managed/brave_debullshitinator-policies.json"
    full_brave_policies=$(echo "${BRAVE_POLICIES}" | sed "1s/{/{\n    \"_warning\": \"Do not modify this file! It is managed by ${SCRIPTNAME}.\",/")
    readonly brave_policy_file full_brave_policies

    if [[ -f "${brave_policy_file}" ]] && echo "${full_brave_policies}" | sudo cmp -s - "${brave_policy_file}"; then
        _OK "Configuration policies debloat Brave déjà à jour (${brave_policy_file})."
    else
        _RUN "Déploiement des policies pour débloater Brave (${brave_policy_file})" sudo install -m 644 -o root -g root /dev/stdin "${brave_policy_file}" <<< "${full_brave_policies}"
    fi

    # IO scheduler
    local rules_file rules_content current
    rules_file="/etc/udev.d/rules.d/60-ioschedulers.rules"
    sudo touch "${rules_file}"
    current=$(cat "${rules_file}" 2>/dev/null || true)
    rules_content='# NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]*", ATTR{queue/scheduler}="none"

# SSD SATA / eMMC
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# HDD rotatif
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
'

    if [[ "${current}" != "${rules_content}" ]]; then
        printf '%s\n' "${rules_content}" | sudo tee "${rules_file}" > /dev/null
        _RUNSILENT "" sudo udevadm control --reload-rules
        _RUNSILENT "" sudo udevadm trigger
        _OK "IO scheduler mis à jour (udev rule)."
    else
        echo "IO scheduler déjà à jour."
    fi


    # --- Configuration Chrony (IPv4 only si IPv6 désactivé) ---
    if echo "${CMDLINE}" | grep -q 'ipv6.disable=1'; then
        local chrony_file chrony_content
        chrony_file="/etc/sysconfig/chronyd"
        chrony_content=$'# Command-line options for chronyd\nOPTIONS="-F 2 -4"\n'
        readonly chrony_file chrony_content
        if [[ -f "${chrony_file}" ]] && echo "${chrony_content}" | sudo cmp -s - "${chrony_file}"; then
            _OK "Configuration chronyd déjà à jour."
        else
            _RUN "Configuration de chronyd" sudo install -m 644 -o root -g root /dev/stdin "${chrony_file}" <<< "${chrony_content}"
           _RUNSILENT "" sudo systemctl try-restart chronyd
        fi
    fi

     # --- Groupe libvirt ---
    local main_user
    main_user=${USER}

    if getent group libvirt >/dev/null 2>&1; then
        if id -nG "${main_user}" | grep -qw "libvirt"; then
            _OK "L'utilisateur ${main_user} est déjà dans le groupe libvirt."
        else
            _RUN "Ajout de l'utilisateur ${main_user} au groupe libvirt" sudo usermod -aG libvirt "${main_user}"
        fi
    fi

}

########################################################################################################################
SETUP_SYSTEMD(){
    local service
    local description
    for service in "${!SERVICES_TO_DISABLE[@]}"; do
        description="${SERVICES_TO_DISABLE[${service}]}"
        if systemctl is-enabled --quiet "${service}" 2>/dev/null; then
            _RUN "Désactivation du ${description}" sudo systemctl disable --now "${service}"
        else
            _INFO "Le ${description} est déjà désactivé."
        fi
    done
}

########################################################################################################################
SETUP_GRUB(){
    local is_grub zswap
    is_grub=$(_DETECT_GRUB)
    zswap="zswap.enabled=1 zswap.compressor=lz4" # on force l'usage d'un zswap, plus efficace que zram car s'appuie sur un backend physique en plus (file ou part)

    _SECTION "Configuration de GRUB"

    if [[ "${is_grub}" == "true" ]]; then
        local luks_param="" target_cmdline="" current_cmdline="" current_default=""

        if grep -q 'rd\.luks\.uuid=' /etc/default/grub; then
            luks_param=$(grep -oP 'rd\.luks\.uuid=\S+' /etc/default/grub | head -n 1)
        fi

        target_cmdline="${luks_param} rhgb ${zswap} ${CMDLINE} ${TTY_COLOR}"
        target_cmdline=$(echo "${target_cmdline}" | xargs)

        current_cmdline=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub | cut -d'"' -f2 || echo "")
        current_default=$(grep '^GRUB_DEFAULT=' /etc/default/grub | cut -d'=' -f2 || echo "")
        current_timeout=$(grep '^GRUB_TIMEOUT=' /etc/default/grub | cut -d'=' -f2 || echo "")

        if [[ "${current_cmdline}" != "${target_cmdline}" ]] || [[ "${current_default}" != "menu" ]] || [[ "${current_timeout}" != "2" ]]; then
            if [[ ! -f /etc/default/grub.origin ]]; then
                _RUNSILENT "" sudo cp -av /etc/default/grub /etc/default/grub.origin
            fi
            _RUNSILENT "" sudo cp -av /etc/default/grub /etc/default/grub.bak

            # Application des modifications (avec gestion de l'absence)
            _RUN "Mise à jour des paramètres de GRUB (zswap, menu affiché, ...)" sudo sed -i -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=menu/' -e "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${target_cmdline}\"|" /etc/default/grub

            if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
                _RUN "Mise à jour du délai de GRUB (2 sec)" sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
            else
                _RUN "Ajout d'un délai GRUB de 2 sec" sudo bash -c "echo 'GRUB_TIMEOUT=2' >> /etc/default/grub"
            fi

            _RUN "Regénération de la configuration de GRUB pour inclure les nouveaux paramètres" sudo grub2-mkconfig -o /boot/grub2/grub.cfg
        else
            _OK "GRUB est déjà correctement configuré."
        fi
    else
        _ERR "GRUB n'a pas été détecté, je ne change rien au bootloader."
    fi
}

########################################################################################################################
SETUP_FIREWALL() {

    # 1. Vérification de l'installation du paquet
    if ! rpm -q firewalld >/dev/null 2>&1; then
        _RUN "Installation de firewalld" sudo dnf install -y firewalld
    fi

    # 2. Vérification et activation du service
    if ! systemctl is-active --quiet firewalld; then
        _RUN "Démarrage et activation du service firewalld" sudo systemctl enable --now firewalld.service
    else
        _OK "Le service firewalld est déjà actif."
    fi

    # 3. Configuration des services essentiels
    local firewall_changed=false
    local service
    for service in "${FIREWALL_SERVICES[@]}"; do
        if sudo firewall-cmd --permanent --query-service="${service}" >/dev/null 2>&1; then
            _OK "Le service '${service}' est déjà autorisé."
        else
            _RUN "Autorisation du service '${service}'" sudo firewall-cmd --permanent --add-service="${service}"
            firewall_changed=true
        fi
    done

    # 4. Si on a fait au moins une modification, on recharge le pare-feu
    if [[ "${firewall_changed}" == true ]]; then
        _RUN "Rechargement des règles de firewalld (${FIREWALL_SERVICES[*]})" sudo firewall-cmd --reload
    fi
}

########################################################################################################################
SETUP_FSTAB(){
    _SECTION "Configuration FSTAB"
    # SWAPFILE
    local swapdir="/var/swap"
    if ! grep -q "${swapdir}/swapfile" /etc/fstab; then
        if [[ ! -f /etc/fstab.origin ]]; then
            _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.origin
        fi
        _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.bak.swap
        _RUN "Ajout du swap" sudo bash -c "echo ${swapdir}/swapfile none swap defaults 0 0 >> /etc/fstab"
    else
        _OK "Swap déjà présent dans /etc/fstab."
    fi

    # --- Optimisations Fstab (noatime, lazytime) ---
    local fstab_changed=false tmp_dir
    tmp_dir=$(mktemp -d)
    true > "${tmp_dir}/fstab.new" # on crée un fichier vide temporaire

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*# ]] || [[ -z "${line}" ]]; then # commentaire ou ligne vide ajouté "as is"
            echo "${line}" >> "${tmp_dir}/fstab.new"
            continue
        fi

        local dev mp fs opts dump pass
        read -r dev mp fs opts dump pass <<< "${line}"

        if [[ "${fs}" =~ ^(btrfs|ext4|xfs)$ ]]; then # si FS btrfs,ext4,xfs on va ajouter noatime/lazytime si absent
            local orig_opts="${opts}"

            if [[ ! ",${opts}," =~ ,noatime, ]]; then
                opts="${opts},noatime"
            fi
            if [[ ! ",${opts}," =~ ,lazytime, ]]; then
                opts="${opts},lazytime"
            fi
            if [[ ! ",${opts}," =~ ,commit, ]] && [[ "${fs}" = "ext4" ]]; then
                opts="${opts},commit=60"
            fi
            if [[ "${orig_opts}" != "${opts}" ]]; then
                fstab_changed=true
                printf "%-40s %-24s %-8s %-32s %-2s %s\n" "${dev}" "${mp}" "${fs}" "${opts}" "${dump}" "${pass}" >> "${tmp_dir}/fstab.new"
                continue
            fi
        fi

        echo "${line}" >> "${tmp_dir}/fstab.new"
    done < /etc/fstab

    if [[ "${fstab_changed}" == "true" ]]; then
        _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.bak.optimizations
        _RUN "Optimisations des systèmes de fichier" sudo cp -av "${tmp_dir}/fstab.new" /etc/fstab
        _RUNSILENT "" sudo systemctl daemon-reload
    else
        _OK "Les options d'optimisations sont déjà présentes dans /etc/fstab."
    fi

    # NFS
    if ! grep -q "${NFS_SHARE}" /etc/fstab >/dev/null; then
        if grep -q "${NFS_MP}" /etc/fstab >/dev/null; then
            _INFO "Le point de montage demandé (${NFS_MP}) est déjà présent dans /etc/fstab."
            _INFO "Abandon de l'installation du partage réseau NFS."
        else
            _RUNSILENT "" sudo mkdir -pv "${NFS_MP}"
            _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.bak.nfs
            echo "${NFS_SHARE}   ${NFS_MP}   nfs   defaults     0 0" | sudo tee -a /etc/fstab >/dev/null
            _RUNSILENT "" sudo systemctl daemon-reload
            _RUNSILENT "" sudo mount -v "${NFS_MP}"
            _RUN "Installation du partage réseau NFS." sudo ls -l "${NFS_MP}"
        fi
    else
        _RUN "Montage NFS déjà installé."
    fi
    # Nettoyage
    rm -rf "${tmp_dir}"
}

########################################################################################################################
SETUP_SWAP(){
    local target_size=$(( SWAP_SIZE * 1024 * 1024 * 1024))
    local recreate_swap=false
    local swapdir="/var/swap"

    if [[ -f "${swapdir}/swapfile" ]]; then
        local current_size
        current_size=$(sudo stat -c %s "${swapdir}/swapfile" 2>/dev/null || echo 0)

        if [[ "${current_size}" -ne "${target_size}" ]]; then
            _INFO "${swapdir}/swapfile existant mais taille différente de celle demandée (${current_size} octets). Recréation..."
            _RUNSILENT "" sudo swapoff "${swapdir}/swapfile"
            _RUNSILENT "" sudo rm -fv "${swapdir}/swapfile"
            recreate_swap=true
        else
            _OK "${swapdir}/swapfile est déjà correctement installé."
        fi
    else
        recreate_swap=true
    fi

    if [[ "${recreate_swap}" == "true" ]]; then
        local fs_type
        fs_type=$(stat -f -c %T /var)

        if [[ "${fs_type}" == "btrfs" ]]; then
            if [[ -e "${swapdir}" ]]; then
                if btrfs subvolume show "${swapdir}" >/dev/null 2>&1; then
                    _OK "Sous-volume BTRFS ${swapdir} existe déjà."
                else
                    _RUNSILENT "" sudo rm -rvf "${swapdir}"
                    _RUN "Création du sous-volume BTRFS ${swapdir}" sudo btrfs subvolume create "${swapdir}"
                fi
            else
                _RUN "Création du sous-volume BTRFS ${swapdir}" sudo btrfs subvolume create "${swapdir}"
            fi
            _RUN "Création du swapfile BTRFS (${SWAP_SIZE}GiB)" sudo btrfs filesystem mkswapfile --size "${SWAP_SIZE}g" "${swapdir}/swapfile"
        else # ext4, ...
            _RUNSILENT "" sudo mkdir -vp "${swapdir}"
            _RUN "Création du swapfile (${SWAP_SIZE}GiB)" sudo fallocate -l "${SWAP_SIZE}G" "${swapdir}/swapfile"
            _RUNSILENT "" sudo chmod 0600 -v "${swapdir}/swapfile"
            _RUNSILENT "" sudo mkswap "${swapdir}/swapfile"
        fi
    fi

    if ! swapon --show | grep -q "${swapdir}/swapfile"; then
        _RUN "Activation du swap" sudo swapon "${swapdir}/swapfile"
    else
        _OK "Swap déjà actif."
    fi


    # --- 2.5 SELinux : Autorisation pour systemd-logind ---
    # 1. On s'assure que le label est déclaré et appliqué (rapide et idempotent)
    if ! sudo semanage fcontext -l | grep -q "^${swapdir}(/.*)?"; then
        _RUN "Définition du contexte SELinux pour ${swapdir}" sudo semanage fcontext -a -t swapfile_t "${swapdir}(/.*)?"
    fi
    _RUNSILENT "" sudo restorecon -RF "${swapdir}"

    # 2. On vérifie si notre module SELinux local est déjà installé
    if ! sudo semodule -l | grep -q "^systemd_swap_search$"; then
        local selinux_tmp="/tmp/systemd_swap_search"

        # module SElinux pour gérer le swap
        local selinux_content
        selinux_content=$'module systemd_swap_search 1.0;\nrequire {\ntype swapfile_t;\ntype systemd_logind_t;\nclass dir search;\n}\n#============= systemd_logind_t ==============\nallow systemd_logind_t swapfile_t:dir search;\n'

        cat <<< "${selinux_content}" > "${selinux_tmp}.te"
        _RUNSILENT "" sudo checkmodule -M -m -o "${selinux_tmp}.mod" "${selinux_tmp}.te"
        _RUNSILENT "" sudo semodule_package -o "${selinux_tmp}.pp" -m "${selinux_tmp}.mod"
        _RUN "Installation du module SELinux systemd_swap_search" sudo semodule -i "${selinux_tmp}.pp"

        _RUNSILENT "" rm -fv "${selinux_tmp}.*"
    else
        _OK "Le module SELinux systemd_swap_search est déjà actif."
    fi
}

########################################################################################################################
SETUP_SUDO_RS() {
    _SECTION "Configuration sudo-rs"
    # 1. On installe sudo-rs
    if ! command -v sudo-rs &>/dev/null; then
        _RUN "Installation de sudo-rs" sudo dnf install -y sudo-rs
    else
        _OK "sudo-rs est déjà installé."
    fi

    # 2. Copie (sans suppression) des fichiers vers le monde sudo-rs
    local f_sudoers_rs="/etc/sudoers-rs"
    local d_sudoers_rs_d="/etc/sudoers-rs.d"

    if [[ -f "/etc/sudoers" && ! -f "${f_sudoers_rs}" ]]; then
        _RUN "Création de ${f_sudoers_rs} depuis l'original" sudo cp -a /etc/sudoers "${f_sudoers_rs}"
    fi

    if [[ -d "/etc/sudoers.d" && ! -d "${d_sudoers_rs_d}" ]]; then
        _RUN "Création de ${d_sudoers_rs_d} depuis l'original" sudo cp -a /etc/sudoers.d "${d_sudoers_rs_d}"
    fi

    # 3. Assurer la présence stricte des inclusions dans le nouveau fichier
    # CORRECTION : Utilisation de ~ comme délimiteur sed pour ne pas interférer avec le OU (|)
    if ! sudo grep -q "@includedir /etc/sudoers-rs.d" "${f_sudoers_rs}"; then
        _RUN "Configuration des includedir dans ${f_sudoers_rs}" sudo bash -c "
            sed -i -E 's~^(@|#)includedir[[:space:]]+/etc/sudoers\.d~@includedir /etc/sudoers-rs.d~g' '${f_sudoers_rs}'

            if ! grep -qE '^(@|#)includedir[[:space:]]+/etc/sudoers-rs\.d' '${f_sudoers_rs}'; then
                echo -e '\n@includedir /etc/sudoers-rs.d' >> '${f_sudoers_rs}'
            fi

            if ! grep -qE '^(@|#)includedir[[:space:]]+/etc/sudoers\.d' '${f_sudoers_rs}'; then
                echo -e '# Fallback pour les paquets Fedora\n@includedir /etc/sudoers.d' >> '${f_sudoers_rs}'
            fi
        "
    fi

    # 4. Remplacement du binaire sudo (La BASCULE CRITIQUE)
    local sys_sudo="/usr/bin/sudo"
    local sys_sudo_bak="/usr/bin/sudo.bak"
    local sudo_rs_bin="/usr/bin/sudo-rs"
    local local_bin_sudo="/usr/local/bin/sudo"

    local current_link=""
    if [[ -L "${sys_sudo}" ]]; then
        current_link=$(readlink "${sys_sudo}" || true)
    fi

    if [[ "${current_link}" == "${sudo_rs_bin}" ]]; then
        _OK "Le lien symbolique sudo -> sudo-rs est déjà en place."
    else
        # CORRECTION : On regroupe le 'mv' et le 'ln' dans le même appel sudo pour ne pas bloquer le système !
        _RUN "Remplacement radical du binaire sudo" sudo bash -c "
            if [[ -f '${sys_sudo}' && ! -L '${sys_sudo}' ]]; then
                mv -f '${sys_sudo}' '${sys_sudo_bak}'
            fi
            ln -sf '${sudo_rs_bin}' '${sys_sudo}'
        "
    fi
    _PASS
    _RUN "Symlink prioritaire /usr/local/bin/sudo -> sudo-rs" sudo ln -svf "${sudo_rs_bin}" "${local_bin_sudo}"
    _RUNSILENT "" sudo chmod -v 4111 "${sudo_rs_bin}"
    _RUNSILENT "" sudo chmod -v 0000 "${sys_sudo_bak}"

    # 5. Déploiement des règles spécifiques
    local pattern="%wheel ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper"
    local file="${d_sudoers_rs_d}/90-profile-sync-daemon"
    if ! sudo grep -q "${pattern}" "${file}" > /dev/null; then
        _RUN "Mise en place de la règle profile-sync-daemon." echo "${pattern}" | sudo tee "${file}" > /dev/null
    else
        _OK "Règle profile-sync-daemon déjà existante (${file})."
    fi

    local pattern="Defaults pwfeedback,timestamp_timeout=60"
    local file2="${d_sudoers_rs_d}/99-timeout"
    if ! sudo grep -q "${pattern}" "${file2}" > /dev/null; then
        _RUN "Mise en place de la règle timeout." echo "${pattern}" | sudo tee "${file2}" > /dev/null
    else
        _OK "Règle timeout déjà existante (${file2})."
    fi

    _RUNSILENT "" sudo chmod -v 0440 "${f_sudoers_rs}"
    _RUNSILENT "" sudo chmod -v 0750 "${d_sudoers_rs_d}"
    _RUNSILENT "" sudo chmod -v 0440 "${file}" "${file2}"

    # 6. Nettoyage radical des anciens fichiers
    if [[ -f "/etc/sudoers" && ! -L "/etc/sudoers" ]]; then
        _RUNSILENT "" sudo mv -vf /etc/sudoers /etc/sudoers.bak
    fi

    if [[ -d "/etc/sudoers.d" ]]; then
        _RUNSILENT "" sudo rm -vf /etc/sudoers.d/*
    else
        _RUNSILENT "" sudo mkdir -pv /etc/sudoers.d
        _RUNSILENT "" sudo chmod -v 0750 /etc/sudoers.d
    fi

    # 7. Blocage propre des futures mises à jour du vieux sudo par DNF
    _RUNSILENT "" sudo dnf versionlock add sudo
    _RUNSILENT "" sudo crudini --verbose --set /etc/dnf/dnf.conf main excludepkgs 'sudo'
    _OK "sudo-rs est en place et remplace définitivement sudo (dnf versionlock+excludepkgs)."
}

########################################################################################################################
SETUP_KDE_PLASMA() {
# on check KDE est lancé
    if pgrep -f '\b(plasmashell|kwin|kwin_wayland|plasma-desktop)\b'> /dev/null; then
        _SECTION "Personnalisation de KDE Plasma 6"

        # 1. Base Dark
        _RUN "Passage en mode Dark global" plasma-apply-lookandfeel -a org.kde.breezedark.desktop

        # 2. Color Scheme : Tokyo Night (Mise à jour sécurisée systématique)
        local color_dir="${HOME}/.local/share/color-schemes"
        local color_file="${color_dir}/TokyoNight.colors"
        local tokyo_url="https://raw.githubusercontent.com/Jayy-Dev/Plasma-Tokyo-Night/plasma-6/colorscheme/TokyoNight.colors"

        # -fsL garantit qu'on ne crée pas de fichier corrompu en cas de 404
        _RUN "Téléchargement de TokyoNight.colors" curl -fsL "${tokyo_url}" -o "${color_file}"

        if [[ ! -s "${color_file}" ]]; then
            _ERR "Le fichier téléchargé est introuvable ou vide. Faudra appliquer le schéma de couleurs manuellement..."
        else
            # Détection du nom exact par Plasma (extraction propre du premier mot)
            local scheme=""
            if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
                scheme="$(plasma-apply-colorscheme --list-schemes 2>/dev/null | grep -i 'tokyonight' | awk '{print $2}' | head -n1 || true)"
                [[ -z "${scheme}" ]] && _ERR "Tokyo Night non détecté par KDE Plasma ! Faudra appliquer manuellement..."
                _RUN "Application de la palette de couleurs ${scheme}" plasma-apply-colorscheme "${scheme}"
            fi
        fi

        # 3. Icônes : Tela Dark
        local temp_tela
        if ! find "${HOME}/.local/share/icons" -maxdepth 1 -type d -name "*Tela*" -print -quit | grep -q . >/dev/null; then
            temp_tela=$(mktemp -d)
            _RUN "Téléchargement des icônes Tela Dark" git clone --quiet https://github.com/vinceliuice/Tela-icon-theme.git "${temp_tela}/tela"
            _RUN "Installation des icônes Tela Dark" bash "${temp_tela}/tela/install.sh" -d "${HOME}/.local/share/icons"
            _RUNSILENT "" rm -rvf "${temp_tela}"
        else
            _INFO "Le pack d'icônes Tela Dark est déjà installé."
        fi

        # 4. Curseur : Bibata Lavender (via Catppuccin Mocha)
        local temp_cursor
        temp_cursor=$(mktemp -d)
        if ! find "${HOME}/.local/share/icons" -maxdepth 1 -type d -name "*catppuccin-mocha-lavender-cursors*" -print -quit | grep -q . >/dev/null; then
            _RUN "Installation du curseur Bibata Lavender" curl -fsL "https://github.com/catppuccin/cursors/releases/latest/download/catppuccin-mocha-lavender-cursors.zip" -o "${temp_cursor}/cursor.zip"
            _RUNSILENT "" unzip -q -o "${temp_cursor}/cursor.zip" -d "${HOME}/.local/share/icons/"
        else
            _INFO "Le pack de curseurs Bibata Lavender est déjà installé."
        fi

        # Pointeur par défaut pour compatibilité GTK
        if [[ -f "${HOME}/.local/share/icons/default/index.theme" ]] && ! grep -q "catppuccin-mocha-lavender-cursors" "${HOME}/.local/share/icons/default/index.theme"; then
            echo -e "[Icon Theme]\nInherits=catppuccin-mocha-lavender-cursors" > "${HOME}/.local/share/icons/default/index.theme"
        fi

        # Baloo
        if command -v balooctl6 >/dev/null 2>&1; then
            _RUN "Désactivation du service d'indexation de KDE Plasma (baloo)" bash -c "balooctl6 suspend ; balooctl6 disable ; balooctl6 purge"
        else
            _INFO "L'outil balooctl n'est pas installé. Aucune action requise."
        fi

        # Configuration des thèmes pour les applications Flatpak (Mode global/system-wide overrides)
        _RUN "Application du thème (Tokyo Night, Tela, Bibata) aux Flatpaks" sudo flatpak override \
            --filesystem="${HOME}/.local/share/icons:ro" \
            --filesystem="${HOME}/.local/share/themes:ro" \
            --filesystem="${HOME}/.icons:ro" \
            --filesystem="xdg-config/gtk-3.0:ro" \
            --filesystem="xdg-config/gtk-4.0:ro" \
            --env="GTK_THEME=TokyoNight" \
            --env="ICON_THEME=Tela-dark" \
            --env="XCURSOR_THEME=catppuccin-mocha-lavender-cursors"

        # déplacement du panneau principal
        # local target_pos="${KDEPANEL:-bottom}" # fallback en bas
        # if ! pgrep plasmashell > /dev/null 2>&1; then # pas de session KDE en cours
        #     _INFO "plasmashell ne tourne pas. Configuration du panneau reportée."
        # else
        #     plasma_eval() {
        #         local script="$1"
        #         busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "${script}"
        #     }
        #     _RUN "Déplacement du panneau en position ${target_pos}" plasma_eval "
        #         var allPanels = panels();
        #         for (var i = 0; i < allPanels.length; i++) {
        #             allPanels[i].location = \"${target_pos}\";
        #             }
        #     "
        #     _RUNSILENT "" systemctl --user restart plasma-plasmashell.service
        # fi
        if pgrep plasmashell > /dev/null 2>&1; then
            _RUN "Redémarrage de l'interface de KDE Plasma 6..." bash -c "\
            kwriteconfig6 --file kdeglobals --group Icons --key Theme \"Tela-dark\" ;\
            kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme \"catppuccin-mocha-lavender-cursors\" ;\
            [[ -n \"${scheme}\" ]] && kwriteconfig6 --file kdeglobals --group General --key ColorScheme \"${scheme}\" ;\
            plasma-apply-wallpaperimage \"${HOME}/.local/share/wallpapers/SpacePlasma.jpg\" ;\
            systemctl --user restart plasma-plasmashell.service"
        fi
    else
        echo
        _INFO "KDE n'a pas été détecté... Je ne touche pas à la customization de KDE."
    fi
}

########################################################################################################################
SETUP_PLM() {
# on teste si KDE tourne
    if pgrep -f '\b(plasmashell|kwin|kwin_wayland|plasma-desktop)\b'> /dev/null; then

        if ! rpm -q plasma-login-manager >/dev/null 2>&1; then
            _RUN "Installation de plasma-login-manager" sudo dnf install -y plasma-login-manager kcm-plasmalogin
        else
            _OK "plasma-login-manager déjà installé."
        fi

        if systemctl is-enabled --quiet sddm.service 2>/dev/null; then
            _RUN "Désactivation de SDDM à partir du prochain boot" sudo systemctl disable sddm.service
        else
            _INFO "SDDM déjà désactivé."
        fi

        if systemctl is-enabled --quiet plasmalogin.service 2>/dev/null; then
            _OK "plasmalogin.service déjà activé."
        else
            _RUN "Activation de Plasma Login Manager à partir du prochain boot" sudo systemctl enable --force plasmalogin.service
        fi
    else
        echo
        _INFO "KDE n'a pas été détecté... Je ne touche pas au display-manager."
    fi
}

########################################################################################################################
MAIN "$@"

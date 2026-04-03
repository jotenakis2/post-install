#!/usr/bin/env bash
set -euo pipefail
# ─── Variables globales ────────────────────────────────────────────────────────
readonly VER=2.7
MYREPOS="https://codeberg.org/jotenakis"
GIT_DIR="${HOME}/git"
DNF_PACKAGES=(
    zsh fastfetch util-linux-script sudo-rs foot ghostty kitty eza fzf neovim bat bat-extras grc axel rclone procs
    wl-clipboard glow expect sqlite btop atop glances nvtop gping iftop gdu duf speedtest-cli kate shfmt ShellCheck inxi
    nodejs-bash-language-server golang make mpv vlc libdvdcss foliate imv plasma-login-manager thunderbird
    vesktop telegram-desktop qbittorrent brave-browser helium-browser-bin qemu virt-manager virt-viewer gum stress-ng
    libreoffice-langpack-fr nss-tools ldns-utils profile-sync-daemon htop micro
    # Ajoute tes autres paquets ici
)
DNF_REMOVE=(
    zram-generator-defaults PackageKit-glib google-noto-sans-mono-cjk-vf-fonts akonadi-server kdeconnectd
    libreswan plasma-drkonqi ibus imsettings maliit-keyboard abrt plasma-discover
    # Ajoute tes autres paquets ici
)
FONTS=(
    jetbrainsmono-nerd-fonts
    iosevka-nerd-fonts
    # Ajoute tes autres paquets ici
)
FLATPAK_PKGS=(
    "com.ktechpit.whatsie"
    "org.gnome.Showtime"
    "io.github.giantpinkrobots.flatsweep"
    "com.github.tchx84.Flatseal"
    # Ajoute tes autres paquets ici
)
CARGO_PACKAGES=(
    bandwhich bat bottom cargo-update diskus fd-find hyperfine netscanner parallel-disk-usage resvg
    ripgrep sd sheldon tealdeer yazi-fm yazi-cli zoxide zsh-patina
    # Ajoute tes autres paquets ici
)
declare -A BIN_MAPPING=(
        ["yazi-fm"]="yazi"
        ["yazi-cli"]="ya"
        ["tealdeer"]="tldr"
        ["parallel-disk-usage"]="pdu"
        ["fd-find"]="fd"
        ["bottom"]="btm"
        ["ripgrep"]="rg"
        ["cargo-update"]="cargo-install-update cargo-install-update-config"
        # Ajoute tes autres correspondances ici
)
DOTFILES_REPO="${MYREPOS}/dotfiles"
DOTFILES_DIR="${GIT_DIR}/dotfiles"
GIT_REPOS=(
    "${MYREPOS}/fedupdate.git|${GIT_DIR}/fedupdate"
    "${MYREPOS}/backupsystem.git|${GIT_DIR}/backupsystem"
    "${MYREPOS}/scripts.git|${GIT_DIR}/scripts"
    "${DOTFILES_REPO}|${DOTFILES_DIR}"
    # Ajoute tes autres "repos|dossierlocaux" ici
)
FIREWALL_SERVICES=(
    "mdns"
    "ipp-client"
    "samba-client"
    # ajoute tes autres services réseaux à autoriser ici
)
declare -A SERVICES_TO_DISABLE=(
    ["ModemManager.service"]="service ModemManager"
    ["rsyslog.service"]="service rsyslog"
    # ajoute tes autres services systemd à désactiver ici
)
# ─── /Variables globales ───────────────────────────────────────────────────────



# ─── MAIN ──────────────────────────────────────────────────────────────────────
MAIN() {
    INITIALIZE
    CHECK_ENV
    _PASS
    _RUN "Mise à jour forcée du système" sudo dnf upgrade --refresh -y
    REMOVE_RPM_PACKAGES
    INSTALL_REPOS
    INSTALL_RPM_PACKAGES
    INSTALL_FONTS
    INSTALL_CODECS
    INSTALL_RUST
    INSTALL_CARGO_PACKAGES
    INSTALL_FLATPAK_PACKAGES
    #
    CLONE_REPOS
    SETUP_SHELL
    SETUP_DOTFILES
    SETUP_SYSTEM
    SETUP_FIREWALL
    CUSTOMIZE_KDE_PLASMA
    REPLACE_SDDM_WITH_PLM
    _PASS
    SETUP_SUDO_RS

    printf "\n%b%b  ✓ Terminé — rebooter pour appliquer les modifications.%b\n" "${C_GREEN}" "${C_BOLD}" "${C_RESET}"
    printf "%b  Log complet : %s%b\n\n" "${C_MAGENTA}" "${LOG_FILE}" "${C_RESET}"

    _PASS
    sudo rm -f "${SUDOTMP}"
}























#################################################################################################################################
#################################################################################################################################
#################################################################################################################################


# ─── Init ─────────────────────────────────────────────────────────────
INITIALIZE() {
    C_RESET='' C_RED='' C_GREEN='' C_YELLOW='' C_MAGENTA='' C_CYAN='' C_BOLD=''
    if [[ -t 1 ]]; then
        C_RESET='\e[0m'
        C_BOLD='\e[1m'
        C_RED='\e[1;31m'
        C_GREEN='\e[1;32m'
        C_YELLOW='\e[1;33m'
        C_MAGENTA='\e[1;35m'
        C_CYAN='\e[1;36m'
    fi
    LOG_DIR="${HOME}/.local/log"
    LOG_FILE="${LOG_DIR}/post-install-fedora-$(date +%Y%m%d-%H%M%S).log"
    INSTALL_DIR="${HOME}/.local/bin"
    # RUST
    export RUSTUP_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/rustup"
    export CARGO_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/cargo"
    # GO
    export GOPATH="${XDG_DATA_HOME:-${HOME}/.local/share}/go"
    export GOBIN="${XDG_BIN_HOME:-${HOME}/.local/bin}"

    mkdir -p "${GIT_DIR}" "${LOG_DIR}" "${INSTALL_DIR}" "${RUSTUP_HOME}" "${CARGO_HOME}" "${GOPATH}" "${GOBIN}" "${HOME}/.local/share/zsh"
    _PASS
    sudo mkdir -p "/usr/local/bin"

    # Préparation d'une session sudo confortable et longue pour l'installation
    SUDOTMP="/etc/sudoers-rs.d/99_POST-INSTALL" # pour delete à la fin
    local sudotmp="/etc/sudoers.d/99_POST-INSTALL"
    sudo mkdir -p /etc/sudoers.d
    sudo bash -c "echo 'Defaults pwfeedback,timestamp_timeout=180' > '${sudotmp}'"
    sudo chmod 0440 "${sudotmp}"

    # PATH
    export PATH="${GOBIN}:${CARGO_HOME}/bin:${INSTALL_DIR}:${PATH}"

    SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

    #
    _BANNER
}
# ─── Helpers divers _XXX ─────────────────────────────────────────────────────
_BANNER() {
    printf "%b%b\n  ╔════════════════════════════════════╗\n  ║      Post-install Fedora (${VER})     ║\n  ╚════════════════════════════════════╝%b\n  Log : %s\n\n" "${C_CYAN}" "${C_BOLD}" "${C_MAGENTA}" "${LOG_FILE}"
    echo -ne "${C_RESET}"
}

_SECTION()  { printf "\n%b%b━━━ %s ━━━%b\n" "${C_CYAN}" "${C_BOLD}" "$*" "${C_RESET}" | tee -a "${LOG_FILE}"; }
_OK()       { printf " %b✓%b %s\n" "${C_GREEN}"  "${C_RESET}" "$*" | tee -a "${LOG_FILE}"; }
_ERR()      { printf " %b✗%b %s\n" "${C_RED}"    "${C_RESET}" "$*" | tee -a "${LOG_FILE}" >&2; }
_INFO()     { printf " %b→%b %s\n" "${C_YELLOW}"   "${C_RESET}" "$*" | tee -a "${LOG_FILE}"; }
_DIE()      { _ERR "$*"; exit 1; }

_PASS() {
    # On vérifie silencieusement si l'autorisation est requise, si oui on gère un joli prompt
    if ! sudo -n true 2>/dev/null; then
        printf "\n%b[🔐 SUDO]%b Autorisation requise pour %b%s%b : " "${C_RED}" "${C_RESET}" "${C_BOLD}" "${USER}" "${C_RESET}"
        sudo -v -p ""
    fi
}

_RUN() {
    local msg="$1"; shift

    spin() {
        local pid="$1" msg="$2" i=0
        while kill -0 "${pid}" 2>/dev/null; do
            printf "\r %b%s%b %s" "${C_GREEN}" "${SPIN_FRAMES[$((i % 10))]}" "${C_RESET}" "${msg}"
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
        # SC2312 : On stocke le résultat séparément
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
        _PASS
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

trap '_ERR "Interruption ligne ${LINENO}"; _DIE "Log : ${LOG_FILE}"' _ERR

# ─── 0. Vérification shell ─────────────────────────────────────────────────────
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

    _PASS
    _RUN "Dépendances initiales (curl, git, stow, pciutils, binutils, dnf-plugins-core policycoreutils-python-utils)" sudo dnf install -y curl git stow pciutils dnf-plugins-core binutils policycoreutils-python-utils

    local fedora_rel
    fedora_rel=$(cat /etc/fedora-release)
    _OK "Environnement valide — ${fedora_rel}"
}

# ─── 1. Suppression paquets indésirables ───────────────────────────────────────
REMOVE_RPM_PACKAGES() {
    _SECTION "Suppression paquets indésirables"

    local pkg
    _PASS
    for pkg in "${DNF_REMOVE[@]}"; do
        if rpm -q "${pkg}" &>/dev/null; then
            _RUN "Suppression ${pkg}" sudo dnf remove -y "${pkg}"
        else
            _OK "${pkg} absent — ignoré."
        fi
    done

    # systemd-networkd : supprimé seulement si NetworkManager est actif
    if systemctl is-active --quiet NetworkManager; then
        if rpm -q systemd-networkd &>/dev/null; then
            _PASS
            _RUN "Suppression systemd-networkd (NetworkManager actif)" sudo dnf remove -y systemd-networkd
        else
            _OK "systemd-networkd absent — ignoré."
        fi
    else
        _INFO "NetworkManager inactif — systemd-networkd conservé."
    fi
}

# ─── 2. Dépôts ─────────────────────────────────────────────────────────────────
INSTALL_REPOS() {
    _SECTION "Dépôts"

    local fedora_ver
    fedora_ver=$(rpm -E '%fedora')

    _PASS
    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        _RUN "RPM Fusion free (f${fedora_ver})" sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"${fedora_ver}".noarch.rpm
        _RUN "RPM Fusion free tainted (f${fedora_ver})" sudo dnf install -y rpmfusion-free-release-tainted
    else
        _OK "RPM Fusion free déjà présent."
    fi
    _PASS
    if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
        _RUN "RPM Fusion nonfree (f${fedora_ver})" sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"${fedora_ver}".noarch.rpm
        _RUN "RPM Fusion nonfree tainted (f${fedora_ver})" sudo dnf install -y rpmfusion-nonfree-release-tainted
    else
        _OK "RPM Fusion nonfree déjà présent."
    fi
    _PASS
    if rpm -q rpmfusion-free-appstream-data &>/dev/null; then
        _RUN "suppression métadonnées appstream free" sudo dnf remove -y rpmfusion-free-appstream-data
    fi
    if rpm -q rpmfusion-nonfree-appstream-data &>/dev/null; then
        _RUN "suppression métadonnées appstream nonfree" sudo dnf remove -y rpmfusion-nonfree-appstream-data
    fi
    _PASS
    if ! rpm -q terra-release &>/dev/null; then
        # shellcheck disable=SC2016
        _RUN "Terra (f${fedora_ver})" sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
    else
        _OK "Terra déjà présent."
    fi
    _PASS
    if ! dnf copr list 2>/dev/null | grep -q "bigmenpixel/profile-sync-daemon"; then
        _RUN "COPR profile-sync-daemon" sudo dnf copr enable -y bigmenpixel/profile-sync-daemon
    else
        _OK "COPR profile-sync-daemon déjà présent."
    fi
    _PASS
    if ! dnf repolist 2>/dev/null | grep -q "brave-browser"; then
        _RUN "Brave Browser Repo" sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
    else
        _OK "Brave Browser Repo est déjà présent."
    fi
    _PASS
    _RUN "Rafraîchissement des métadonnées" sudo dnf makecache
}

# ─── 3. Nerd Fonts ─────────────────────────────────────────────────────────────
INSTALL_FONTS() {
    _SECTION "Nerd Fonts"

    local font
    _PASS
    for font in "${FONTS[@]}"; do
        if ! rpm -q "${font}" &>/dev/null; then
            _RUN "Installation ${font}" sudo dnf install -y "${font}"
        else
            _OK "${font} déjà présente."
        fi
    done
}

# ─── 4. Codecs & Mesa ──────────────────────────────────────────────────────────
INSTALL_CODECS() {
    _SECTION "Codecs multimédia"

    _PASS
    if ! rpm -q ffmpeg &>/dev/null; then
        _RUN "Swap ffmpeg-free → ffmpeg" sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    else
        _OK "ffmpeg (RPM Fusion) déjà présent."
    fi

    #_RUN "Groupe multimedia" sudo dnf groupupdate -y multimedia --setopt='install_weak_deps=False' --exclude=PackageKit-gstreamer-plugin
    #_RUN "Groupe sound-and-video" sudo dnf groupupdate -y sound-and-video

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

# ─── 5. Paquets DNF ────────────────────────────────────────────────────────────
INSTALL_RPM_PACKAGES() {
    _SECTION "Paquets RPM"

    local pkg
    local -a missing_packages=()

    for pkg in "${DNF_PACKAGES[@]}"; do
        if ! rpm -q "${pkg}" &>/dev/null; then
            missing_packages+=("${pkg}")
        else
            _OK "${pkg} est déjà installé — ignoré."
        fi
    done

    if ((${#missing_packages[@]})); then
        _PASS
        _RUN "Installation des paquets RPM manquants" sudo dnf install -y "${missing_packages[@]}"
        _OK "Les paquets ${missing_packages[*]} ont été correctement installés."
    else
        _INFO "Tous les paquets RPM sont déjà installés."
    fi
}

# ─── 6. Rustup ─────────────────────────────────────────────────────────────────
INSTALL_RUST() {
    _SECTION "Toolchain Rust"

    if command -v rustup &>/dev/null; then
        _RUN "Mise à jour rustup stable" rustup update stable
    else
        _RUN "Installation rustup" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable'
    fi
}

# ─── 7. Paquets Cargo ──────────────────────────────────────────────────────────
INSTALL_CARGO_PACKAGES() {
    _SECTION "Paquets Cargo binaires"

    # 1. Installation de cargo-binstall sans compilation
    if ! command -v cargo-binstall &>/dev/null; then
        _RUN "Installation de cargo-binstall (pré-compilé)" bash -c "curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash"
    else
        _OK "cargo-binstall est déjà installé."
    fi
    _RUN " Lien symbolique : cargo-binstall -> /usr/local/bin" sudo ln -sf "${CARGO_HOME}/bin/cargo-binstall" "/usr/local/bin/"

    local cmd
    for cmd in "${CARGO_PACKAGES[@]}"; do

        # 1. Installation du paquet via Cargo (binstall)
        if cargo install --list | grep -q "^${cmd} "; then
            _OK "${cmd} déjà installé."
        else
            _RUN "Installation binaire de ${cmd}" cargo binstall --no-confirm "${cmd}"
        fi

        # 2. Création des liens symboliques dans /usr/local/bin
        local bins_to_link
        if [[ -n "${BIN_MAPPING[${cmd}]:-}" ]]; then
            bins_to_link="${BIN_MAPPING[${cmd}]}"
        else
            bins_to_link="${cmd}"
        fi

        local bin_name src_bin dest_link current_target
        _PASS
        for bin_name in ${bins_to_link}; do
            src_bin="${CARGO_HOME}/bin/${bin_name}"
            dest_link="/usr/local/bin/${bin_name}"

            if [[ -x "${src_bin}" ]]; then
                # Résolution de SC2312 : On gère readlink séparément
                current_target=""
                if [[ -L "${dest_link}" ]]; then
                    current_target=$(readlink -f "${dest_link}" || true)
                fi

                if [[ "${current_target}" != "${src_bin}" ]]; then
                    _RUN " Lien symbolique : ${bin_name} -> /usr/local/bin" sudo ln -sf "${src_bin}" "${dest_link}"
                else
                    _OK " Lien symbolique ${bin_name} déjà présent."
                fi
            else
                _ERR " Binaire introuvable : ${src_bin}"
            fi
        done
    done

    # 3. Ajustement des permissions pour l'accès global
    _RUN "Permissions : accès global aux binaires Cargo" \
        chmod a+x "${HOME}" \
        "${HOME}/.local" \
        "${HOME}/.local/share" \
        "${CARGO_HOME}" \
        "${CARGO_HOME}/bin"
}

# ─── 8. Outils git  ────────────────────────────────────────────────────────────
# INSTALL_GIT_TOOLS() {
#     _SECTION "Outils git"
#
#     local tool url
#
#     for tool in "${!GIT_TOOLS[@]}"; do
#         url="${GIT_TOOLS[${tool}]}"
#         _RUN "Installation ${tool}" bash -c "curl -fsSL '${url}' -o '${INSTALL_DIR}/${tool}' && chmod +x '${INSTALL_DIR}/${tool}'"
#         _OK "${tool} → ${INSTALL_DIR}/${tool}"
#     done
# }

# ─── 8. Clonage des dépôts Git personnels ─────────────────────────────────────
CLONE_REPOS() {
    _SECTION "Clonage et mise à jour des dépôts Git personnels"

    local repo_entry repo_url dest_dir repo_name backup_dir

    for repo_entry in "${GIT_REPOS[@]}"; do
        # Extraction de l'URL et de la destination (séparées par '|')
        repo_url="${repo_entry%%|*}"
        dest_dir="${repo_entry##*|}"

        # Récupération du nom du dépôt pour l'affichage (ex: "scripts")
        repo_name=$(basename "${repo_url}" .git)

        if [[ -d "${dest_dir}/.git" ]]; then
            # C'est un dépôt Git valide, on le met à jour
            _RUN "Mise à jour de ${repo_name} (pull --ff-only)" git -C "${dest_dir}" pull --ff-only
        else
            # Le chemin existe MAIS n'est pas un dépôt Git (ou c'est un fichier)
            if [[ -e "${dest_dir}" ]]; then
                backup_dir="${dest_dir}_backup_$(date +%Y%m%d%H%M%S)"
                _RUN "Sauvegarde de l'existant non-git (${repo_name})" mv "${dest_dir}" "${backup_dir}"
                _INFO "Ancien '${dest_dir}' sauvegardé dans '${backup_dir}'"
            fi

            # La voie est libre, on clone
            _RUN "Clonage de ${repo_name}" git clone "${repo_url}" "${dest_dir}"
        fi
    done

    _OK "Tous les dépôts Git sont à jour."
}

# ─── 9. Shell par défaut ───────────────────────────────────────────────────────
SETUP_SHELL() {
    _SECTION "Shell par défaut → zsh"

    # 1- zsh
    local zsh_bin
    zsh_bin=$(command -v zsh)

    _PASS
    if ! grep -qxF "${zsh_bin}" /etc/shells; then
        echo "${zsh_bin}" | sudo tee -a /etc/shells > /dev/null
        _OK "${zsh_bin} ajouté à /etc/shells."
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
    _OK "Installation du Prompt Oh-My-Posh"
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
        chmod 777 "${omp_bin}"
    fi
}

# ─── 10. Dotfiles ──────────────────────────────────────────────────────────────
SETUP_DOTFILES() {
    _SECTION "Dotfiles"
    if [[ ! -d "${DOTFILES_DIR}" ]]; then
        _ERR "Le dossier ${DOTFILES_DIR} est introuvable. Stow ignoré."
        return
    fi

    # 1- nettoyage
    local skel_files=(".bashrc" ".bash_logout" ".zshenv" ".zshrc")
    local f
    for f in "${skel_files[@]}"; do
        if [[ -f "${HOME}/${f}" && ! -L "${HOME}/${f}" ]]; then
            _RUN "Suppression du fichier système par défaut ${f}" rm -f "${HOME}/${f}"
        fi
    done

    # 2- stow pour déployer dotfiles depuis dépôt git
    local pkg name
    for pkg in "${DOTFILES_DIR}"/*/; do
        name=$(basename "${pkg}")
        _RUN "stow : ${name}" stow --dir="${DOTFILES_DIR}" --target="${HOME}" --restow "${name}"
    done
    _INFO "Les dotfiles ne sont déployés que pour l'utilisateur qui lance le script (${USER})"

}

# ─── 11. Configuration Système & Optimisations ─────────────────────────────────
SETUP_SYSTEM() {
    _SECTION "Configuration Système (Réseau, Swap, GRUB, Sysctl, Fstab, Brave, Chrony)"
    # --- 1. NetworkManager & systemd-resolved ---
    # --- 2. Swapfile BTRFS / Ext4 / XFS ---
        # --- 2.5 SELinux : Autorisation pour systemd-logind ---
    # --- 3. Configuration GRUB ---
    # --- 4. Optimisations Kernel (Sysctl) ---
    # --- 5. Optimisations Fstab (noatime, lazytime) ---
    # --- 6. Configuration Brave Browser (Policies debloat) ---
    # --- 7. Configuration Chrony (IPv4 only) ---
    # --- 8. Groupe libvirt ---
    # --- 9. sudo/sudo-rs --- => remplacé par SETUP_SUDO_RS
    # --- 10. profile-sync-daemon --- A FAIRE
    # --- 11. services systemd --- A FAIRE
    # --- 12. dnf.conf ---

    local tmp_dir
    tmp_dir=$(mktemp -d)

    # --- 1. NetworkManager & systemd-resolved ---
    cat << 'EOF' > "${tmp_dir}/99-global-dns.conf"
[main]
dns=systemd-resolved
EOF

    cat << 'EOF' > "${tmp_dir}/dns_servers.conf"
[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net
FallbackDNS=1.1.1.1#one.one.one.one
Domains=~.
DNSOverTLS=yes
DNSSEC=yes
EOF

    cat << 'EOF' > "${tmp_dir}/10-disable-llmnr.conf"
[Resolve]
LLMNR=no
EOF
    _PASS
    _RUN "Déploiement configs DNS" sudo bash -c "
        mkdir -p /etc/NetworkManager/conf.d /etc/systemd/resolved.conf.d &&
        install -m 644 -o root -g root '${tmp_dir}/99-global-dns.conf' /etc/NetworkManager/conf.d/ &&
        install -m 644 -o root -g root '${tmp_dir}/dns_servers.conf' /etc/systemd/resolved.conf.d/ &&
        install -m 644 -o root -g root '${tmp_dir}/10-disable-llmnr.conf' /etc/systemd/resolved.conf.d/ &&
        ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
    "
    _RUN "Redémarrage NetworkManager & systemd-resolved" sudo systemctl restart systemd-resolved NetworkManager


    # --- 2. Swapfile BTRFS / Ext4 / XFS ---
    local target_size=$((20 * 1024 * 1024 * 1024)) # 20 GiB en octets
    local recreate_swap=false

    if [[ -f "/var/swap/swapfile" ]]; then
        local current_size
        current_size=$(sudo stat -c %s /var/swap/swapfile 2>/dev/null || echo 0)

        if [[ "${current_size}" -ne "${target_size}" ]]; then
            _INFO "Swapfile existant mais taille différente (${current_size} octets). Recréation..."
            sudo swapoff /var/swap/swapfile 2>/dev/null || true
            sudo rm -f /var/swap/swapfile
            recreate_swap=true
        else
            _OK "Swapfile existant et à la bonne taille (20GiB)."
        fi
    else
        recreate_swap=true
    fi

    if [[ "${recreate_swap}" == "true" ]]; then
        local fs_type
        fs_type=$(stat -f -c %T /var)

        _PASS
        if [[ "${fs_type}" == "btrfs" ]]; then
            if ! sudo btrfs subvolume show /var/swap >/dev/null 2>&1; then
                _RUN "Création du sous-volume BTRFS /var/swap" sudo btrfs subvolume create /var/swap
            else
                _OK "Sous-volume BTRFS /var/swap déjà existant."
            fi
            _RUN "Création du swapfile BTRFS (20G)" sudo btrfs filesystem mkswapfile --size 20g /var/swap/swapfile
        else
            _RUN "Création du dossier /var/swap" sudo mkdir -p /var/swap
            _RUN "Allocation du swapfile classique (20G)" sudo fallocate -l 20G /var/swap/swapfile
            _RUN "Droits sur le swapfile" sudo chmod 0600 /var/swap/swapfile
            _RUN "Formatage du swapfile" sudo mkswap /var/swap/swapfile
        fi
    fi

    if ! swapon --show | grep -q "/var/swap/swapfile"; then
        _RUN "Activation du swap" sudo swapon /var/swap/swapfile
    else
        _OK "Swap déjà actif en mémoire."
    fi

    if ! grep -q "/var/swap/swapfile" /etc/fstab; then
        _RUN "Ajout du swap à /etc/fstab" sudo bash -c 'echo "/var/swap/swapfile none swap defaults 0 0" >> /etc/fstab'
    else
        _OK "Swap déjà présent dans /etc/fstab."
    fi

    # --- 2.5 SELinux : Autorisation pour systemd-logind ---
    # 1. On s'assure que le label est déclaré et appliqué (rapide et idempotent)
    if ! sudo semanage fcontext -l | grep -q "^/var/swap(/.\*)?"; then
        _RUN "Déclaration du contexte SELinux pour /var/swap (swapfile_t)" sudo semanage fcontext -a -t swapfile_t '/var/swap(/.*)?'
    fi
    _RUN "Application du contexte SELinux pour /var/swap (swapfile_t)" sudo restorecon -RF /var/swap

    # 2. On vérifie si notre module SELinux local est déjà installé
    if ! sudo semodule -l | grep -q "^systemd_swap_search$"; then
        local selinux_tmp="/tmp/systemd_swap_search"

        cat << 'EOF' > "${selinux_tmp}.te"
module systemd_swap_search 1.0;
require {
        type swapfile_t;
        type systemd_logind_t;
        class dir search;
}
#============= systemd_logind_t ==============
allow systemd_logind_t swapfile_t:dir search;
EOF

        _RUN "Compilation du module SELinux systemd_swap_search" sudo checkmodule -M -m -o "${selinux_tmp}.mod" "${selinux_tmp}.te"
        _RUN "Packaging du module SELinux systemd_swap_search" sudo semodule_package -o "${selinux_tmp}.pp" -m "${selinux_tmp}.mod"
        _RUN "Installation du module SELinux systemd_swap_search" sudo semodule -i "${selinux_tmp}.pp"

        rm -f "${selinux_tmp}.*"
    else
        _OK "Le module SELinux 'systemd_swap_search' est déjà actif."
    fi

    # --- 3. Configuration GRUB ---
    local is_grub
    is_grub=$(_DETECT_GRUB)

    if [[ "${is_grub}" == "true" ]]; then
        local luks_param="" target_cmdline="" current_cmdline="" current_default=""

        if grep -q 'rd\.luks\.uuid=' /etc/default/grub; then
            luks_param=$(grep -oP 'rd\.luks\.uuid=\S+' /etc/default/grub | head -n 1)
        fi

        target_cmdline="${luks_param} rhgb loglevel=5 rd.systemd.show_status=1 ipv6.disable=1 zswap.enabled=1 zswap.compressor=lz4 vt.default_red=30,243,166,249,137,245,148,186,88,243,166,249,137,245,148,166 vt.default_grn=30,139,227,226,180,194,226,194,91,139,227,226,180,194,226,173 vt.default_blu=46,168,161,175,250,231,213,222,112,168,161,175,250,231,213,200"
        target_cmdline=$(echo "${target_cmdline}" | xargs)

        current_cmdline=$(grep '^GRUB_CMDLINE_LINUX=' /etc/default/grub | cut -d'"' -f2 || echo "")
        current_default=$(grep '^GRUB_DEFAULT=' /etc/default/grub | cut -d'=' -f2 || echo "")
        current_timeout=$(grep '^GRUB_TIMEOUT=' /etc/default/grub | cut -d'=' -f2 || echo "")

        if [[ "${current_cmdline}" != "${target_cmdline}" ]] || [[ "${current_default}" != "menu" ]] || [[ "${current_timeout}" != "2" ]]; then
            _PASS
            # 1. Sauvegarde originelle qui ne sera jamais écrasée
            if [[ ! -f /etc/default/grub.origin ]]; then
                _RUN "Sauvegarde originale de /etc/default/grub" sudo cp -a /etc/default/grub /etc/default/grub.origin
            fi

            # 2. Sauvegarde de travail (écrasée à chaque modification)
            _RUN "Sauvegarde de travail dans /etc/default/grub.bak" sudo cp -a /etc/default/grub /etc/default/grub.bak

            # 3. Application des modifications (avec gestion de l'absence)
            _RUN "Mise à jour de GRUB_DEFAULT et GRUB_CMDLINE_LINUX" sudo sed -i -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=menu/' -e "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${target_cmdline}\"|" /etc/default/grub
            if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
                _RUN "Mise à jour de GRUB_TIMEOUT (2 sec)" sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
            else
                _RUN "Ajout de GRUB_TIMEOUT=2" sudo bash -c "echo 'GRUB_TIMEOUT=2' >> /etc/default/grub"
            fi

            _RUN "Regénération de GRUB" sudo grub2-mkconfig -o /boot/grub2/grub.cfg
        else
            _OK "Configuration GRUB déjà à jour."
        fi
    else
        _ERR "GRUB n'a pas été détecté, je ne change rien au bootloader."
    fi

    # --- 4. Optimisations Kernel (Sysctl) ---
    cat << 'EOF' > "${tmp_dir}/99-swap.conf"
vm.swappiness = 10
EOF

    cat << 'EOF' > "${tmp_dir}/99-olivier.conf"
# optimisations
vm.vfs_cache_pressure = 100
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.dirty_background_ratio = 2
vm.dirty_ratio = 3
vm.dirty_bytes = 335544320
vm.dirty_background_bytes = 167772160
vm.dirty_writeback_centisecs = 1500
net.core.somaxconn = 8192
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
kernel.task_delayacct = 1
kernel.soft_watchdog = 0
kernel.watchdog = 0
kernel.dmesg_restrict = 0
vm.laptop_mode=5
fs.suid_dumpable=0
kernel.core_pattern=|/bin/false

# hardening
dev.tty.ldisc_autoload = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
kernel.core_uses_pid = 1
kernel.ctrl-alt-del = 0
kernel.perf_event_paranoid = 4
kernel.randomize_va_space = 2
kernel.sysrq = 16
kernel.unprivileged_bpf_disabled = 1
kernel.yama.ptrace_scope = 3
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.bootp_relay = 0
net.ipv4.conf.all.forwarding = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.lo.log_martians = 1
net.ipv4.conf.default.forwarding = 0
net.ipv4.conf.all.proxy_arp = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.ip_forward = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
#net.ipv4.conf.wlp2s0.log_martians = 1
net.ipv4.conf.default.rp_filter = 1
EOF
    _PASS
    _RUN "Déploiement config sysctl" sudo bash -c "
        mkdir -p /etc/sysctl.d &&
        install -m 644 -o root -g root '${tmp_dir}/99-swap.conf' /etc/sysctl.d/ &&
        install -m 644 -o root -g root '${tmp_dir}/99-olivier.conf' /etc/sysctl.d/
    "
    _RUN "Application des paramètres sysctl" bash -c "sudo sysctl -p /etc/sysctl.d/99-*.conf"


    # --- 5. Optimisations Fstab (noatime, lazytime) ---
    local fstab_changed=false
    true > "${tmp_dir}/fstab.new"

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

            if [[ "${orig_opts}" != "${opts}" ]]; then
                fstab_changed=true
                printf "%-40s %-24s %-8s %-32s %-2s %s\n" "${dev}" "${mp}" "${fs}" "${opts}" "${dump}" "${pass}" >> "${tmp_dir}/fstab.new"
                continue
            fi
        fi

        echo "${line}" >> "${tmp_dir}/fstab.new"
    done < /etc/fstab

    if [[ "${fstab_changed}" == "true" ]]; then
        _PASS
        if [[ ! -f /etc/fstab.origin ]]; then
            _RUN "Sauvegarde originale de /etc/fstab" sudo cp -a /etc/fstab /etc/fstab.origin
        fi
        _RUN "Sauvegarde de travail dans /etc/fstab.bak" sudo cp -a /etc/fstab /etc/fstab.bak
        _RUN "Application de noatime/lazytime dans /etc/fstab" sudo cp -a "${tmp_dir}/fstab.new" /etc/fstab
        _RUN "Rechargement du démon systemd" sudo systemctl daemon-reload
    else
        _OK "Les options noatime/lazytime sont déjà présentes dans /etc/fstab."
    fi


    # --- 6. Configuration Brave Browser (Policies debloat) ---
    cat << 'EOF' > "${tmp_dir}/brave_debullshitinator-policies.json"
{
    "BraveRewardsDisabled": true,
    "BraveWalletDisabled": true,
    "BraveVPNDisabled": 1,
    "BraveAIChatEnabled": false,
    "TorDisabled": true,
    "PasswordManagerEnabled": false,
    "DnsOverHttpsMode": "automatic"
}
EOF

    if [[ -f /etc/brave/policies/managed/brave_debullshitinator-policies.json ]] && cmp -s "${tmp_dir}/brave_debullshitinator-policies.json" /etc/brave/policies/managed/brave_debullshitinator-policies.json; then
        _OK "Policies Debloat pour Brave déjà à jour."
    else
        _PASS
        _RUN "Déploiement des policies Brave pour debloat" sudo bash -c "
            mkdir -p /etc/brave/policies/managed &&
            install -m 644 -o root -g root '${tmp_dir}/brave_debullshitinator-policies.json' /etc/brave/policies/managed/
        "
    fi

    # --- 7. Configuration Chrony (IPv4 only) ---
    cat << 'EOF' > "${tmp_dir}/chronyd"
# Command-line options for chronyd
OPTIONS="-F 2 -4"
EOF

    if [[ -f /etc/sysconfig/chronyd ]] && cmp -s "${tmp_dir}/chronyd" /etc/sysconfig/chronyd; then
        _OK "Configuration chronyd déjà à jour (-F 2 -4)."
    else
        _PASS
        _RUN "Application de la configuration chronyd" sudo install -m 644 -o root -g root "${tmp_dir}/chronyd" /etc/sysconfig/chronyd
        _RUN "Redémarrage du service chronyd" sudo systemctl try-restart chronyd
    fi

     # --- 8. Groupe libvirt ---
    local main_user
    main_user=$(getent passwd 1000 | cut -d: -f1 || true)

    if [[ -n "${main_user}" ]]; then
        if getent group libvirt >/dev/null 2>&1; then
            if id -nG "${main_user}" | grep -qw "libvirt"; then
                _OK "L'utilisateur ${main_user} est déjà dans le groupe libvirt."
            else
                _PASS
                _RUN "Ajout de l'utilisateur ${main_user} au groupe libvirt" sudo usermod -aG libvirt "${main_user}"
            fi
        else
            _INFO "Le groupe libvirt n'existe pas. Ajout ignoré."
        fi
    else
        _INFO "Aucun utilisateur avec l'UID 1000 trouvé."
    fi

    # --- 9. sudo/sudo-rs --- => remplacé par SETUP_SUDO_RS

    # --- 10. profile-sync-daemon ---

    # --- 11. services systemd ---
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

    # --- 12. dnf.conf ---
    cat << 'EOF' > "${tmp_dir}/dnf.conf"
# see `man dnf.conf` for defaults and possible options

[main]
defaultyes = true
max_parallel_downloads = 10
EOF

    if [[ -f /etc/dnf/dnf.conf ]] && cmp -s "${tmp_dir}/dnf.conf" /etc/dnf/dnf.conf; then
        _OK "Configuration DNF déjà à jour."
    else
        _PASS
        _RUN "Déploiement de la configuration de DNF" sudo bash -c "mkdir -p /etc/dnf && install -m 644 -o root -g root '${tmp_dir}/dnf.conf' /etc/dnf/"
    fi

    # --- 13. NFS mount ---


    # Nettoyage
    rm -rf "${tmp_dir}"
}

# ─── 12. Configuration Firewalld ---------──────────────────────────────────────
SETUP_FIREWALL() {
    _SECTION "Configuration du Pare-feu (Firewalld)"

    # 1. Vérification de l'installation du paquet
    if ! rpm -q firewalld >/dev/null 2>&1; then
        _RUN "Installation de firewalld" sudo dnf install -y firewalld
    fi

    # 2. Vérification et activation du service
    if ! systemctl is-active --quiet firewalld; then
        _RUN "Démarrage et activation du service firewalld" sudo systemctl enable --now firewalld.service
    else
        _INFO "Le service firewalld est déjà actif."
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

# ─── 13. Configuration sudo-rs ─────────────────────────────────────────────────
SETUP_SUDO_RS() {
    _SECTION "Configuration sudo-rs et remplacement radical de sudo"

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
    _RUN "Configuration des includedir dans ${f_sudoers_rs}" sudo bash -c "
        sed -i -E 's~^(@|#)includedir[[:space:]]+/etc/sudoers\.d~@includedir /etc/sudoers-rs.d~g' '${f_sudoers_rs}'

        if ! grep -qE '^(@|#)includedir[[:space:]]+/etc/sudoers-rs\.d' '${f_sudoers_rs}'; then
            echo -e '\n@includedir /etc/sudoers-rs.d' >> '${f_sudoers_rs}'
        fi

        if ! grep -qE '^(@|#)includedir[[:space:]]+/etc/sudoers\.d' '${f_sudoers_rs}'; then
            echo -e '# Fallback pour les paquets Fedora\n@includedir /etc/sudoers.d' >> '${f_sudoers_rs}'
        fi
    "

    # 4. Remplacement du binaire sudo (La BASCULE CRITIQUE)
    local sys_sudo="/usr/bin/sudo"
    local sys_sudo_bak="/usr/bin/sudo.bak"
    local sudo_rs_bin="/usr/bin/sudo-rs"
    local local_bin_sudo="/usr/local/bin/sudo"

    local current_link=""
    if [[ -L "${sys_sudo}" ]]; then
        current_link=$(readlink "${sys_sudo}" || true)
    fi

    _PASS
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
    _RUN "Symlink prioritaire /usr/local/bin/sudo -> sudo-rs" sudo ln -sf "${sudo_rs_bin}" "${local_bin_sudo}"
    _RUN "Fixation des permissions SUID sur sudo-rs" sudo chmod 4111 "${sudo_rs_bin}"

    # 5. Déploiement de tes règles spécifiques
    _RUN "Règle PSD (90-profile-sync-daemon)" sudo bash -c "echo '%wheel ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper' > '${d_sudoers_rs_d}/90-profile-sync-daemon'"
    _RUN "Règles globales (99-olivier)" sudo bash -c "echo 'Defaults pwfeedback,timestamp_timeout=60' > '${d_sudoers_rs_d}/99-olivier'"

    _RUN "Permissions sur ${f_sudoers_rs}" sudo chmod 0440 "${f_sudoers_rs}"
    _RUN "Permissions sur ${d_sudoers_rs_d}" sudo chmod 0750 "${d_sudoers_rs_d}"
    _RUN "Permissions sur les fichiers de règles" sudo chmod 0440 "${d_sudoers_rs_d}/99-olivier" "${d_sudoers_rs_d}/90-profile-sync-daemon"

    # 6. Nettoyage radical des anciens fichiers
    if [[ -f "/etc/sudoers" && ! -L "/etc/sudoers" ]]; then
        _RUN "Désactivation de /etc/sudoers (renommé en .bak)" sudo mv -f /etc/sudoers /etc/sudoers.bak
    fi

    if [[ -d "/etc/sudoers.d" ]]; then
        _RUN "Nettoyage du contenu de /etc/sudoers.d" sudo bash -c 'rm -f /etc/sudoers.d/*'
    else
        _RUN "Création du dossier de compatibilité /etc/sudoers.d" sudo mkdir -p /etc/sudoers.d
        _RUN "Permissions sur le dossier de compatibilité" sudo chmod 0750 /etc/sudoers.d
    fi

    # 7. Blocage propre des futures mises à jour du vieux sudo par DNF
    local dnf_conf="/etc/dnf/dnf.conf"
    if grep -q '^excludepkgs=' "${dnf_conf}"; then
        if ! grep -Eq '^excludepkgs=.*(^|[ ,])sudo([ ,]|$)' "${dnf_conf}"; then
            _RUN "Exclusion de sudo dans DNF (ajout propre)" \
                sudo sed -i '/^excludepkgs=/ s/$/,sudo/' "${dnf_conf}"
        else
            _OK "sudo est déjà exclu proprement dans ${dnf_conf}."
        fi
    else
        _RUN "Exclusion de sudo dans DNF (nouvelle ligne)" \
            sudo bash -c "printf '\nexcludepkgs=sudo\n' >> '${dnf_conf}'"
    fi

    _OK "sudo-rs est définitivement en place."
}

# ─── 14. Customisation KDE Plasma ──────────────────────────────────────────────
CUSTOMIZE_KDE_PLASMA() {
    _SECTION "Personnalisation de KDE Plasma 6 (Thèmes & Layout)"

    # 1. Base Dark
    _RUN "Passage en mode Dark global" plasma-apply-lookandfeel -a org.kde.breezedark.desktop

    # 2. Color Scheme : Tokyo Night (Mise à jour sécurisée systématique)
    local color_dir="${HOME}/.local/share/color-schemes"
    local color_file="${color_dir}/TokyoNight.colors"
    local tokyo_url="https://raw.githubusercontent.com/Jayy-Dev/Plasma-Tokyo-Night/plasma-6/colorscheme/TokyoNight.colors"

    mkdir -p "${color_dir}"

    # -fsL garantit qu'on ne crée pas de fichier corrompu en cas de 404
    _RUN "Téléchargement de TokyoNight.colors" curl -fsL "${tokyo_url}" -o "${color_file}"

    if [[ ! -s "${color_file}" ]]; then
        _ERR "Le fichier téléchargé est introuvable ou vide. Faudra appliquer le schéma de couleurs manuellement..."
    else
        # Détection du nom exact par Plasma (extraction propre du premier mot)
        local scheme=""
        if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
            scheme="$(plasma-apply-colorscheme --list-schemes 2>/dev/null | grep -i 'tokyonight' | awk '{print $2}' | head -n1 || true)"
        fi

        [[ -n "${scheme}" ]] || _ERR "Tokyo Night non détecté par KDE Plasma ! Faudra appliquer manuellement..."

        _RUN "Application du color scheme ${scheme}" plasma-apply-colorscheme "${scheme}"
        kwriteconfig6 --file kdeglobals --group General --key ColorScheme "${scheme}"
    fi

    # 3. Icônes : Tela Dark
    local temp_tela
    temp_tela=$(mktemp -d)
    _RUN "Clonage des icônes Tela Dark" git clone --quiet https://github.com/vinceliuice/Tela-icon-theme.git "${temp_tela}/tela"
    _RUN "Installation des icônes Tela Dark" bash "${temp_tela}/tela/install.sh" -d "${HOME}/.local/share/icons"
    kwriteconfig6 --file kdeglobals --group Icons --key Theme "Tela-dark"
    rm -rf "${temp_tela}"

    # 4. Curseur : Bibata Lavender (via Catppuccin Mocha)
    mkdir -p "${HOME}/.local/share/icons"
    local temp_cursor
    temp_cursor=$(mktemp -d)
    _RUN "Téléchargement du curseur Bibata Lavender" curl -fsL "https://github.com/catppuccin/cursors/releases/latest/download/catppuccin-mocha-lavender-cursors.zip" -o "${temp_cursor}/cursor.zip"
    _RUN "Extraction du curseur" unzip -q -o "${temp_cursor}/cursor.zip" -d "${HOME}/.local/share/icons/"
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "catppuccin-mocha-lavender-cursors"

    # Pointeur par défaut pour compatibilité GTK
    mkdir -p "${HOME}/.local/share/icons/default"
    echo -e "[Icon Theme]\nInherits=catppuccin-mocha-lavender-cursors" > "${HOME}/.local/share/icons/default/index.theme"
    _OK "Curseur de secours (GTK fallback) configuré dans ~/.local/share/icons/default."

    # Baloo
    if command -v balooctl6 >/dev/null 2>&1; then
        _RUN "Désactivation du service d'indexation de KDE Plasma (baloo)" bash -c "balooctl6 suspend ; balooctl6 disable ; balooctl6 purge"
        _OK "Le service baloo est désactivé et sa base de données a été supprimée."
    else
        _INFO "L'outil balooctl n'est pas installé. Aucune action requise."
    fi

    # déplacement du panneau principal vers le haut
    if ! pgrep plasmashell > /dev/null 2>&1; then
        _INFO "plasmashell ne tourne pas. Configuration du layout reportée."
        return 0
    fi
    plasma_eval() {
        local script="$1"
        busctl --user call org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell evaluateScript s "${script}"
    }
    _RUN "Déplacement du panneau vers le haut" plasma_eval "
        var allPanels = panels();
        for (var i = 0; i < allPanels.length; i++) {
            if (allPanels[i].location === 'bottom') {
                allPanels[i].location = 'top';
            }
        }
    "
    _RUN "Redémarrage de l'interface Plasma" systemctl --user restart plasma-plasmashell.service

    # 5. Rafraîchissement optionnel si session graphique active
    if pgrep plasmashell > /dev/null 2>&1; then
        _RUN "Redémarrage de plasmashell" systemctl --user restart plasma-plasmashell.service
    fi

    _OK "Personnalisation KDE (TokyoNight, Tela, Bibata, Panneau) terminée."
}

# ─── 15. Plasma-login-manager à la place de SDDM ───────────────────────────────
REPLACE_SDDM_WITH_PLM() {
    _SECTION "Préparation de Plasma Login Manager"

    if ! rpm -q plasma-login-manager >/dev/null 2>&1; then
        _RUN "Installation de plasma-login-manager" sudo dnf install -y plasma-login-manager kcm-plasmalogin
    else
        _OK "plasma-login-manager déjà installé."
    fi

    if systemctl is-enabled --quiet sddm.service 2>/dev/null; then
        _RUN "Désactivation de SDDM pour le prochain boot" sudo systemctl disable sddm.service
    else
        _INFO "SDDM déjà désactivé."
    fi

    if systemctl is-enabled --quiet plasmalogin.service 2>/dev/null; then
        _OK "plasmalogin.service déjà activé."
    else
        _RUN "Activation de Plasma Login Manager pour le prochain boot" sudo systemctl enable --force plasmalogin.service
    fi

}


# ─── 16. Flatpak ───────────────────────────────────────────────────────────────
INSTALL_FLATPAK_PACKAGES() {
    _SECTION "Configuration/Installation de Flatpak"

    # 1. Vérification et installation de Flatpak
    if ! command -v flatpak >/dev/null 2>&1; then
        _RUN "Installation de Flatpak" sudo dnf install -y flatpak
    else
        _OK "Flatpak est déjà installé."
    fi

    # 2. Ajout de Flathub s'il n'existe pas
    _RUN "Ajout du dépôt Flathub" sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

    # 3. Activation de Flathub sans filtre
    _RUN "Activation complète de Flathub" sudo flatpak remote-modify --no-filter --enable flathub

    # 4. Vérification et suppression du dépôt Fedora
    if flatpak remotes --columns=name | grep -q "^fedora$"; then
        _RUN "Suppression du dépôt Fedora Flatpak" sudo flatpak remote-delete --force fedora
    else
        _OK "Le dépôt Fedora Flatpak n'est pas présent."
    fi

    # 5. Installation des paquets depuis Flathub (System-wide par défaut avec sudo)
    if [[ ${#FLATPAK_PKGS[@]} -gt 0 ]]; then
        for pkg in "${FLATPAK_PKGS[@]}"; do
            if flatpak info "${pkg}" >/dev/null 2>&1; then
                _OK "Flatpak '${pkg}' est déjà installé."
            else
                _RUN "Installation de ${pkg}" sudo flatpak install -y flathub "${pkg}"
            fi
        done
    else
        _INFO "Aucun paquet Flatpak à installer."
    fi

    # 6. Configuration des thèmes pour les applications Flatpak (Mode global/system-wide overrides)
    _RUN "Application du thème (Tokyo Night, Tela, Bibata) aux Flatpaks" \
    sudo flatpak override \
        --filesystem="${HOME}/.local/share/icons:ro" \
        --filesystem="${HOME}/.local/share/themes:ro" \
        --filesystem="${HOME}/.icons:ro" \
        --filesystem="xdg-config/gtk-3.0:ro" \
        --filesystem="xdg-config/gtk-4.0:ro" \
        --env="GTK_THEME=TokyoNight" \
        --env="ICON_THEME=Tela-dark" \
        --env="XCURSOR_THEME=catppuccin-mocha-lavender-cursors"

    # 7. Petit nettoyage des runtimes inutilisés
    _RUN "Nettoyage des runtimes Flatpak orphelins" sudo flatpak uninstall --unused -y
}

##########################################################################################################################
##########################################################################################################################
##########################################################################################################################
# appel principal
##########################################################################################################################
##########################################################################################################################
##########################################################################################################################

MAIN "$@"

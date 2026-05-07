#!/usr/bin/env bash
# TODO sshd : email quand conn. / fail2ban
#      cachyos kernel
# shellcheck disable=SC2310
set -euo pipefail
trap '_CLEANUP' ERR
trap '_INTERRUPT' INT
readonly SCRIPTNAME="${0##*/}"
readonly VER=32.8
# paramètres customisables définis dans settings.sh. ###############################
source ./settings.sh                                                               #
####################################################################################

# ─── MAIN ────────────────────────────────────────────────────────────────────────────────────────────────────────────
MAIN() {
    args=${1:-}
    source ./helpers.sh
    _ENABLE_COLORS
    CHECK
    INITIALIZE
    if [[ "${args}" = "--shellonly" ]] || [[ "${args}" = "-s" ]]; then
        SHELLONLYMODE
    elif [[ "${args}" = "--check" ]] || [[ "${args}" = "-c" ]]; then
        CHECKMODE
    elif [[ "${args}" = "--help" ]] || [[ "${args}" = "-h" ]]; then
        HELPMODE
    else
        MAINMODE
    fi
    END
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

########################################################################################################################
# FONCTIONS DISTRO-AGNOSTIQUE                                                                                          #
########################################################################################################################
MAINMODE() {
    _REFRESH_SYS_CACHE
    _RUN "Mise à jour forcée du système" _SYS_UPDATE
    SETUP_SUDO_RS
    # remove/install
    REMOVE_RPM_PACKAGES
    INSTALL_REPOS
    INSTALL_RPM_PACKAGES
    INSTALL_FONTS
    INSTALL_CODECS
    INSTALL_CARGO_PACKAGES
    INSTALL_GO_PACKAGES
    INSTALL_FLATPAK_PACKAGES
    INSTALL_GIT_REPOS
    # config
    SETUP_SHELL
    SETUP_DOTFILES
    SETUP_ETC
    SETUP_SYSTEMD
    SETUP_FIREWALL
    SETUP_SWAP
    SETUP_SSHD
    SETUP_FSTAB
    SETUP_GRUB
    SETUP_KDE_PLASMA
    SETUP_PLM
    SETUP_DATA
}

########################################################################################################################
SHELLONLYMODE() {
    _SECTION " Mode shellonly (cargo, go, git, shell, dotfiles) " "━" "${C_GREEN}"
    INSTALL_CARGO_PACKAGES
    INSTALL_GO_PACKAGES
    INSTALL_GIT_REPOS
    SETUP_SHELL
    SETUP_DOTFILES
}

########################################################################################################################
CHECKMODE() {
    _SECTION " Mode contrôle - paramètres personnalisables de ${SCRIPTNAME} " "━" "${C_GREEN}"
    echo "Fichier : "
    ls -l ./settings.sh 2>/dev/null
    echo ""
    echo "Contenu : "
    if _EXIST bat; then
        grep -E -v '^(#.*shellcheck disable|\s*#.*shellcheck disable|\s*$)' ./settings.sh | bat -pP
    else
        grep -E -v '^(#.*shellcheck disable|\s*#.*shellcheck disable|\s*$)' ./settings.sh
    fi
    echo ""
    _RUNSILENT "" sudo rm -f "${SUDOTMP[@]}"
    exit 0
}

########################################################################################################################
HELPMODE() {
    _SECTION " Mode aide " "━" "${C_GREEN}"
    _INFO "Usage : ./${SCRIPTNAME} [ --shellonly | --check | --help ]"
    _INFO "Sans option, ${SCRIPTNAME} éxécute la post-installation complète."
    _INFO "Les paramètres personnalisables sont stockés dans ./settings.sh."
    _RUNSILENT "" sudo rm -f "${SUDOTMP[@]}"
    exit 0
}

########################################################################################################################
INITIALIZE() {
    local heure
    heure=$(date '+%T')
    local logsuffix
    START=${SECONDS}
    _PASS
    LOG_DIR="${HOME}/.local/log"
    logsuffix="$(date +%Y%m%d-%H%M%S)"
    LOG_FILE="${LOG_DIR}/post-install-fedora-${logsuffix}.log"
    INSTALL_DIR="${HOME}/.local/bin"
    export LOG_DIR LOG_FILE INSTALL_DIR
    mkdir -p "${LOG_DIR}"
    touch "${LOG_FILE}"

    clear
    source /etc/os-release
    _BANNER "blue" "${SCRIPTNAME} (${VER})"
    _SECTION " Préparation de la post-installation " "━" "${C_GREEN}"
    _INFO "Distribution : ${PRETTY_NAME}"
    _INFO "Heure de démarrage du script : ${heure}"
    _OK "Fichier log de la post-installation : ${LOG_FILE}"
    printf '%s' "Paramètres utilisateur retenus : " >>"${LOG_FILE}"
    grep -E -v '^(#.*shellcheck disable|\s*#.*shellcheck disable|\s*$)' ./settings.sh >>"${LOG_FILE}"

    INSTALL_DEPS

    # RUST
    export RUSTUP_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/rustup"
    export CARGO_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/cargo"
    # GO
    export GOPATH="${XDG_DATA_HOME:-${HOME}/.local/share}/go"
    export GOBIN="${XDG_BIN_HOME:-${HOME}/.local/bin}"

    # Dossiers utilisateur requis
    _RUNSILENT "" mkdir -pv "${INSTALL_DIR}" "${RUSTUP_HOME}" "${CARGO_HOME}" "${GOPATH}" "${GOBIN}" "${HOME}/.local/share/zsh" "${HOME}/.local/share/icons/default" "${HOME}/.local/share/color-schemes" "${HOME}/.local/share/themes"
    # Dossiers système requis
    _RUNSILENT "" sudo mkdir -pv /usr/local/bin /etc/sudoers.d /etc/udev/rules.d /etc/NetworkManager/conf.d /etc/systemd/resolved.conf.d /etc/sysctl.d/ /etc/brave/policies/managed/

    # Préparation d'une session sudo confortable et longue pour l'installation
    local sudotmp
    declare -ga SUDOTMP=()
    sudotmp="/etc/sudoers.d/99_POST-INSTALL"
    SUDOTMP=(/etc/sudoers-rs.d/99_POST-INSTALL /etc/sudoers.d/99_POST-INSTALL) # pour delete à la fin et en cas de plantage
    _RUNSILENT "" bash -c "echo 'Defaults pwfeedback,timestamp_timeout=180' | sudo tee '${sudotmp}'"
    _RUNSILENT "" sudo chmod -v 0440 "${sudotmp}"

    # aussitôt je conf le package manager si besoin pour accélérer les download de paquets
    _PKG_CONFIG

    # PATH
    export PATH="${GOBIN}:${CARGO_HOME}/bin:${INSTALL_DIR}:${PATH}"
    #

    # liste des fichiers système crées ou modifiés par le script
    declare -a ETC_FILES=()
}

########################################################################################################################
INSTALL_CARGO_PACKAGES() {
    if [[ -n "${CARGO_PACKAGES[*]}" ]]; then
        _SECTION " Installation des paquets Cargo personnalisés " "━" "${C_GREEN}"

        # 0. toolchain rust
        local check
        if _EXIST rustup; then
            check=$(rustup check 2>/dev/null)
            if echo "${check}" | grep -q "update available"; then
                version=$(echo "${check}" | awk -F ":" '{print $2}' | xargs)
                _RUN "Mise à jour de la toolchain RUST (${version})" rustup update stable
            else
                _LOG "la toolchain rust est à jour"
            fi
        else
            _RUN "Installation de la toolchain RUST" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --default-toolchain stable'
        fi

        # 1. Installation de cargo-binstall sans compilation
        if ! _EXIST cargo-binstall; then
            _RUN "Installation de cargo-binstall (installation de paquets binaires)" bash -c "curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash"
        else
            _LOG "cargo-binstall (installation de paquets binaires) est déjà installé"
        fi
        _RUNSILENT "" _SYMLINK "${CARGO_HOME}/bin/cargo-binstall" "/usr/local/bin/cargo-binstall"

        # 2. Installation des paquets via Cargo (binstall)
        declare -g INSTALLED_LIST
        _RUN "Listing des paquets cargo" bash -c "cargo install --list 2>/dev/null > /tmp/cargolist"
        INSTALLED_LIST="$(cat /tmp/cargolist 2>/dev/null || true)" # je passe par un fichier /tmp/cargolist pour avoir un spinner
        export INSTALLED_LIST # variable utilisée par _CARGOPKG_INSTALL
        _MANAGE_TABLE _IS_CARGOPKG_INSTALLED _CARGOPKG_INSTALL "${CARGO_PACKAGES[@]}"
        rm -f /tmp/cargolist 2>/dev/null

        # 3. symlinks globaux
        local cmd
        for cmd in "${CARGO_PACKAGES[@]}"; do
            local bins_to_link bin_name
            bins_to_link="${BIN_MAPPING[${cmd}]:-${cmd}}"
            for bin_name in ${bins_to_link}; do
                _RUNSILENT "" _SYMLINK "${CARGO_HOME}/bin/${bin_name}" "/usr/local/bin/${bin_name}"
            done
        done

        # 4. Ajustement des permissions pour l'accès global
        _RUNSILENT "" chmod a+x -v "${HOME}" "${HOME}/.local" "${HOME}/.local/share" "${CARGO_HOME}" "${CARGO_HOME}/bin"
    else
        _LOG "Aucun paquets cargo demandés"
    fi
}

########################################################################################################################
INSTALL_GO_PACKAGES() {
    if [[ -n "${GO_PACKAGES[*]}" ]]; then
        _SECTION " Installation des paquets GO personnalisés " "━" "${C_GREEN}"

        local pkg current="" latest="" arch="" os="" gofile=""

        if [[ ! "${PATH}" =~ "/usr/local/go/bin" ]]; then
            export PATH="/usr/local/go/bin:${PATH}"
        fi
        if _EXIST go; then
            current="$(go version | awk '{print $3}' || true)"
        fi
        latest="$(curl -fsSL https://go.dev/dl/?mode=json | jq -r '.[0].version' || true)"
        arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/' || true)
        os=$(uname | tr '[:upper:]' '[:lower:]' || true)
        gofile="${latest}.${os}-${arch}.tar.gz"

        if [[ "${current}" == "${latest}" ]] && _EXIST go; then
            _LOG "la toolchain GO est à jour (${latest})"
        else
            _RUNSILENT "" curl -LO "https://go.dev/dl/${gofile}"
            _RUNSILENT "" sudo rm -rvf /usr/local/go
            _RUN "Installation de la toolchain GO (${latest})" sudo tar -C /usr/local -xzf "${gofile}"
            _RUNSILENT "" rm -vf "${gofile}"
        fi

        if _EXIST go; then
            local -a missing=()
            local -a missingbin=()
            local -a present=()
            for pkg in "${!GO_PACKAGES[@]}"; do
                local url
                url="${GO_PACKAGES[${pkg}]}"
                if _EXIST "${pkg}"; then
                    present+=("${url}")
                else
                    missing+=("${url}")
                    missingbin+=("${pkg}")
                fi
            done
            if [[ -z "${missing[*]}" ]]; then
                local present_fmt
                present_fmt=$(_FORMAT_LIST "${present[@]}")
                _INFO "Tout a été traité (installation) : "
                _PRINT_LIST "${present_fmt}" | tee -a "${LOG_FILE}"
            else
                if [[ -n "${present[*]}" ]]; then
                    local present_fmt
                    present_fmt=$(_FORMAT_LIST "${present[@]}")
                    _INFO "Déjà installé : "
                    _PRINT_LIST "${present_fmt}" | tee -a "${LOG_FILE}" || true
                fi
            fi
            for pkg in "${missing[@]}"; do
                _RUN "Installation de ${pkg}" go install "${pkg}"
            done
            for pkg in "${missingbin[@]}"; do
                _RUNSILENT "" _SYMLINK "${GOBIN}/${pkg}" "/usr/local/bin/${pkg}"
            done
        fi
    else
        _LOG "Aucun paquets GO demandés"
    fi
}

########################################################################################################################
INSTALL_GIT_REPOS() {
    local repo name target
    _RUNSILENT "" mkdir -pv "${HOME}/git"
    _SECTION " Installation des dépôts Git personnalisés " "━" "${C_GREEN}"

    for repo in "${GIT_REPOS[@]}" "${DOTFILES_REPO}"; do
        name="${repo##*/}"
        target="${HOME}/git/${name}"

        if [[ -d "${target}" ]]; then
            if git -C "${target}" rev-parse --git-dir &>/dev/null; then
                if [[ "${UPDATE_GIT_REPOS}" = "yes" ]]; then
                    _RUN "Mise à jour de ${name}" git -C "${target}" pull --ff-only
                else
                    _INFO "${name} déjà présent et pas de mise à jour demandée"
                fi
            else
                _ERR "${target} existe mais n'est pas un dépôt git, ignoré"
            fi
        else
            _RUN "Téléchargement de ${name}" git clone "${repo}" "${target}"
        fi

        if [[ "${repo}" == "${DOTFILES_REPO}" && "${target}" != "${DOTFILES_DIR}" ]]; then
            _RUNSILENT "" _SYMLINK "${target}" "${DOTFILES_DIR}"
        fi
    done
}

########################################################################################################################
SETUP_SHELL() {
    _SECTION " Configuration du shell zsh par défaut " "━" "${C_GREEN}"
    # 1- zsh
    local zsh_bin
    _EXIST zsh || _RUNSILENT "" _PKG_INSTALL zsh
    zsh_bin=$(command -v zsh)

    if ! grep -qxF "${zsh_bin}" /etc/shells; then
        echo "${zsh_bin}" | sudo tee -a /etc/shells >/dev/null
    fi

    local user uid current_shell
    while IFS=: read -r user _ uid _ _ _ _; do                                    # on parcourt le fichier /etc/passwd pour récupérer user et uid.
        if [[ ("${uid}" -ge 1000 && "${uid}" -lt 5000) || "${uid}" -eq 0 ]]; then # root et users normaux
            current_shell=$(getent passwd "${user}" | cut -d: -f7)
            if [[ "${current_shell}" != "${zsh_bin}" ]]; then
                _RUN "Shell zsh pour ${user}" sudo chsh -s "${zsh_bin}" "${user}"
                _ETC_FILES_ADD "/etc/passwd"
            else
                _INFO "${user} a déjà zsh par défaut"
            fi
        fi
    done </etc/passwd

    # 2- Oh-my-posh prompt
    if [[ ${USE_OH_MY_POSH_PROMPT,,} = "yes" ]]; then
        local arch omp_target="" no_ohmyposh=0
        arch=$(uname -m)

        case "${arch}" in
        x86_64 | amd64)
            omp_target="posh-linux-amd64"
            ;;
        aarch64 | arm64)
            omp_target="posh-linux-arm64"
            ;;
        armv7l)
            omp_target="posh-linux-arm"
            ;;
        *)
            _ERR "Architecture non supportée pour Oh My Posh : ${arch}"
            no_ohmyposh=1
            ;;
        esac

        if [[ "${no_ohmyposh}" = 0 ]]; then
            local omp_url="https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/${omp_target}"
            local omp_bin="${INSTALL_DIR}/oh-my-posh"
            if _EXIST oh-my-posh; then
                local check
                check=$(oh-my-posh notice)
                if [[ -z "${check}" ]]; then
                    _LOG "aucune mise à jour de oh-my-posh dispo"
                else
                    _RUN "Mise à jour de Oh-My-Posh" oh-my-posh upgrade
                fi
            else
                _RUN "Téléchargement du binaire Oh-My-Posh (${omp_target})" curl -fsSL "${omp_url}" -o "${omp_bin}"
                _RUNSILENT "" chmod 777 -v "${omp_bin}"
            fi
        fi
    fi
    _INSTALL_USER_CRONTAB
}

########################################################################################################################
SETUP_DOTFILES() {
    _SECTION " Installation des configurations personnalisées de ${USER} (dotfiles) " "━" "${C_GREEN}"

    if [[ ! -d "${DOTFILES_DIR}" ]]; then
        _ERR "Le dossier ${DOTFILES_DIR} est introuvable. Stow ignoré."
        return
    fi

    # 1- nettoyage avant stow pour éviter erreurs.
    local skel_files=(".bashrc" ".bash_logout" ".zshenv" ".zshrc" ".config/plasma-org.kde.plasma.desktop-appletsrc" ".config/kactivitymanagerd-statsrc" ".config/kglobalshortcutsrc" ".config/konsolerc" ".config/user-dirs.dirs" ".config/user-dirs.locale")
    local file
    mkdir -p "${HOME}/backup"
    for file in "${skel_files[@]}"; do
        if [[ -f "${HOME}/${file}" && ! -L "${HOME}/${file}" ]]; then
            _LOG "déplacement de fichiers qui seront remplacés par le dotfiles via stow dans ~/backup : "
            _RUNSILENT "" mv -v "${HOME}/${file}" "${HOME}/backup/"
        fi
    done

    # 2- stow pour déployer dotfiles depuis dépôt git
    local pkg name listdot=" " displayed_stow
    [[ "${RESTOW}" = "yes" ]] && displayed_stow="Forçage des liens symboliques (restow)" || displayed_stow="Vérification des liens symboliques, création si besoin (stow)"

    echo -e " ${C_GREEN}✓ ${C_RESET} ${displayed_stow} :"
    for pkg in "${DOTFILES_DIR}"/*/; do
        name=$(basename "${pkg}")
        listdot="${listdot}${name} "
    done
    _PRINT_LIST "${listdot}" | tee -a "${LOG_FILE}"
    for pkg in "${DOTFILES_DIR}"/*/; do
        name=$(basename "${pkg}")
        if [[ "${RESTOW}" = "yes" ]]; then
            stow -v1 --dir="${DOTFILES_DIR}" --target="${HOME}" --restow "${name}" &>>"${LOG_FILE}"
        else
            stow -v1 --dir="${DOTFILES_DIR}" --target="${HOME}" "${name}" &>>"${LOG_FILE}"
        fi
    done

    if _EXIST bat; then
        _LOG "Reconstruction du cache de bat"
        _RUNSILENT "" bash -c "bat cache --clear; bat cache --build"
    fi
    _INFO "Note : dotfiles déployés uniquement pour ${USER}"

}

########################################################################################################################
SETUP_SYSTEMD() {
    _LOG "* systemd *"
    local service
    local description
    local -a missing=()
    local -a present=()

    for service in "${!SERVICES_TO_DISABLE[@]}"; do
        description="${SERVICES_TO_DISABLE[${service}]}"
        if _IS_ENABLED "${service}"; then
            missing+=("${service}")
        else
            present+=("${service}")
        fi
    done

    local missing_fmt present_fmt
    present_fmt=$(_FORMAT_LIST "${present[@]}")
    if ((${#missing[@]})); then
        missing_fmt=$(_FORMAT_LIST "${missing[@]}")
        ((${#present[@]})) && {
            _INFO "Déjà désactivés : "
            _PRINT_LIST "${present_fmt}" | tee -a "${LOG_FILE}" || true
        }
        _INFO "À désactiver : "
        _PRINT_LIST "${missing_fmt}" | tee -a "${LOG_FILE}" || true
        _RUN "Désactivation des services" sudo systemctl disable --now "${missing[@]}"
    else
        _INFO "Services déjà désactivés : "
        _PRINT_LIST "${present_fmt}" | tee -a "${LOG_FILE}" || true
    fi

    for service in "${!USER_SERVICES_TO_ENABLE[@]}"; do
        description="${USER_SERVICES_TO_ENABLE[${service}]}"
        if ! _IS_ENABLED_USER "${service}"; then
            _RUN "Activation du ${description}" systemctl --user enable --now "${service}"
        else
            _INFO "${description^} déjà activé"
        fi
    done
}

########################################################################################################################
SETUP_FSTAB() {
    _SECTION " Configuration du fichier FSTAB " "━" "${C_GREEN}"

    # SWAPFILE
    if [[ "${ZSWAP,,}" = "yes" ]]; then
        local swapdir="/var/swap"
        if ! grep -q "${swapdir}/swapfile" /etc/fstab; then
            if [[ ! -f /etc/fstab.origin ]]; then
                _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.origin
            fi
            _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.bak.swap
            _RUN "Ajout du swap" bash -c "echo ${swapdir}/swapfile none swap sw,nofail 0 0 | sudo tee -a /etc/fstab"
            _ETC_FILES_ADD "/etc/fstab"
        else
            _INFO "Swap déjà présent dans /etc/fstab"
        fi
    else
        _LOG "Pas de zswap demandé on ne fait pas de swapfile."
    fi

    # --- Optimisations Fstab (noatime, lazytime) ---
    local fstab_changed=false tmp_dir
    tmp_dir=$(mktemp -d)
    true >"${tmp_dir}/fstab.new" # on crée un fichier vide temporaire

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^[[:space:]]*# ]] || [[ -z "${line}" ]]; then # commentaire ou ligne vide ajouté "as is"
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
            if [[ ! ",${opts}," =~ ,commit=60, ]] && [[ "${fs}" = "ext4" ]]; then
                opts="${opts},commit=60"
            fi
            if [[ "${orig_opts}" != "${opts}" ]]; then
                fstab_changed=true
                printf "%-40s %-24s %-8s %-32s %-2s %s\n" "${dev}" "${mp}" "${fs}" "${opts}" "${dump}" "${pass}" >>"${tmp_dir}/fstab.new"
                continue
            fi
        fi

        echo "${line}" >>"${tmp_dir}/fstab.new"
    done </etc/fstab

    if [[ "${fstab_changed}" == "true" ]]; then
        _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.bak.optimizations
        _RUN "Optimisations des systèmes de fichier" sudo cp -av "${tmp_dir}/fstab.new" /etc/fstab
        _RUNSILENT "" sudo systemctl daemon-reload
        _ETC_FILES_ADD "/etc/fstab"
    else
        _INFO "Options d'optimisations déjà présentes dans /etc/fstab"
    fi

    # NFS
    if [[ "${NFS_SHARE}" != "" ]]; then
        local opts
        opts="rw,_netdev,nofail,nodev,nosuid,noexec,noatime,lazytime,x-systemd.automount,x-systemd.device-timeout=30"
        if ! grep -q "${NFS_SHARE}" /etc/fstab >/dev/null; then
            if grep -q "${NFS_MP}" /etc/fstab >/dev/null; then
                _INFO "Point de montage demandé (${NFS_MP}) déjà présent dans /etc/fstab :"
                grep "${NFS_MP}" /etc/fstab
                _INFO "Abandon de l'installation du partage réseau NFS."
            else
                _RUNSILENT "" sudo mkdir -pv "${NFS_MP}"
                _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.bak.nfs
                echo "${NFS_SHARE}   ${NFS_MP}   nfs   ${opts}      0 0" | sudo tee -a /etc/fstab >/dev/null
                _ETC_FILES_ADD "/etc/fstab"
                _RUNSILENT "" sudo systemctl daemon-reload
                _RUN "Montage du partage réseau NFS" bash -c "sudo mount -v \"${NFS_MP}\" && sudo ls -l \"${NFS_MP}\""
            fi
        else
            _INFO "Montage NFS déjà OK"
        fi
    else
        _LOG "Aucun montage NFS demandé"
    fi

    # fast_commit pour ext4
    local mounts
    mounts=$(findmnt -rn -t ext4 -o SOURCE,TARGET,FSTYPE)
    while read -r dev mp fs _; do
        [[ "${fs}" != "ext4" ]] && continue
        [[ "${mp}" == "/boot" ]] && continue
        if sudo tune2fs -l "${dev}" 2>/dev/null | grep -q "fast_commit"; then
            _LOG "fast_commit déjà actif sur ${dev} (montée en ${mp})"
        else
            _RUN "Activation flag \"fast_commit\" sur ${dev} (montée en ${mp})" sudo tune2fs -O fast_commit "${dev}"
        fi
    done <<<"${mounts}"

    # Nettoyage
    rm -rf "${tmp_dir}"
}

########################################################################################################################
SETUP_DATA() {
    _SECTION " Restauration des données privées de l'utilisateur ${USER} " "━" "${C_GREEN}"
    if [[ -e "${SOURCE}" ]]; then
        if [[ ${#DESTINATIONS[@]} -gt 0 ]]; then
            local profil file cmd ffile
            for profil in "${!DESTINATIONS[@]}"; do
                cmd=${COMMANDS["${profil}"]}
                # on récupère la sauvegarde la plus récente dans le dossier SOURCE pour le profil ${profil}
                file=$(find "${SOURCE}" -maxdepth 1 -name "${profil}_*.tar.gz" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2- || true)
                if [[ -n "${cmd}" ]] && pgrep -x "${cmd}" >/dev/null; then
                    _ERR "Ferme ${cmd} d'abord !"
                else
                    if [[ -n "${file}" ]]; then
                        if _DIR_IS_SAFE_TO_RESTORE "${DESTINATIONS[${profil}]}"; then
                            ffile=$(basename "${file}")
                            _RUN "Restauration de ${profil} (de ${ffile} vers ${HOME})" tar -xzf "${file}" -C "${HOME}"
                        else
                            _ERR "Le dossier de restauration de ${profil} contient déjà des données, on ne fait rien"
                        fi
                    else
                        _INFO "Aucun fichier de sauvegarde trouvé pour le profil ${profil}"
                    fi
                fi
            done
        else
            echo ""
            _INFO "Aucune données privées à restaurer"
        fi
    else
        _ERR "Dossier de restauration (${SOURCE}) absent"
    fi
}

########################################################################################################################
SETUP_KDE_PLASMA() {
    # on check KDE est lancé
    if pgrep -f '\b(plasmashell|kwin|kwin_wayland|plasma-desktop)\b' >/dev/null; then
        _SECTION " Personnalisation de l'interface KDE Plasma 6 de l'utilisateur ${USER} " "━" "${C_GREEN}"
        local change=0

        # Color Scheme : Tokyo Night
        local color_dir="${HOME}/.local/share/color-schemes"
        local color_file="${color_dir}/TokyoNight.colors"
        local tokyo_url="https://raw.githubusercontent.com/Jayy-Dev/Plasma-Tokyo-Night/plasma-6/colorscheme/TokyoNight.colors"

        # -fsL garantit qu'on ne crée pas de fichier corrompu en cas de 404
        if [[ ! -f "${color_file}" ]]; then
            _RUN "Téléchargement de TokyoNight.colors (dans ${color_dir})" curl -fsL "${tokyo_url}" -o "${color_file}"
            change=1
        fi

        if [[ ! -s "${color_file}" ]]; then
            _ERR "Le fichier téléchargé est introuvable ou vide. Faudra appliquer le schéma de couleurs manuellement..."
        else
            # Détection du nom exact par Plasma (extraction propre du premier mot)
            local tokyoexist="" currentlist="" currentscheme=""
            if _EXIST plasma-apply-colorscheme; then
                currentlist=$(LANG=C plasma-apply-colorscheme --list-schemes 2>/dev/null)
                currentscheme=$(echo "${currentlist}" | grep -i 'current color scheme' | awk '{print $2}' || true)
                tokyoexist=$(echo "${currentlist}" | grep -i 'tokyonight' | awk '{print $2}' | head -n1 || true)

                if [[ -z "${tokyoexist}" ]]; then
                    _ERR "Tokyo Night non détecté par KDE Plasma ! Faudra appliquer manuellement..."
                else
                    if [[ "${tokyoexist}" != "${currentscheme}" ]]; then
                        _RUN "Application de la palette de couleurs ${tokyoexist}" plasma-apply-colorscheme "${tokyoexist}"
                        change=1
                    fi
                fi

            fi
        fi

        # 3. Icônes : Tela
        local temp_tela
        if ! find "${HOME}/.local/share/icons" -maxdepth 1 -type d -name "*Tela*" -print -quit | grep -q . >/dev/null; then
            temp_tela=$(mktemp -d)
            _RUN "Téléchargement des icônes Tela" git clone https://github.com/vinceliuice/Tela-icon-theme.git "${temp_tela}/tela"
            _RUN "Installation des icônes Tela dracula (dans ${HOME}/.local/share/icons/)" bash -c "\"${temp_tela}\"/tela/install.sh -c dracula -d \"${HOME}\"/.local/share/icons"
            _RUNSILENT "" rm -rf "${temp_tela}"
            change=1
        fi

        # 4. Curseur : Bibata Lavender (via Catppuccin Mocha)
        local temp_cursor
        temp_cursor=$(mktemp -d)
        if ! find "${HOME}/.local/share/icons" -maxdepth 1 -type d -name "*catppuccin-mocha-lavender-cursors*" -print -quit | grep -q . >/dev/null; then
            _RUN "Installation du curseur catppuccin-mocha-lavender (dans ${HOME}/.local/share/icons/)" curl -fsL "https://github.com/catppuccin/cursors/releases/latest/download/catppuccin-mocha-lavender-cursors.zip" -o "${temp_cursor}/cursor.zip"
            _RUNSILENT "" unzip -q -o "${temp_cursor}/cursor.zip" -d "${HOME}/.local/share/icons/"
            change=1
        fi

        # Pointeur par défaut pour compatibilité GTK
        if [[ ! -f "${HOME}/.local/share/icons/default/index.theme" ]] || ! grep -q "catppuccin-mocha-lavender-cursors" "${HOME}/.local/share/icons/default/index.theme"; then
            echo -e "[Icon Theme]\nInherits=catppuccin-mocha-lavender-cursors" >"${HOME}/.local/share/icons/default/index.theme"
        fi

        # Baloo
        if _EXIST balooctl6; then
            if balooctl6 status >/dev/null 2>&1; then
                _RUN "Désactivation du service d'indexation de KDE Plasma (baloo)" bash -c "balooctl6 suspend ; balooctl6 disable ; balooctl6 purge"
            else
                _INFO "Service d'indexation déjà désactivé"
            fi
        else
            _INFO "L'outil balooctl n'est pas installé. Aucune action requise"
        fi

        # déplacement du panneau principal
        local target_pos display_pos
        target_pos="${KDEPANEL,,:-bottom}"

        case "${target_pos}" in
        bottom) display_pos="basse" ;;
        top) display_pos="haute" ;;
        right) display_pos="droite" ;;
        left) display_pos="gauche" ;;
        *) display_pos="basse" ;;
        esac

        if ! pgrep plasmashell >/dev/null 2>&1; then
            _INFO "plasmashell n'est pas lancée, déplacement du panneau annulé"
        else
            local current_positions
            current_positions=$(_PLASMA_GET_PANEL_LOCATION)

            if [[ -z "${current_positions}" ]]; then
                _INFO "Aucun panneau détecté"
            elif [[ "${current_positions}" == "${target_pos}" ]]; then
                _INFO "Panneau déjà à la position voulue (${display_pos})"
            else
                _RUN "Déplacement du panneau en position ${display_pos}" _PLASMA_EVAL "
                    var allPanels = panels();
                    for (var i = 0; i < allPanels.length; i++) {
                        allPanels[i].location = \"${target_pos}\";
                    }
                "
                change=1
            fi
        fi
        # Avatar
        local avatar
        avatar="/usr/share/plasma/avatars/photos/Cocktail.png"
        [[ -f /var/lib/AccountsService/icons/"${USER}" ]] || _RUN "Avatar (Cocktail) pour ${USER}" sudo cp -v "${avatar}" /var/lib/AccountsService/icons/"${USER}"

        # on redémarre l'interface pour appliquer de suite.
        if pgrep plasmashell >/dev/null 2>&1; then
            if [[ "${change}" -eq 1 ]]; then
                _RUN "Redémarrage de l'interface de KDE Plasma 6" bash -c "\
                kwriteconfig6 --file kdeglobals --group Icons --key Theme Tela-dracula-dark ;\
                kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme catppuccin-mocha-lavender-cursors ;\
                [[ -n \"${tokyoexist}\" ]] && plasma-apply-colorscheme \"${tokyoexist}\" ;\
                [[ -f \"${HOME}/.local/share/wallpapers/SpacePlasma.jpg\" ]] && plasma-apply-wallpaperimage \"${HOME}/.local/share/wallpapers/SpacePlasma.jpg\" ;\
                kwriteconfig6 --file ksplashrc --group KSplash --key Theme Colourful-Ring-Splashscreen-Plasma6 ;\
                sleep 1 ;\
                systemctl --user restart plasma-plasmashell.service"
            else
                _INFO "Aucune modification de configuration effectuée, pas de redémarrage de KDE Plasma"
            fi
        fi

        # Configuration des thèmes pour les applications Flatpak (Mode global/system-wide overrides)
        if _EXIST flatpak; then
            _RUNSILENT "" sudo flatpak override \
                --filesystem="${HOME}/.local/share/icons:ro" \
                --filesystem="${HOME}/.local/share/themes:ro" \
                --filesystem="xdg-config/gtk-3.0:ro" \
                --filesystem="xdg-config/gtk-4.0:ro" \
                --env="GTK_THEME=TokyoNight" \
                --env="ICON_THEME=Tela-dracula-dark" \
                --env="XCURSOR_THEME=catppuccin-mocha-lavender-cursors"
        fi
    else
        echo
        _INFO "KDE Plasma non détectée, pas de personnalisation"
    fi
}

########################################################################################################################
SETUP_PLM() {
    _LOG "* Login Manager KDE *"
    # on teste si KDE tourne
    local change=0
    if pgrep -f '\b(plasmashell|kwin|kwin_wayland|plasma-desktop)\b' >/dev/null; then
        if ! _EXIST plasmalogin; then
            _RUN "Installation de plasma-login-manager" _PKG_INSTALL plasma-login-manager kcm-plasmalogin
            change=1
        fi

        if _IS_ENABLED sddm.service; then
            _RUN "Désactivation de SDDM à partir du prochain boot" sudo systemctl disable sddm.service
            change=1
        fi

        if ! _IS_ENABLED plasmalogin.service; then
            _RUN "Activation de Plasma Login Manager à partir du prochain boot" sudo systemctl enable --force plasmalogin.service
            change=1
        fi

        if [[ "${change}" = 0 ]]; then
            _INFO "Plasma Login Manager déjà OK"
        fi
        SET_PLM_WALLPAPER
    else
        echo
        _INFO "KDE Plasma non détectée, pas de changement du login-manager"
    fi
}

########################################################################################################################
SETUP_ETC() {
    _SECTION " Configuration générale du système " "━" "${C_GREEN}"
    _MSMTP
    _HOSTNAME
    _JOURNALD
    _NETWORKMANAGER
    _SYSTEMD_RESOLVED
    _KERNEL
    _DISABLE_COREDUMP
    _BRAVEPOLICIES
    _IOSCHEDULER
    _UDEVPERSIST
    _LIBVIRT
    _CHRONY
    _HARDENING
}

########################################################################################################################
SETUP_SSHD() {
    if [[ "${ACTIVATE_SSHD}" = "yes" ]]; then
        _SECTION " Configuration du service ssh " "━" "${C_GREEN}"
        _RUNSILENT "" sudo mkdir -pv /etc/ssh/sshd_config.d

        local config_ssh_file banner_file full_ssh_content ssh_header
        config_ssh_file="/etc/ssh/sshd_config.d/90-jotenakis.conf"
        config_ssh_allow="/etc/ssh/sshd_config.d/92-AllowUsers.conf"
        banner_file="/etc/issue.net"
        content_ssh_allow="# automatically generated and managed by ${SCRIPTNAME} - can be modified to allow other users ======
AllowUsers ${USER}
# ===========================================================================================================
"
        ssh_header="# =======================================================================
# WARNING: Do not modify this file!
# It is automatically generated and managed by ${SCRIPTNAME}.
#
# To override these settings, create a new drop-in file with a
# higher priority number (e.g., /etc/ssh/sshd_config.d/99-custom.conf).
# ======================================================================="
        readonly ssh_header content_ssh_allow

        # on concatène le header et la variable globale SSHD_CONFIG
        full_ssh_content="${ssh_header}
${SSHD_CONFIG}"

        _INSTALL_ETC_FILES "sshd" "${full_ssh_content}" "${config_ssh_file}" "600"

        # config sshd AllowUsers
        if sudo test -f "${config_ssh_allow}"; then
            _INFO "Fichier ${config_ssh_allow} déjà présent"
        else
            _OK "Configuration ${config_ssh_allow} créée"
            printf '%s' "${content_ssh_allow}" | sudo tee "${config_ssh_allow}" >/dev/null
            _RUNSILENT "" sudo chmod -v 600 "${config_ssh_allow}"
            _ETC_FILES_ADD "${config_ssh_allow}"
        fi
        {
            sudo ls -l "${config_ssh_allow}"
            sudo cat "${config_ssh_allow}"
            echo ""
        } >>"${LOG_FILE}"

        # banière /etc/issue.net
        sudo test -L "${banner_file}" && sudo rm -f "${banner_file}"
        _INSTALL_ETC_FILES "bannière sshd" "${BANNER}" "${banner_file}" "644"
        if sudo test -L /etc/issue; then
            local currentlink
            currentlink="$(sudo readlink /etc/issue || true)"
            [[ ${currentlink} != "${banner_file}" ]] && { sudo rm -f /etc/issue; _ETC_FILES_ADD "/etc/issue"; }
        else
            sudo rm -f /etc/issue
            _ETC_FILES_ADD "/etc/issue"
        fi
        _RUNSILENT "" _SYMLINK "${banner_file}" "/etc/issue"
        [[ "${STATUSSYMLINK}" -eq 0 ]] && _ETC_FILES_ADD "/etc/issue"

        # gestion service
        if _IS_ENABLED sshd; then
            if _IS_ACTIVE sshd; then
                _LOG "Le service sshd est bien activé et démarré"
            else
                _LOG "Le service sshd est bien activé mais n'est pas démarré, on le démarre maintenant"
                _RUNSILENT "" sudo systemctl start sshd.service
            fi
        else
            _RUN "Activation du service sshd" sudo systemctl --now enable sshd.service
        fi

    else
        if _IS_ENABLED sshd; then
            _SECTION " Configuration du service ssh " "━" "${C_GREEN}"
            _LOG "pas de service sshd demandé"
            _RUN "Désactivation du service sshd" sudo systemctl --now disable sshd.service sshd.socket ssh.service ssh.socket
        else
            _LOG "pas de service sshd détecté ni demandé"
        fi
    fi
}

########################################################################################################################

SET_PLM_WALLPAPER() {
    local dest_dir="/var/lib/plasmalogin/wallpapers"
    local dest_file="${dest_dir}/PlasmaLogin.jpg"
    local src="${HOME}/.local/share/wallpapers/SpacePlasma.jpg"
    #local confdirPLM="/etc/plasmalogin.conf.d"
    #local configPLM="${confdirPLM}/90-jotenakis.conf"
    local configPLM="/etc/plasmalogin.conf"

    if [[ -f "${src}" ]]; then
        _RUNSILENT "" sudo install -d -m 0755 "${dest_dir}"
        #_RUNSILENT "" sudo install -d -m 0755 "${confdirPLM}"
        _RUNSILENT "" sudo install -m 0644 "${src}" "${dest_file}"
        _LOG "Installation du wallpaper PLM"
        if ! sudo grep -Fqx "Image=file://${dest_file}" "${configPLM}" 2>/dev/null; then
            _LOG "Ajout de la configuration wallpaper PLM"
            sudo tee -a "${configPLM}" >/dev/null <<EOF

# added by post-install-script jotenakis -------------------------
[Greeter][Wallpaper][org.kde.image][General]
Image=file://${dest_file}
# /added by post-install-script jotenakis ------------------------
EOF
            _ETC_FILES_ADD "${configPLM}"
        else
            _LOG "Wallpaper PLM déjà configuré"
        fi
        {
            sudo ls -l "${configPLM}"
            sudo cat "${configPLM}"
        } >>"${LOG_FILE}"
    else
        _LOG "Fond d'écran custo de PLM introuvable : ${src}"
    fi
}

########################################################################################################################

INSTALL_DEPS() {
    local -a prerequisit=(zsh curl crudini ncurses git stow pciutils dnf-plugins-core binutils policycoreutils-python-utils)
    _MANAGE_TABLE _IS_PKG_INSTALLED _PKG_INSTALL "${prerequisit[@]}"
}

########################################################################################################################

INSTALL_FLATPAK_PACKAGES() {
    if [[ -n "${FLATPAK_PKGS[*]}" ]]; then
        _SECTION " Installation des paquets Flatpak personnalisés " "━" "${C_GREEN}"
        # 1. Vérification et installation de Flatpak
        if ! _EXIST flatpak; then
            _RUN "Installation de Flatpak" _PKG_INSTALL flatpak
        else
            _LOG "Flatpak est déjà installé"
        fi

        # 2. Ajout de Flathub s'il n'existe pas
        if ! flatpak --columns=name remotes | grep -q "^flathub$"; then
            _RUN "Ajout du dépôt Flathub" sudo flatpak --verbose remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
        else
            _INFO "Dépot flathub déjà présent"
        fi

        # 3. Activation de Flathub sans filtre
        _RUNSILENT "" sudo flatpak --verbose remote-modify --no-filter --enable flathub

        # 4. Vérification et suppression du dépôt Fedora
        if flatpak remotes --columns=name | grep -q "^fedora$"; then
            _RUN "Suppression du dépôt Fedora Flatpak" sudo flatpak --verbose remote-delete --force fedora
        else
            _LOG "Le dépôt Fedora Flatpak n'est pas présent, c'est bien."
        fi

        # 5. Installation des paquets depuis Flathub (System-wide par défaut avec sudo)
        _MANAGE_TABLE _IS_FPPKG_INSTALLED _FPPKG_INSTALL "${FLATPAK_PKGS[@]}"

        # 6. Petit nettoyage des runtimes inutilisés
        _LOG "Nettoyage des runtimes Flatpak orphelins"
        _RUNSILENT "" sudo flatpak --verbose uninstall --unused -y
    else
        _LOG "Aucun paquets Flatpak demandés"
    fi
}

########################################################################################################################

END() {
    local duration file
    rm -f /tmp/status 2>/dev/null
    _SECTION " Finalisation de ${SCRIPTNAME} " "━" "${C_GREEN}"
    _RUNSILENT "" sudo rm -f "${SUDOTMP[@]}"
    duration=$(_CONVERT_SECONDS "$((SECONDS - START))")
    _INFO "${SCRIPTNAME} v${VER} a terminé avec succès en ${duration}."
    if [[ -n "${ETC_FILES[*]}" ]]; then
        _PRINT_ETC_FILES
        _INFO "REDÉMARREZ pour appliquer les modifications complètement !"
    else
        _INFO "Aucun fichier système crée ou modifié"
        _INFO "Il est plus prudent néanmoins de redémarrer"
    fi

    # LOG
    _INFO "Fichier log de la post-installation : ${LOG_FILE}"
    _EXIST curl || _RUNSILENT "" _PKG_INSTALL curl
    local url
    url="https://temp.sh/upload"
    file=$(curl -F file=@"${LOG_FILE}" "${url}" 2>/dev/null)
    [[ -n "${file}" ]] && _OK "Log téléversé : ${file}"
    #
    echo ""
}

########################################################################################################################

_JOURNALD() {
    local journald_content journald_file
    journald_file="/etc/systemd/journald.conf"
    journald_content=$'[Journal]\nSystemMaxUse=900M\nSystemKeepFree=2G\n'
    readonly journald_file journald_content
    _LOG "* journald *"
    _INSTALL_ETC_FILES "journal système" "${journald_content}" "${journald_file}" "644"
}

########################################################################################################################

_HOSTNAME() {
    local currenthost newhost
    currenthost=$(hostnamectl hostname)
    _LOG "* nom d'hôte *"
    if [[ -n "${MYHOSTNAME}" ]] && [[ "${currenthost}" != "${MYHOSTNAME}" ]]; then
        _RUN "Changement du nom de la machine (de ${currenthost} vers ${MYHOSTNAME})" sudo hostnamectl set-hostname "${MYHOSTNAME}"
        newhost=$(hostnamectl hostname)
        _LOG "nouveau hostname : ${newhost}"
        _ETC_FILES_ADD "/etc/hostname"
    else
        _LOG "hostname déjà correctement défini"
    fi
}

########################################################################################################################

_MSMTP() {
    # par défaut msmtp ne crée pas le log system !
    if _IN_ARRAY "msmtp" "${DNF_PACKAGES[@]}"; then
        if [[ ! -f /var/log/msmtp.log ]]; then
            _LOG "config log msmtp car paquet présent"
            sudo touch /var/log/msmtp.log
            _RUNSILENT "" sudo chmod -v 600 /var/log/msmtp.log >>"${LOG_FILE}"
            _ETC_FILES_ADD "/var/log/msmtp.log"
        fi
    fi
}

########################################################################################################################

_NETWORKMANAGER() {
    local nm_dns_conf file dir restart=0
    nm_dns_conf=$'[main]\ndns=systemd-resolved\n'
    dir="/etc/NetworkManager/conf.d"
    file="${dir}/99-global-dns.conf"
    readonly nm_dns_conf file dir

    _LOG "* dns : NetworkManager *"

    if grep -rq "dns=systemd-resolved" "${dir}"; then
        _INFO "Backend DNS de NetworkManager déjà OK (${file})"
    else
        _OK "Configuration backend DNS de NetworkManager (${file})"
        printf '%s' "${nm_dns_conf}" | sudo tee "${file}" >/dev/null
        _RUNSILENT "" sudo chmod -v 644 "${file}"
        restart=1
        _ETC_FILES_ADD "${file}"
    fi

    if [[ ${restart} -eq 1 ]]; then
        _RUN "Redémarrage du service NetworkManager" sudo systemctl restart NetworkManager.service
    fi

    {
        ls -l "${file}"
        cat "${file}"
        echo ""
    } >>"${LOG_FILE}"
}

########################################################################################################################

_SYSTEMD_RESOLVED() {
    local resolved_10_conf dnsfile llmnrfile dir restart=0
    dir="/etc/systemd/resolved.conf.d"
    dnsfile="${dir}/90-dns_servers.conf"
    llmnrfile="${dir}/10-disable-llmnr.conf"
    resolved_10_conf=$'[Resolve]\nLLMNR=no\n'
    readonly resolved_10_conf dir dnsfile llmnrfile

    _LOG "* dns : systemd-resolved *"
    _RUNSILENT "" _SYMLINK "../run/systemd/resolve/stub-resolv.conf" "/etc/resolv.conf"

    if [[ ! -f "${dnsfile}" ]] || [[ ! -f "${llmnrfile}" ]]; then
        _OK "Configuration DNS (dans ${dir})"
        printf '%s' "${RESOLVED_DNS_SERVERS}" | sudo tee "${dnsfile}" >/dev/null
        printf '%s' "${resolved_10_conf}" | sudo tee "${llmnrfile}" >/dev/null
        _RUNSILENT "" sudo chmod -v 644 "${dnsfile}" "${llmnrfile}"
        restart=1
        _ETC_FILES_ADD "${dnsfile}"
        _ETC_FILES_ADD "${llmnrfile}"
    else
        _INFO "Configuration DNS déjà OK (dans ${dir})"
    fi

    if [[ ${restart} -eq 1 ]]; then
        _RUN "Redémarrage du service systemd-resolved" sudo systemctl restart systemd-resolved
    fi

    {
        ls -l "${dnsfile}"
        cat "${dnsfile}"
        echo ""
        ls -l "${llmnrfile}"
        cat "${llmnrfile}"
        echo ""
    } >>"${LOG_FILE}"
}

########################################################################################################################

_KERNEL() {
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
    full_sysctl_content="${sysctl_header}
${SYSCTL_CONF}"

    _LOG "* sysctl *"
    _INSTALL_ETC_FILES "noyau" "${full_sysctl_content}" "${sysctlfile}" "644"
    grep -qxF 0 "/tmp/status" 2>/dev/null && _RUNSILENT "" sudo sysctl -p "${sysctlfile}" || true
}

########################################################################################################################

_BRAVEPOLICIES() {
    # --- Configuration Brave Browser (Policies debloat) ---
    _LOG "* Brave debloat *"
    if [[ -n "${BRAVE_POLICIES}" ]]; then
        local brave_policy_file full_brave_policies
        brave_policy_file="/etc/brave/policies/managed/brave_debullshitinator-policies.json"
        full_brave_policies=$(echo "${BRAVE_POLICIES}" | sed "1s/{/{\n    \"_warning\": \"Do not modify this file! It is managed by ${SCRIPTNAME}.\",/")
        readonly brave_policy_file full_brave_policies
        _INSTALL_ETC_FILES "politiques de Brave" "${full_brave_policies}" "${brave_policy_file}" "644"
    else
        _LOG "Aucune politique de Brave demandée"
    fi
}

########################################################################################################################

_IOSCHEDULER() {
    # IO scheduler NVMe = none, SSD = mq-deadline, HDD = bfq
    # Some may prefer kyber for nvme
    #
    local rules_file rules_content
    rules_file="/etc/udev/rules.d/60-ioschedulers.rules"
    rules_content='# NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]*", ATTR{queue/scheduler}="none"

# SSD SATA / eMMC
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# HDD rotatif
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
'
    _LOG "* IO scheduler *"
    _INSTALL_ETC_FILES "règles d'ordonnancement des E/S" "${rules_content}" "${rules_file}" "644"
    if grep -qxF 0 "/tmp/status" 2>/dev/null; then
        _RUNSILENT "" sudo udevadm control --reload-rules
        _RUNSILENT "" sudo udevadm trigger
    fi
}

########################################################################################################################

_UDEVPERSIST() {
    # --- udev static custom rule, par exemple clé usb
    _LOG "* udev persist custom *"
    if [[ -n "${UDEVRULE}" ]]; then
        local udevfilename rules_file
        udevfilename="99-persist-key.rules"
        rules_file="/etc/udev/rules.d/${udevfilename}"

        _INSTALL_ETC_FILES "règle udev persistante (${UDEVDESCR})" "${UDEVRULE}" "${rules_file}" "644"
        if grep -qxF 0 "/tmp/status" 2>/dev/null; then
            _RUNSILENT "" sudo udevadm control --reload-rules
            _RUNSILENT "" sudo udevadm trigger
        fi
    else
        _LOG "Aucune règle udev persistante demandée"
    fi
}

########################################################################################################################

_LIBVIRT() {
    # --- Groupe libvirt ---
    _LOG "* groupe libvirt *"

    if getent group libvirt >/dev/null 2>&1; then
        if id -nG "${USER}" | grep -qw "libvirt"; then
            _INFO "Utilisateur ${USER} déjà dans libvirt"
        else
            _RUN "Ajout de l'utilisateur ${USER} au groupe libvirt" sudo usermod -aG libvirt "${USER}"
            _ETC_FILES_ADD "/etc/group"
        fi
    fi
    {
        ls -l /etc/group
        grep libvirt /etc/group
        echo ""
    } >>"${LOG_FILE}"

}

########################################################################################################################

_CHRONY() {
    # --- Configuration Chrony (IPv4 only si IPv6 désactivé) ---
    _LOG "* chrony *"
    if echo "${CMDLINE}" | grep -q 'ipv6.disable=1'; then
        local chrony_file chrony_content
        chrony_file="/etc/sysconfig/chronyd"
        chrony_content=$'# Command-line options for chronyd\nOPTIONS="-F 2 -4"\n'
        readonly chrony_file chrony_content

        _INSTALL_ETC_FILES "chronyd" "${chrony_content}" "${chrony_file}" "644"
        grep -qxF 0 "/tmp/status" 2>/dev/null && _RUNSILENT "" sudo systemctl try-restart chronyd || true
    else
        _LOG "ipv6 n'est pas activé donc on ne change rien à chrony"
    fi
}

########################################################################################################################

_DISABLE_COREDUMP(){
    local file content dir limits_file dirlimits dirprofile profile
    dir="/etc/systemd/coredump.conf.d"
    dirlimits="/etc/security/limits.d"
    dirprofile="/etc/profile.d"
    sudo mkdir -p "${dir}" "${dirlimits}" "${dirprofile}"

    _LOG "* coredump disable *"

    file="${dir}/disable.conf"
    content=$'[Coredump]\nStorage=none\nProcessSizeMax=0\n'
    _INSTALL_ETC_FILES "coredump systemd" "${content}" "${file}" "644"
    grep -qxF 0 "/tmp/status" 2>/dev/null && _RUNSILENT "" sudo systemctl daemon-reload || true
    { ls -l "${file}" ; cat "${file}" ; echo "" ; } >> "${LOG_FILE}"

    limits_file="${dirlimits}/disable-coredump.conf"
    if ! grep -qxF "* soft core 0" "${limits_file}" 2>/dev/null; then
        printf '* soft core 0\n* hard core 0\n' | sudo tee "${limits_file}" > /dev/null
        _OK "Configuration coredump (${limits_file})"
        _ETC_FILES_ADD "${limits_file}"
    else
        _INFO "Coredump déja OK (${limits_file})"
    fi
    { ls -l "${limits_file}" ; cat "${limits_file}" ; echo "" ; } >> "${LOG_FILE}"

    profile="${dirprofile}/coredump.sh"
    content=$'ulimit -c 0\n'
    _INSTALL_ETC_FILES "coredump shell" "${content}" "${profile}" "644"
    { ls -l "${profile}" ; cat "${profile}" ; echo "" ; } >> "${LOG_FILE}"

}

########################################################################################################################

_INSTALL_USER_CRONTAB(){
    local cron_job1 cron_job2
    _LOG "* crontab ${USER} *"
    _EXIST crontab || _RUNSILENT "" _PKG_INSTALL cronie
    cron_job1='0 21 * * 0 ~/.local/share/cargo/bin/sheldon lock --update >> ~/.local/share/sheldon/update.log 2>&1'
    if ! crontab -l 2>/dev/null | grep -qF ".local/share/cargo/bin/sheldon lock --update"; then
        _RUN "Tâche cron \"sheldon update\" ajoutée pour ${USER}" bash -c "( crontab -l 2>/dev/null; echo \"${cron_job1}\" ) | crontab -"
    else
        _INFO "Tâche cron \"sheldon update\" déjà là pour ${USER}"
    fi
    cron_job2='5 */4 * * * ~/.local/share/cargo/bin/tldr -u >/tmp/tldr 2>&1'
    if ! crontab -l 2>/dev/null | grep -qF ".local/share/cargo/bin/tldr -u"; then
        _RUN "Tâche cron \"tldr update\" ajoutée pour ${USER}" bash -c "( crontab -l 2>/dev/null; echo \"${cron_job2}\" ) | crontab -"
    else
        _INFO "Tâche cron \"tldr update\" déjà là pour ${USER}"
    fi
    _RUNSILENT "" crontab -l
}

########################################################################################################################

_CLEANUP() {
    echo -e "${C_BOLD}${C_RED} Plantage !${C_RESET}"
    sudo rm -f "${SUDOTMP[@]}" /tmp/status
    _PRINT_ETC_FILES
    echo -e "${C_BOLD}${C_RED}"
    echo "Extrait du Log : "
    tail -5 "${LOG_FILE:-}" 2>/dev/null
    echo -e "${C_RESET}"
    _DIE "Log complet : ${LOG_FILE:-}"
}

########################################################################################################################

_INTERRUPT() {
    echo -e "${C_BOLD}${C_GREEN} Arrêt du script demandé par l'utilisateur...${C_RESET}"
    sudo rm -f "${SUDOTMP[@]}" /tmp/status
    _PRINT_ETC_FILES
    echo -e "${C_BOLD}${C_GREEN}"
    echo "Extrait du Log : "
    tail -5 "${LOG_FILE:-}" 2>/dev/null
    echo -e "${C_RESET}"
    _DIE "Log complet : ${LOG_FILE:-}"
}

########################################################################################################################

_HARDENING(){
    local rights file dir
    dir="/etc/tmpfiles.d"
    file="${dir}/hardening-perms.conf"
    _RUNSILENT "" sudo mkdir -pv "${dir}"
    rights='
z /etc/cron.deny    0600 root root -
z /etc/cron.allow   0600 root root -
z /etc/at.deny      0600 root root -
z /etc/at.allow     0600 root root -
z /etc/crontab      0600 root root -
z /etc/cron.d       0700 root root -
Z /etc/cron.hourly  0700 root root -
Z /etc/cron.daily   0700 root root -
Z /etc/cron.weekly  0700 root root -
Z /etc/cron.monthly 0700 root root -
'
    _INSTALL_ETC_FILES "robustification des droits (${file})" "${rights}" "${file}" "644"
     grep -qxF 0 "/tmp/status" 2>/dev/null && _RUNSILENT "" sudo systemd-tmpfiles --create "${file}"

}

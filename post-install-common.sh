#!/usr/bin/env bash
# shellcheck disable=SC2310
set -euo pipefail
readonly SCRIPTNAME="${0##*/}"
readonly VER=26.5
# paramètres customisables définis dans settings.sh. ###############################
source ./settings.sh                                                               #
####################################################################################

# ─── MAIN ────────────────────────────────────────────────────────────────────────────────────────────────────────────
MAIN() {
    args=${1:-}
    source helpers.sh # bibliothèque de fonctions d'aide
    _INIT_COLOR
    trap '_ERR "Interruption ligne ${LINENO}"; _DIE "Log : ${LOG_FILE}"' ERR # gestion des erreurs

    # Préparation
    CHECK
    INITIALIZE

    if [[ "${args}" = "--shellonly" ]]; then
        INSTALL_CARGO_PACKAGES
        INSTALL_GO_PACKAGES
        CLONE_GIT
        SETUP_SHELL
        SETUP_DOTFILES
        SETUP_DATA
    else
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
        SETUP_CHRONY
        SETUP_SYSTEMD
        SETUP_FIREWALL
        SETUP_SWAP
        SETUP_SSHD
        SETUP_FSTAB
        SETUP_GRUB
        SETUP_KDE_PLASMA
        SETUP_PLM
        SETUP_DATA
    fi

    # Finalisation
    END
}
# ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

########################################################################################################################
# FONCTIONS DISTRO-AGNOSTIQUE                                                                                          #
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
    _BANNER "blue" "${SCRIPTNAME} (${VER})"
    _SECTION " Préparation de la post-installation " "━" "${C_GREEN}"
    _LOG "*** Préparation ***"
    _OK "Heure de démarrage de la post-installation : ${heure}"
    _OK "Fichier log de la post-installation : ${LOG_FILE}"
    INSTALL_DEPS


    _LOG "*** INITIALIZE ***"

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
    SUDOTMP="/etc/sudoers-rs.d/99_POST-INSTALL" # pour delete à la fin
    local sudotmp="/etc/sudoers.d/99_POST-INSTALL"

    _RUNSILENT "" sudo bash -c "echo 'Defaults pwfeedback,timestamp_timeout=180' > '${sudotmp}'"
    _RUNSILENT "" sudo chmod -v 0440 "${sudotmp}"


    _HEURE >> "${LOG_FILE}"

    # aussitôt je conf le package manager si besoin pour accélérer les download de paquets
    _PKG_CONFIG

    # PATH
    export PATH="${GOBIN}:${CARGO_HOME}/bin:${INSTALL_DIR}:${PATH}"
    #
}

########################################################################################################################
INSTALL_CARGO_PACKAGES() {
    _SECTION " Installation des paquets Cargo personnalisés " "━" "${C_GREEN}"
    _LOG "*** Paquets Cargo ***"

    # 0. toolchain rust
    local check
    if _EXIST rustup; then
        check=$(rustup check 2>/dev/null)
        if echo "${check}" | grep -q "update available"; then
            version=$(echo "${check}"| awk -F ":" '{print $2}' | xargs)
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

    # 2 & 3. Installation des paquets via Cargo (binstall) + symlinks
    #local -a to_install=() already_installed=()
    #local list cmd
    declare -g installed_list
    installed_list=$(cargo install --list 2>/dev/null)

    # for cmd in "${CARGO_PACKAGES[@]}"; do
    #     if echo "${installed_list}" | grep -q "^${cmd} "; then
    #         _LOG "${cmd} déjà installé"
    #         already_installed+=("${cmd}")
    #     else
    #         to_install+=("${cmd}")
    #     fi
    # done
    #
    # if [[ ${#already_installed[@]} -gt 0 ]]; then
    #     list=$(_FORMAT_LIST "${already_installed[@]}")
    #     _OK "Paquets déjà installés : ${list}"
    # fi
    #
    # if [[ ${#to_install[@]} -gt 0 ]]; then
    #     list=$(_FORMAT_LIST "${to_install[@]}")
    #     _OK "Paquets à installer : ${list}"
    #     _RUN "Installation des paquets manquants" cargo binstall --no-confirm "${to_install[@]}"
    # else
    #     _OK "Aucun paquet à installer"
    # fi

    _MANAGE_TABLE "INSTALLÉ correctement" _IS_CARGOPKG_INSTALLED _CARGOPKG_INSTALL "${CARGO_PACKAGES[@]}"

    local cmd
    # symlinks après installation
    for cmd in "${CARGO_PACKAGES[@]}"; do
        local bins_to_link bin_name
        bins_to_link="${BIN_MAPPING[${cmd}]:-${cmd}}"
        for bin_name in ${bins_to_link}; do
            _RUNSILENT "" _SYMLINK "${CARGO_HOME}/bin/${bin_name}" "/usr/local/bin/${bin_name}"
        done
    done

    # 4. Ajustement des permissions pour l'accès global
    _RUNSILENT "" chmod a+x -v "${HOME}" "${HOME}/.local" "${HOME}/.local/share" "${CARGO_HOME}" "${CARGO_HOME}/bin"
}

########################################################################################################################
INSTALL_GO_PACKAGES() {
    _SECTION " Installation des paquets GO personnalisés " "━" "${C_GREEN}"
    _LOG "*** Paquets GO ***"
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
            _OK "Tout est INSTALLÉ correctement : ${present[*]}"
        else
            [[ -n "${present[*]}" ]] && _OK "Déjà installé : ${present[*]}"
        fi
        for pkg in "${missing[@]}"; do
            _RUN "Installation de ${pkg}" go install "${pkg}"
        done
        for pkg in "${missingbin[@]}"; do
            _RUNSILENT "" _SYMLINK "${GOBIN}/${pkg}" "/usr/local/bin/${pkg}"
        done
    fi
}

########################################################################################################################
INSTALL_GIT_REPOS() {
    local repo name target
    _RUNSILENT "" mkdir -pv "${HOME}/git"
    _SECTION " Installation des dépôts Git personnalisés " "━" "${C_GREEN}"

    for repo in "${GIT_REPOS[@]}"; do
        name="${repo##*/}"
        target="${HOME}/git/${name}"

        if [[ -d "${target}" ]]; then
            if git -C "${target}" rev-parse --git-dir &>/dev/null; then
                _RUN "Mise à jour de ${name}" git -C "${target}" pull --ff-only
            else
                _ERR "${target} existe mais n'est pas un dépôt git, ignoré"
            fi
        else
            _RUN "Téléchargement de ${name}" git clone "${repo}" "${target}"
        fi

        if [[ "${repo}" == "${DOTFILES_REPO}" && "${target}" != "${DOTFILES_DIR}" ]]; then
            #ln -sfn "${target}" "${DOTFILES_DIR}"
            _RUNSILENT "" _SYMLINK "${target}" "${DOTFILES_DIR}"
        fi
    done
}


# CLONE_GIT() {
#     _SECTION " Installation des dépôts Git personnalisés " "━" "${C_GREEN}"
#     _LOG "*** dépôts git personnels ***"
#     local repo_entry repo_url dest_dir repo_name backup_dir
#
#     for repo_entry in "${GIT_REPOS[@]}"; do
#         # Extraction de l'URL et de la destination (séparées par '|')
#         repo_url="${repo_entry%%|*}"
#         dest_dir="${repo_entry##*|}"
#
#         # Récupération du nom du dépôt pour l'affichage (ex: "scripts")
#         repo_name=$(basename "${repo_url}" .git)
#
#         if [[ -d "${dest_dir}/.git" ]]; then
#             # C'est un dépôt Git valide, on le met à jour
#             _RUN "Mise à jour de ${repo_name}" git -C "${dest_dir}" pull --ff-only
#         else
#             # Le chemin existe MAIS n'est pas un dépôt Git (ou c'est un fichier)
#             if [[ -e "${dest_dir}" ]]; then
#                 backup_dir="${dest_dir}_backup_$(date +%Y%m%d%H%M%S)"
#                 _RUN "Sauvegarde de l'existant non-git (${repo_name})" mv "${dest_dir}" "${backup_dir}"
#                 _INFO "Ancien '${dest_dir}' sauvegardé dans '${backup_dir}'"
#             fi
#
#             # La voie est libre, on clone
#             _RUN "Téléchargement de ${repo_name}" git clone "${repo_url}" "${dest_dir}"
#         fi
#     done
# }

########################################################################################################################
SETUP_SHELL() {
    _SECTION " Configuration du shell par défaut (zsh) " "━" "${C_GREEN}"
    _LOG "*** Shell ***"
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
                _OK "${user} utilise déjà zsh"
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

    # 3- symlinks
    _SYMLINK "${HOME}/.local/share/icons" "${HOME}/.icons"
    _SYMLINK "${HOME}/.local/share/themes" "${HOME}/.themes"
    #_SYMLINK "${HOME}/.config/mozilla/firefox" "${HOME}/.mozilla/firefox"
    #_SYMLINK "${HOME}/.config/thunderbird" "${HOME}/.thunderbird"

    # 4- installation de fedupdate
    # local here fedupdate
    # fedupdate=$(command -v fedupdate)
    # if [[ -z "${fedupdate}" ]] && command -v make >/dev/null 2>&1; then
    #     here=$(pwd)
    #     cd "${HOME}/fedupdate"
    #     _RUNSILENT "Installation de fedupdate" make install
    #     cd "${here}"
    # elif [[ -n "${fedupdate}" ]]; then
    #     _OK "fedupdate est déjà installé (${fedupdate})"
    # fi

    # 4- Divers
}

########################################################################################################################
SETUP_DOTFILES() {
    _SECTION " Installation des configurations personnalisées de ${USER} (dotfiles) " "━" "${C_GREEN}"
    _LOG "*** dotfiles ***"

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
    echo -en "${C_GREEN}✓ ${C_RESET}"
    for pkg in "${DOTFILES_DIR}"/*/; do
        name=$(basename "${pkg}")
        #_RUNSILENT "${name}"
        echo -n "${name} "
        stow --dir="${DOTFILES_DIR}" --target="${HOME}" --restow "${name}" &>>"${LOG_FILE}"
    done
    echo ""

    if _EXIST bat; then
        _LOG "Reconstruction du cache de bat"
        _RUNSILENT "" bash -c "bat cache --clear; bat cache --build"
    fi
    _INFO "Les dotfiles ne sont déployés que pour l'utilisateur qui lance le script (ici : ${USER})"

}

########################################################################################################################
SETUP_SYSTEMD(){
    _LOG "*** systemd ***"
    local service
    local description
    local -a missing=()
    local -a present=()

    for service in "${!SERVICES_TO_DISABLE[@]}"; do
        description="${SERVICES_TO_DISABLE[${service}]}"
        if _IS_ENABLED "${service}"; then
            present+=("${service}")
        else
            missing+=("${pkg}")
        fi
    done

    local all_fmt
    local missing_fmt
    local present_fmt
    present_fmt=$(_FORMAT_LIST "${present[@]}")
    if ((${#missing[@]})); then
        missing_fmt=$(_FORMAT_LIST "${missing[@]}")
        ((${#present[@]})) && _OK "Déjà désactivés : ${present_fmt}"
        _OK "À désactiver : ${missing_fmt}"
        _RUN "Désactivation des services" sudo systemctl disable --now "${missing[@]}"
    else
    #     all_fmt=$(_FORMAT_LIST "$@")
    #     _OK "Tout est ${msg} : ${all_fmt}"
        _OK "Tous les services sont déjà désactivés : ${present_fmt}"
    fi

    #
    # _OK "Le ${description} est déjà désactivé"


    for service in "${!USER_SERVICES_TO_ENABLE[@]}"; do
        description="${USER_SERVICES_TO_ENABLE[${service}]}"
        if ! _IS_ENABLED_USER "${service}"; then
            _RUN "Activation du ${description}" systemctl --user enable --now "${service}"
        else
            _OK "Le ${description} est déjà activé"
        fi
    done
}

########################################################################################################################
SETUP_FSTAB(){
    _SECTION " Configuration du fichier FSTAB " "━" "${C_GREEN}"
    _LOG "*** /etc/fstab ***"

    # SWAPFILE
    local swapdir="/var/swap"
    if ! grep -q "${swapdir}/swapfile" /etc/fstab; then
        if [[ ! -f /etc/fstab.origin ]]; then
            _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.origin
        fi
        _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.bak.swap
        _RUN "Ajout du swap" sudo bash -c "echo ${swapdir}/swapfile none swap defaults,nofail 0 0 >> /etc/fstab"
    else
        _OK "Swap déjà présent dans /etc/fstab"
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
            if [[ ! ",${opts}," =~ ,commit=60, ]] && [[ "${fs}" = "ext4" ]]; then
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
        _OK "Les options d'optimisations sont déjà présentes dans /etc/fstab"
    fi

    # NFS
    local opts
    opts="rw,_netdev,nofail,nodev,nosuid,noexec,noatime,lazytime,x-systemd.automount,x-systemd.device-timeout=30"
    if ! grep -q "${NFS_SHARE}" /etc/fstab >/dev/null; then
        if grep -q "${NFS_MP}" /etc/fstab >/dev/null; then
            _INFO "Le point de montage demandé (${NFS_MP}) est déjà présent dans /etc/fstab :"
            grep "${NFS_MP}" /etc/fstab
            _INFO "Abandon de l'installation du partage réseau NFS."
        else
            _RUNSILENT "" sudo mkdir -pv "${NFS_MP}"
            _RUNSILENT "" sudo cp -av /etc/fstab /etc/fstab.bak.nfs
            echo "${NFS_SHARE}   ${NFS_MP}   nfs   ${opts}      0 0" | sudo tee -a /etc/fstab >/dev/null
            _RUNSILENT "" sudo systemctl daemon-reload
            _RUNSILENT "" sudo mount -v "${NFS_MP}"
            _RUN "Installation du partage réseau NFS" sudo ls -l "${NFS_MP}"
        fi
    else
        _RUN "Montage NFS déjà installé"
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
            _RUN "Activation flag fast_commit sur ${dev} (montée en ${mp})" sudo tune2fs -O fast_commit "${dev}"
        fi
    done <<< "${mounts}"

    # Nettoyage
    rm -rf "${tmp_dir}"
}

########################################################################################################################
SETUP_DATA() {
    _LOG "*** Restauration des données privées de l'utilisateur ${USER} ***"
    _SECTION " Restauration des données privées de l'utilisateur ${USER} " "━" "${C_GREEN}"
    if [[ -d "${SOURCE}" ]]; then
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
                            _OK "Aucun fichier de sauvegarde trouvé pour le profil ${profil}"
                        fi
                    fi
            done
        else
            echo ""
            _INFO "Aucune données privées à restaurer"
        fi
    else
        _ERR "Le dossier de restauration (${SOURCE}) n'existe pas"
    fi
}

########################################################################################################################
SETUP_KDE_PLASMA() {
    _LOG "*** Personnalisation de KDE Plasma 6 ***"
# on check KDE est lancé
    if pgrep -f '\b(plasmashell|kwin|kwin_wayland|plasma-desktop)\b'> /dev/null; then
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
            _RUN "Installation des icônes Tela (dans ${HOME}/.local/share/icons/)" bash -c "   \"${temp_tela}\"/tela/install.sh -a -d \"${HOME}\"/.local/share/icons   "
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
            echo -e "[Icon Theme]\nInherits=catppuccin-mocha-lavender-cursors" > "${HOME}/.local/share/icons/default/index.theme"
        fi

        # Baloo
        if _EXIST balooctl6; then
            if balooctl6 status > /dev/null 2>&1; then
                _RUN "Désactivation du service d'indexation de KDE Plasma (baloo)" bash -c "balooctl6 suspend ; balooctl6 disable ; balooctl6 purge"
            else
                _OK "Service d'indexation déjà désactivé"
            fi
        else
            _INFO "L'outil balooctl n'est pas installé. Aucune action requise"
        fi

        # déplacement du panneau principal
        local target_pos="${KDEPANEL:-bottom}" # fallback en bas
        local display_pos
        case "${target_pos}" in
            bottom) display_pos="basse";;
            top) display_pos="haute";;
            right) display_pos="droite";;
            left) display_pos="gauche";;
            *) display_pos="inconnue";;
        esac

        if ! pgrep plasmashell > /dev/null 2>&1; then
            _INFO "plasmashell n'est pas lancée, déplacement du panneau annulé"
        else
            local current_positions
            current_positions=$(_PLASMA_GET_PANEL_LOCATION)

            if [[ -z "${current_positions}" ]]; then
                _INFO "Aucun panneau détecté"
            elif [[ "${current_positions}" == "${target_pos}" ]]; then
                _OK "Panneau déjà à la position voulue (${display_pos})"
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
        if pgrep plasmashell > /dev/null 2>&1; then
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
                _OK "Aucune modification de configuration effectuée, je ne redémarre pas l'interface de KDE Plasma 6"
            fi
        fi

        # Configuration des thèmes pour les applications Flatpak (Mode global/system-wide overrides)
        if _EXIST flatpak; then
            _RUNSILENT "" sudo flatpak override \
                --filesystem="${HOME}/.local/share/icons:ro" \
                --filesystem="${HOME}/.local/share/themes:ro" \
                --filesystem="${HOME}/.icons:ro" \
                --filesystem="${HOME}/.themes:ro" \
                --filesystem="xdg-config/gtk-3.0:ro" \
                --filesystem="xdg-config/gtk-4.0:ro" \
                --env="GTK_THEME=TokyoNight" \
                --env="ICON_THEME=Tela-dracula-dark" \
                --env="XCURSOR_THEME=catppuccin-mocha-lavender-cursors"
        fi
    else
        echo
        _INFO "KDE n'a pas été détecté, je ne touche pas à la customization de KDE"
    fi
}

########################################################################################################################
SETUP_PLM() {
    _LOG "*** Display Manager KDE ***"
# on teste si KDE tourne
    local change=0
    if pgrep -f '\b(plasmashell|kwin|kwin_wayland|plasma-desktop)\b'> /dev/null; then
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
            _OK "Plasma Login Manager est déjà correctement configuré pour remplacer SDDM"
        fi
        SET_PLM_WALLPAPER
    else
        echo
        _INFO "KDE n'a pas été détecté, on ne touche pas au display-manager"
    fi
}


########################################################################################################################
SETUP_ETC() {
    _SECTION " Configuration générale du système " "━" "${C_GREEN}"
    _LOG "*** configuration système ***"

    # par défaut msmtp ne crée pas le log system
    if _IN_ARRAY "msmtp" "${DNF_PACKAGES[@]}"; then
        _LOG "config log msmtp car paquet présent"
        _RUNSILENT "" sudo bash -c "touch /var/log/msmtp.log && chmod -v 600 /var/log/msmtp.log"
    fi

    # --- Hostname ---
    local currenthost newhost
    currenthost=$(hostnamectl hostname)
    if [[ -n "${MYHOSTNAME}" ]] && [[ "${currenthost}" != "${MYHOSTNAME}" ]]; then
        _RUN "Changement du nom de la machine (de ${currenthost} vers ${MYHOSTNAME})" sudo hostnamectl set-hostname "${MYHOSTNAME}"
        newhost=$(hostnamectl hostname)
        _LOG "nouveau hostname : ${newhost}"
    fi

    # --- NetworkManager & systemd-resolved ---
    _LOG "* réseau *"
    local nm_dns_conf resolved_10_conf restart=0
    nm_dns_conf=$'[main]\ndns=systemd-resolved\n'
    resolved_10_conf=$'[Resolve]\nLLMNR=no\n'
    readonly nm_dns_conf resolved_10_conf

    if ! grep -rq "dns=systemd-resolved" /etc/NetworkManager/conf.d; then
        _RUN "Configuration de NetworkManager pour systemd-resolved (/etc/NetworkManager/conf.d/99-global-dns.conf)" sudo bash -c "
        echo '${nm_dns_conf}' | install -v -m 644 -o root -g root /dev/stdin /etc/NetworkManager/conf.d/99-global-dns.conf
        "
        restart=1
    else
        _OK "NetworkManager déjà configuré pour utiliser systemd-resolved (/etc/NetworkManager/conf.d/99-global-dns.conf)"
    fi

    _RUNSILENT "" _SYMLINK /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

    if [[ ! -f /etc/systemd/resolved.conf.d/dns_servers.conf ]] || [[ ! -f /etc/systemd/resolved.conf.d/10-disable-llmnr.conf ]]; then
        _RUN "Déploiement de la configuration DNS (dans /etc/systemd/resolved.conf.d/)" sudo bash -c "echo '${RESOLVED_DNS_SERVERS}' | install -v -m 644 -o root -g root /dev/stdin /etc/systemd/resolved.conf.d/dns_servers.conf ; echo '${resolved_10_conf}' | install -v -m 644 -o root -g root /dev/stdin /etc/systemd/resolved.conf.d/10-disable-llmnr.conf"
        restart=1
    else
        _OK "Configuration DNS déjà présente (dans /etc/systemd/resolved.conf.d/)"
    fi
    if [[ ${restart} -eq 1 ]]; then
        _RUN "Redémarrage des services NetworkManager et systemd-resolved" sudo systemctl restart systemd-resolved NetworkManager
    fi

    # --- Optimisations Kernel (Sysctl) ---
    _LOG "* sysctl *"
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
        _OK "Configuration noyau déjà à jour (${sysctlfile})"
    else
        _RUN "Déploiement de la configuration du noyau (${sysctlfile})" sudo install -v -m 644 -o root -g root /dev/stdin "${sysctlfile}" <<< "${full_sysctl_content}"
        _RUNSILENT "" sudo sysctl -p "${sysctlfile}"
    fi

    # --- Configuration Brave Browser (Policies debloat) ---
    _LOG "* brave debloat *"
    local brave_policy_file full_brave_policies
    brave_policy_file="/etc/brave/policies/managed/brave_debullshitinator-policies.json"
    full_brave_policies=$(echo "${BRAVE_POLICIES}" | sed "1s/{/{\n    \"_warning\": \"Do not modify this file! It is managed by ${SCRIPTNAME}.\",/")
    readonly brave_policy_file full_brave_policies

    if [[ -f "${brave_policy_file}" ]] && echo "${full_brave_policies}" | sudo cmp -s - "${brave_policy_file}"; then
        _OK "Configuration policies debloat Brave déjà à jour (${brave_policy_file})"
    else
        _RUN "Déploiement des policies pour débloater Brave (${brave_policy_file})" sudo install -v -m 644 -o root -g root /dev/stdin "${brave_policy_file}" <<< "${full_brave_policies}"
    fi

    # IO scheduler
    _LOG "* udev *"
    local rules_file rules_content current
    rules_file="/etc/udev/rules.d/60-ioschedulers.rules"
    sudo touch "${rules_file}"
    current=$(cat "${rules_file}" 2>/dev/null || true)
    rules_content='# NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]*", ATTR{queue/scheduler}="none"

# SSD SATA / eMMC
ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# HDD rotatif
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
'

    if [[ -f "${rules_file}" ]] &&  echo "${rules_content}" | sudo cmp -s - "${rules_file}"; then
        _OK "Règle IO scheduler déjà à jour (${rules_file})"
    else
        #printf '%s\n' "${rules_content}" | sudo tee "${rules_file}" > /dev/null
        _RUN "Règle IO scheduler créée (${rules_file})" sudo install -v -m 644 -o root -g root /dev/stdin "${rules_file}" <<< "${rules_content}"
        _RUNSILENT "" sudo udevadm control --reload-rules
        _RUNSILENT "" sudo udevadm trigger
    fi

    # --- udev static custom rule
    rules_file="/etc/udev/rules.d/${UDEVFILE}" ; sudo touch "${rules_file}"
    rules_content="${UDEVRULE}"
    current=$(cat "${rules_file}" 2>/dev/null || true)

    if [[ -f "${rules_file}" ]] &&  echo "${rules_content}" | sudo cmp -s - "${rules_file}"; then
        _OK "Règle udev persistante (${UDEVDESCR}) à jour (${rules_file})"
    else
        _RUN "Règle udev persistante (${UDEVDESCR}) créée (${rules_file})" sudo install -v -m 644 -o root -g root /dev/stdin "${rules_file}" <<< "${rules_content}"
        _RUNSILENT "" sudo udevadm control --reload-rules
        _RUNSILENT "" sudo udevadm trigger

    fi

    # --- Groupe libvirt ---
    _LOG "* groupe *"
    local main_user
    main_user=${USER}

    if getent group libvirt >/dev/null 2>&1; then
        if id -nG "${main_user}" | grep -qw "libvirt"; then
            _OK "L'utilisateur ${main_user} est déjà dans le groupe libvirt"
        else
            _RUN "Ajout de l'utilisateur ${main_user} au groupe libvirt" sudo usermod -aG libvirt "${main_user}"
        fi
    fi

}

########################################################################################################################
SETUP_SSHD(){
    if [[ "${ACTIVATE_SSHD}" = "yes" ]]; then
        _SECTION " Configuration du service ssh " "━" "${C_GREEN}"
        _LOG "*** service sshd ***"
        _RUNSILENT "" sudo mkdir -pv /etc/ssh/sshd_config.d

        local config_ssh_file banner_file full_ssh_content ssh_header
        config_ssh_file="/etc/ssh/sshd_config.d/90-jotenakis.conf"
        config_ssh_allow="/etc/ssh/sshd_config.d/92-AllowUsers.conf"
        banner_file="/etc/issue.net"
        #sudo touch "${config_ssh_file}" "${banner_file}" "${config_ssh_allow}"

        content_ssh_allow="AllowUsers ${USER}" # on autorise l'utilisateur qui a lancé le script à se connecter en ssh et c'est tout
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

        # config sshd custo
        if sudo test -f "${config_ssh_file}" && echo "${full_ssh_content}" | sudo cmp -s - "${config_ssh_file}"; then
            _OK "Configuration sshd déjà à jour (${config_ssh_file})"
        else
            _RUN "Configuration sshd créée (${config_ssh_file})" sudo install -v -m 600 -o root -g root /dev/stdin "${config_ssh_file}" <<< "${full_ssh_content}"
        fi

        # config sshd AllowUsers
        if sudo test -f "${config_ssh_allow}"; then
            _OK "Fichier ${config_ssh_allow} déjà présent"
        else
            _RUN "Configuration ${config_ssh_allow} créée" sudo install -v -m 600 -o root -g root /dev/stdin "${config_ssh_allow}" <<< "${content_ssh_allow}"
        fi

        # banière /etc/issue.net
        if sudo test -f "${banner_file}" && echo "${BANNER}" | sudo cmp -s - "${banner_file}"; then
            _LOG "Bannière sshd à jour (${banner_file})"
        else
            _LOG "Création banière (${banner_file})"
            _RUNSILENT "" sudo rm -fv "${banner_file}"
            _RUNSILENT "" sudo install -v -m 644 -o root -g root /dev/stdin "${banner_file}" <<< "${BANNER}"
        fi

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
            _RUN "Désactivation du service sshd" sudo systemctl --now disable sshd.service
        else
            _LOG "pas de service sshd détecté ni demandé, rien à faire"
        fi
    fi
}

########################################################################################################################

SET_PLM_WALLPAPER() {
    local dest_dir="/var/lib/plasmalogin/wallpapers"
    local dest_file="${dest_dir}/PlasmaLogin.jpg"
    local src="${HOME}/.local/share/wallpapers/SpacePlasma.jpg"
    local confdirPLM="/etc/plasmalogin.conf.d"
    #local configPLM="${confdirPLM}/90-jotenakis.conf"
    local configPLM="/etc/plasmalogin.conf"

    if [[ -f "${src}" ]]; then
        _RUNSILENT "" sudo install -d -m 0755 "${dest_dir}"
        _RUNSILENT "" sudo install -d -m 0755 "${confdirPLM}"
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
        else
            _LOG "Wallpaper PLM déjà configuré"
        fi
    else
        _LOG "Fond d'écran de PLM introuvable : ${src}"
    fi
}

########################################################################################################################

INSTALL_DEPS() {
    local -a prerequisit=(curl crudini ncurses git stow pciutils dnf-plugins-core binutils policycoreutils-python-utils)
    _MANAGE_TABLE "INSTALLÉ correctement" _IS_PKG_INSTALLED _PKG_INSTALL "${prerequisit[@]}"
}

########################################################################################################################

END() {
    local duration file
    _SECTION " Finalisation de ${SCRIPTNAME} " "━" "${C_GREEN}"
    _LOG "*** fin ***"
    _RUNSILENT "" sudo rm -fv "${SUDOTMP}"
    duration=$(_CONVERT_SECONDS "$(( SECONDS - START ))")
    _OK "${SCRIPTNAME} v${VER} a terminé avec succès en ${duration}."
    _OK "REDÉMARREZ pour appliquer les modifications éventuelles totalement"

    # LOG
    _OK "Fichier log de la post-installation : ${LOG_FILE}"
    _EXIST curl || _RUNSILENT "" _PKG_INSTALL curl
    local url
    url="https://temp.sh/upload"
    file=$(curl -F file=@"${LOG_FILE}" "${url}" 2>/dev/null)
    [[ -n "${file}" ]] &&  _INFO "Log téléversé : ${file}"
    #
    echo ""
}

########################################################################################################################

INSTALL_FLATPAK_PACKAGES() {
    _SECTION " Installation des paquets Flatpak personnalisés " "━" "${C_GREEN}"
    _LOG "*** paquets flatpak ***"
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
        _LOG "Dépot flathub déjà présent"
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
    _MANAGE_TABLE "INSTALLÉ correctement" _IS_FPPKG_INSTALLED _FPPKG_INSTALL "${FLATPAK_PKGS[@]}"

    # 6. Petit nettoyage des runtimes inutilisés
    _LOG "Nettoyage des runtimes Flatpak orphelins"
    _RUNSILENT "" sudo flatpak --verbose uninstall --unused -y
}

########################################################################################################################

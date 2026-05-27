#!/usr/bin/env bash
# shellcheck disable=SC2310
set -euo pipefail
readonly VERSION=39.4

# basename sans l'extension .sh
SCRIPTNAME="${0##*/}" ; SCRIPTNAME="${SCRIPTNAME%.sh}" ; readonly SCRIPTNAME
# gestion des interruptions
trap '_CLEANUP' ERR
trap '_INTERRUPT' INT
trap '_DO_CLEAN' EXIT
# shellcheck source=./helpers.sh
source ./helpers.sh
# shellcheck source=./settings.sh
source ./settings.sh
if [[ "${NOSWAP,,}" = "yes" ]]; then
    ZSWAP="no"
fi

# suffix des sauvegardes de fichiers
_BAKSUFFIX(){
    date +%d_%m_%Y-%H.%M.%S
}

# ─── MAIN ────────────────────────────────────────────────────────────────────────────────────────────────────────────
MAIN() {
    args=${1:-}
    _ENABLE_COLORS
    CHECK
    INITIALIZE
    # shellcheck disable=SC2154
    if [[ "${args}" = "--shellonly" ]] || [[ "${args}" = "-s" ]] || [[ "${ROOT,,}" = "yes" ]]; then
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
    _RUN "Mise à jour du système" _SYS_UPDATE
    SETUP_SUDO_RS
    # remove/install
    REMOVE_SYSTEM_PACKAGES
    INSTALL_REPOS
    INSTALL_SYSTEM_PACKAGES
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
    SETUP_SWAP_BACKEND_FOR_ZSWAP
    SETUP_SSHD
    SETUP_FSTAB
    SETUP_CACHYOS_KERNEL
    SETUP_GRUB
    SETUP_KDE_PLASMA
    SETUP_PLM
    SETUP_DATA
}

########################################################################################################################
SHELLONLYMODE() {
    echo ""
    _BANNER "red" "Mode shellonly (git, shell, dotfiles)"
    INSTALL_GIT_REPOS
    SETUP_SHELL
    SETUP_DOTFILES
}

########################################################################################################################
CHECKMODE() {
    _SECTION " Mode contrôle - paramètres personnalisables de ${SCRIPTNAME} ✅ " "━" "${C_GREEN}"
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
    _DO_CLEAN
    exit 0
}

########################################################################################################################
HELPMODE() {
    _SECTION " Mode aide 🛟 " "━" "${C_GREEN}"
    _INFO "Usage : ./${SCRIPTNAME} [ --shellonly | --check | --help ]"
    _INFO "Sans option, ${SCRIPTNAME} éxécute la post-installation complète."
    _INFO "Les paramètres personnalisables sont stockés dans ./settings.sh."
    _DO_CLEAN
    exit 0
}

########################################################################################################################
INITIALIZE() {
    if [[ "${ROOT,,}" = "no" ]]; then
        cat <<'EOF'

    Précautions d'usage importantes :
        - Les choix utilisateurs sont à ajuster dans le fichier ./settings.sh
        - Ce script va créer ou modifier des fichiers de configuration du système
        - Ce script ne permet pas un retour en arrière automatique si vous changez d'avis
        - Ce script sauvegarde les fichiers qu'ils modifient sur le système (.origin et .bak)
        - Ce script liste tous les fichiers système crées ou modifiés
        - Ce script est idempotent : si on le relance il ne refait que ce qui est nécessaire

EOF

        read -r -p "On continue ? [o/N] " reponse
        case "${reponse,,}" in
            o|oui|y|yes) ;;
            *) exit 127 ;;
        esac
    fi
    #
    local heure
    heure=$(date '+%T')
    local logsuffix
    START=${SECONDS}
    _PASS
    # LOG
    LOG_DIR="${HOME}/.local/log"
    logsuffix="$(date +%d_%m_%Y-%H.%M.%S)"
    LOG_FILE="${LOG_DIR}/${SCRIPTNAME}-${logsuffix}.log"
    export LOG_DIR LOG_FILE
    mkdir -p "${LOG_DIR}" ; true > "${LOG_FILE}"
    #

    # FICHIERS TEMPORAIRES
    declare -g STATUSFILE LINKFILE
    STATUSFILE=$(mktemp /tmp/status.XXXXXX)
    LINKFILE=$(mktemp /tmp/link.XXXXXX)
    export STATUSFILE LINKFILE
    #

    _CLEAR
    local pretty_name="inconnue"
    local fileOS="/etc/os-release"
    if [[ -f "${fileOS}" ]] || [[ -L "${fileOS}" ]]; then
        pretty_name=$(awk -F= '/^PRETTY_NAME/{gsub(/"/, "", $2); print $2; exit}' "${fileOS}")
    fi
    local color
    if [[ "${ROOT,,}" = "yes" ]]; then
        color=${C_RED}
        _BANNER "red" "${SCRIPTNAME} (${VERSION}) 🖥"
    else
        color=${C_GREEN}
        _BANNER "blue" "${SCRIPTNAME} (${VERSION}) 🖥"
    fi
    _SECTION " Préparation de la post-installation 🚀 " "━" "${color}"
    _INFO "Distribution : ${pretty_name}"
    _INFO "Heure de démarrage du script : ${heure}"
    _OK "Fichier log de la post-installation : ${LOG_FILE}"
    printf '%s\n' "Paramètres utilisateur retenus : " >>"${LOG_FILE}"
    tail -n +14 ./settings.sh | grep -E -v '^(#.*shellcheck|export[[:space:]]*|[[:space:]]*#.*shellcheck|[[:space:]]*$)' >> "${LOG_FILE}"
    INSTALL_DEPS

    # RUST
    export RUSTUP_HOME=/opt/rustup
    export CARGO_HOME=/opt/cargo
    # GO
    export GOROOT=/opt/go
    export GOPATH=/opt/go/workspace
    export GOBIN=/opt/go/workspace/bin

    # Dossiers utilisateur requis
    _RUNSILENT "" mkdir -pv "${HOME}/.local/share/zsh" "${HOME}/.local/share/icons/default" "${HOME}/.local/share/color-schemes" "${HOME}/.local/share/themes"
    # Dossiers système requis
    _RUNSILENT "" sudo mkdir -pv /var/tmp/cargo-target "${RUSTUP_HOME}" "${CARGO_HOME}" "${GOPATH}" "${GOBIN}" /usr/local/bin /etc/sudoers.d /etc/udev/rules.d /etc/NetworkManager/conf.d /etc/systemd/resolved.conf.d /etc/sysctl.d/ /etc/brave/policies/managed/
    _RUNSILENT "" sudo chmod -v 777 "${RUSTUP_HOME}" "${CARGO_HOME}" "${GOPATH}" "${GOBIN}" "${GOROOT}" /var/tmp/cargo-target
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
    export PATH="${GOROOT}/bin:${GOBIN}:${CARGO_HOME}/bin:${PATH}"
    #

    # liste des fichiers système crées ou modifiés par le script
    declare -ga ETC_FILES=()

    # liste des fichiers user crées ou modifiés par le script
#    declare -a HOME_FILES=()

}

########################################################################################################################
INSTALL_CARGO_PACKAGES() {
    if [[ -n "${CARGO_PACKAGES[*]}" ]]; then
        _SECTION " Installation des paquets cargo RUST personnalisés 📦 " "━" "${C_GREEN}"

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
        _RUNSILENT "" _SYMLINK "${CARGO_HOME}/bin/cargo" "/usr/local/bin/cargo"
        _RUNSILENT "" _SYMLINK "${CARGO_HOME}/bin/rustup" "/usr/local/bin/rustup"

        # 1. Installation de cargo-binstall sans compilation
        if ! _EXIST cargo-binstall; then
            _RUN "Installation de cargo-binstall" bash -c "curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash"
        else
            _LOG "cargo-binstall (installation de paquets binaires) est déjà installé"
        fi
        _RUNSILENT "" _SYMLINK "${CARGO_HOME}/bin/cargo-binstall" "/usr/local/bin/cargo-binstall"

        # 2. Installation des paquets via Cargo (binstall)
        # declare -g INSTALLED_LIST
        # local cargolist
        # cargolist="/tmp/cargolist$$"
        # _RUNSILENT "" bash -c "cargo install --list 2>/dev/null > ${cargolist}"
        # INSTALLED_LIST=$(cat "${cargolist}" 2>/dev/null || true) # je passe par un fichier /tmp/cargolist pour avoir un spinner
        # export INSTALLED_LIST # variable utilisée par _CARGOPKG_INSTALL

       _MANAGE_TABLE _IS_CARGOPKG_INSTALLED _CARGOPKG_INSTALL "${CARGO_PACKAGES[@]}"
        # rm -f "${cargolist}" 2>/dev/null

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
        #_RUNSILENT "" chmod a+x -v "${HOME}" "${HOME}/.local" "${HOME}/.local/share" "${CARGO_HOME}" "${CARGO_HOME}/bin"
    else
        _LOG "Aucun paquets cargo demandés"
    fi
}

########################################################################################################################
INSTALL_GO_PACKAGES() {
    if [[ -n "${GO_PACKAGES[*]}" ]]; then
        _SECTION " Installation des paquets GO personnalisés 📦 " "━" "${C_GREEN}"

        local pkg current="" latest="" arch="" os="" gofile="" url
        urlGO="https://go.dev/dl/?mode=json"

        if _EXIST go; then
            current="$(go version | awk '{print $3}' || true)"
        fi
        latest="$(curl -fsSL "${urlGO}" | jq -r '.[0].version' || true)"
        arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/' || true)
        os=$(uname | tr '[:upper:]' '[:lower:]' || true)
        gofile="${latest}.${os}-${arch}.tar.gz"

        if [[ "${current}" == "${latest}" ]] && _EXIST go; then
            _LOG "la toolchain GO est à jour (${latest})"
        else
            _RUNSILENT "" curl -LO "https://go.dev/dl/${gofile}"
            _RUN "Installation de la toolchain GO" sudo tar -C /opt -xzf "${gofile}"
            _RUNSILENT "" rm -vf -- "${gofile}"
        fi
        _RUNSILENT "" _SYMLINK "${GOROOT}/bin/go" "/usr/local/bin/go"
        _RUNSILENT "" _SYMLINK "${GOROOT}/bin/gofmt" "/usr/local/bin/gofmt"
        _RUNSILENT "" go telemetry off
        _RUNSILENT "" sudo go telemetry off

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
                _PRINT_LIST "${present_fmt}" | tee -a "${LOG_FILE:-/dev/null}"
            else
                if [[ -n "${present[*]}" ]]; then
                    local present_fmt
                    present_fmt=$(_FORMAT_LIST "${present[@]}")
                    _INFO "Déjà installé : "
                    _PRINT_LIST "${present_fmt}" | tee -a "${LOG_FILE:-/dev/null}"
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
    local repo name target color
    _RUNSILENT "" mkdir -pv "${HOME}/Projects"
    if [[ "${ROOT,,}" = "yes" ]]; then
        color=${C_RED}
    else
        color=${C_GREEN}
    fi
    _SECTION " Installation des dépôts Git personnalisés 🔗 " "━" "${color}"

    for repo in "${GIT_REPOS[@]}" "${DOTFILES_REPO}"; do
        name="${repo##*/}"
        target="${HOME}/Projects/${name}"

        if [[ -d "${target}" ]]; then
            if git -C "${target}" rev-parse --git-dir &>/dev/null; then
                if [[ "${UPDATE_GIT_REPOS}" = "yes" ]]; then
                    _RUN "Mise à jour de ${name}" git -C "${target}" pull --ff-only
                    # installation
                    if [[ "${ROOT,,}" = "no" ]]; then # en mode ROOT, les dépots sont seulements clonés
                        if [[ "${name}" = "fedupdate" ]]; then
                            _RUN "  Installation de ${name}" bash -c "cd ${target}; make install"
                        fi
                        if [[ "${name}" = "backupsystem" ]] || [[ "${name}" = "radiosh" ]]; then
                            _RUN "  Installation de ${name}" bash -c "sudo chmod +x ${target}/${name} ; sudo ln -sf ${target}/${name} /usr/local/bin/${name}"
                        fi
                    fi
                else
                    _INFO "${name} déjà présent et pas de mise à jour demandée"
                fi
            else
                _ERR "${target} existe mais n'est pas un dépôt git, ignoré"
            fi
        else
            _RUN "Téléchargement de ${name}" git clone "${repo}" "${target}"
            # installation
            if [[ "${ROOT,,}" = "no" ]]; then # en mode ROOT, les dépots sont seulements clonés
                if [[ "${name}" = "fedupdate" ]]; then
                    _RUN "  Installation de ${name}" bash -c "cd ${target}; make install"
                fi
                if [[ "${name}" = "backupsystem" ]] || [[ "${name}" = "radiosh" ]]; then
                    _RUN "  Installation de ${name}" bash -c "sudo chmod +x ${target}/${name} ; sudo ln -sf ${target}/${name} /usr/local/bin/${name}"
                fi
            fi
        fi

        if [[ "${repo}" == "${DOTFILES_REPO}" && "${target}" != "${DOTFILES_DIR}" ]]; then
            _RUNSILENT "" _SYMLINK "${target}" "${DOTFILES_DIR}"
        fi
    done
}

########################################################################################################################
SETUP_SHELL() {
    local color
    if [[ "${ROOT,,}" = "yes" ]]; then
        color=${C_RED}
    else
        color=${C_GREEN}
    fi
    _SECTION " Configuration du shell zsh par défaut 🐚 " "━" "${color}"
    # 1- zsh
    local zsh_bin
    if ! _EXIST zsh; then
        _RUNSILENT "" _PKG_INSTALL zsh
    fi
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
            local install_dir="${HOME}/.local/bin"
            local omp_bin="${install_dir}/oh-my-posh"
            mkdir -p "${install_dir}"
            if _EXIST oh-my-posh; then
                local check
                check=$(oh-my-posh notice)
                if [[ -z "${check}" ]]; then
                    _LOG "aucune mise à jour de oh-my-posh dispo"
                else
                    _RUN "Mise à jour de Oh-My-Posh" oh-my-posh upgrade
                fi
            else
                _RUN "Installation du gestionnaire de prompt Oh-My-Posh (${omp_target})" curl -fsSL "${omp_url}" -o "${omp_bin}"
                _RUNSILENT "" chmod 777 -v "${omp_bin}"
                _RUNSILENT "" _SYMLINK "${omp_bin}" "/usr/local/bin/oh-my-posh"
            fi
        fi
    fi
    _INSTALL_USER_CRONTAB

   }

########################################################################################################################
SETUP_DOTFILES() {
    local color
    if [[ "${ROOT,,}" = "yes" ]]; then
        color=${C_RED}
    else
        color=${C_GREEN}
    fi
    _SECTION " Installation des configurations personnalisées de ${USER} (dotfiles) ⚙️ " "━" "${color}"

    if [[ ! -d "${DOTFILES_DIR}" ]]; then
        _ERR "Le dossier ${DOTFILES_DIR} est introuvable. Stow ignoré."
        return
    fi

    # 1- nettoyage avant stow pour éviter erreurs.
    local skel_files=(".bashrc" ".config/Trolltech.conf" ".config/kdeglobals" ".config/plasmashellrc" ".config/plasma-localerc" ".config/kwinrc" ".bash_logout" ".zshenv" ".zshrc" ".config/plasma-org.kde.plasma.desktop-appletsrc" ".config/kactivitymanagerd-statsrc" ".config/kglobalshortcutsrc" ".config/konsolerc" ".config/vesktop/themes/*.css" ".config/user-dirs.dirs" ".config/user-dirs.locale")
    local file dir
    dir="${HOME}/.backup"
    _RUNSILENT "" mkdir -pv "${dir}"
    for file in "${skel_files[@]}"; do
        if [[ -f "${HOME}/${file}" && ! -L "${HOME}/${file}" ]]; then
            _LOG "déplacement de fichiers qui seront remplacés par le dotfiles via stow dans ${dir} : "
            _RUNSILENT "" mv -v "${HOME}/${file}" "${dir}"
        fi
    done

    # 2- stow pour déployer dotfiles depuis dépôt git
    local pkg name listdot=" " displayed_stow
    if [[ "${RESTOW,,}" = "yes" ]]; then
        displayed_stow="Forçage des liens symboliques (restow)"
    else
        displayed_stow="Vérification des liens symboliques, création si besoin (stow)"
    fi
    echo -e " ${C_GREEN}✓ ${C_RESET} ${displayed_stow} :"
    for pkg in "${DOTFILES_DIR}"/*/; do
        name=$(basename "${pkg}")
        listdot="${listdot}${name} "
    done
    _PRINT_LIST "${listdot}" | tee -a "${LOG_FILE:-/dev/null}"
    for pkg in "${DOTFILES_DIR}"/*/; do
        name=$(basename "${pkg}")
        if [[ "${RESTOW,,}" = "yes" ]]; then
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
_SETUP_SYSTEMD() {
    _LOG "* systemd *"

    # Config
    _JOURNALD
    local content file dir
    dir='/etc/systemd'
    file="${dir}/system.conf"
    content=$'[Manager]\nDefaultTimeoutStopSec=30s\n'
    _INSTALL_ETC_FILES "systemd" "${content}" "${file}" "644"
    if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
        _RUN "Redémarrage du démon systemd" sudo systemctl daemon-reexec
    fi

    # Service
    local service
    local description
    local -a missing=()
    local -a present=()


    for service in "${!SERVICES_TO_DISABLE[@]}"; do
        #if _SERVICE_EXIST "${service}"; then
            description="${SERVICES_TO_DISABLE[${service}]}"
            if _IS_ENABLED "${service}"; then
                missing+=("${service}")
            else
                present+=("${service}")
            fi
        #else
            _LOG "Service ${service} introuvable"
        #fi
    done

    local missing_fmt present_fmt
    present_fmt=$(_FORMAT_LIST "${present[@]}")
    if ((${#missing[@]})); then
        missing_fmt=$(_FORMAT_LIST "${missing[@]}")
        if ((${#present[@]})); then
            _LOG "Déjà désactivés : "
            _PRINT_LIST "${present_fmt}" | tee -a "${LOG_FILE:-/dev/null}" >/dev/null
        fi
        _INFO "À désactiver : "
        _PRINT_LIST "${missing_fmt}" | tee -a "${LOG_FILE:-/dev/null}"
        _RUN "Désactivation des services" sudo systemctl disable --now "${missing[@]}"
    else
        _INFO "Services déjà désactivés : "
        _PRINT_LIST "${present_fmt}" | tee -a "${LOG_FILE:-/dev/null}"
    fi

    for service in "${!USER_SERVICES_TO_ENABLE[@]}"; do
        if _USER_SERVICE_EXIST "${service}"; then
            description="${USER_SERVICES_TO_ENABLE[${service}]}"
            if ! _IS_ENABLED_USER "${service}"; then
                _RUN "Activation du ${description}" systemctl --user enable --now "${service}"
            else
                _INFO "${description^} déjà activé"
            fi
        else
            _LOG "Service ${service} introuvable"
        fi
    done
}

########################################################################################################################
SETUP_FSTAB() {
    _SECTION " Configuration du fichier FSTAB ⚙️ " "━" "${C_GREEN}"
    local fstab="/etc/fstab"
    declare -g dr
    dr="no"
    # SWAPFILE
    if [[ "${ZSWAP,,}" = "yes" ]]; then
        local swapdir="/var/swap"
        local swapfile="${swapdir}/swapfile"
        if [[ -f "${swapfile}" ]]; then
            if ! grep -q "${swapfile}" /etc/fstab; then
                if [[ ! -f /etc/fstab.origin ]]; then
                    _RUNSILENT "" sudo cp -av "${fstab}" /etc/fstab.origin
                fi
                local bak
                bak=$(_BAKSUFFIX)
                _RUNSILENT "" sudo cp -av "${fstab}" "/etc/fstab.bak.${bak}"
                _RUN "Ajout du swap" bash -c "echo ${swapdir}/swapfile none swap sw,nofail 0 0 | sudo tee -a ${fstab}"
                _ETC_FILES_ADD "${fstab}"
                dr="yes"
            else
                _INFO "Swap déjà présent dans ${fstab}"
            fi
        fi
    else
        if [[ "${NOSWAP,,}" = "yes" ]]; then
            _DISABLE_SWAP_FSTAB
        fi
        _LOG "Pas de zswap demandé on n'a pas fait de swapfile à ajouter au fstab"
    fi

    # --- Optimisations Fstab (noatime, lazytime) ---
    local fstab_changed=false tmp_dir
    tmp_dir=$(mktemp -d)
    true >"${tmp_dir}/fstab.new" # on crée un fichier vide temporaire
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
        if [[ ! -f /etc/fstab.origin ]]; then
            _RUNSILENT "" sudo cp -av "${fstab}" /etc/fstab.origin
        fi
        local bak
        bak=$(_BAKSUFFIX)
        _RUNSILENT "" sudo cp -av "${fstab}" "/etc/fstab.bak.${bak}"
        _RUN "Optimisations des systèmes de fichier" sudo cp -pv "${tmp_dir}/fstab.new" "${fstab}"
        dr="yes"
        _ETC_FILES_ADD "${fstab}"
    else
        _INFO "Options d'optimisations déjà présentes dans ${fstab}"
    fi

    # NFS
    if [[ "${NFS_SHARE:-}" != "" ]]; then
        local opts
        opts="rw,_netdev,nofail,nodev,nosuid,noexec,noatime,lazytime,x-systemd.automount,x-systemd.mount-timeout=30s"
        if ! grep -q "${NFS_SHARE}" "${fstab}" >/dev/null; then
            if grep -q "${NFS_MP}" "${fstab}" >/dev/null; then
                _INFO "Point de montage demandé (${NFS_MP}) déjà présent dans ${fstab} :"
                grep "${NFS_MP}" "${fstab}"
                _INFO "Abandon de l'installation du partage réseau NFS."
            else
                if [[ ! -f /etc/fstab.origin ]]; then
                    _RUNSILENT "" sudo cp -av "${fstab}" /etc/fstab.origin
                fi
                local bak
                bak=$(_BAKSUFFIX)
                _RUNSILENT "" sudo cp -av "${fstab}" /etc/fstab.bak."${bak}"

                _RUNSILENT "" sudo mkdir -pv "${NFS_MP}"
                echo "${NFS_SHARE}   ${NFS_MP}   nfs   ${opts}      0 0" | sudo tee -a "${fstab}" >/dev/null
                _ETC_FILES_ADD "${fstab}"
                dr="yes"
                _RUN "Montage du partage réseau NFS" bash -c "sudo mount -v \"${NFS_MP}\" && sudo ls -l \"${NFS_MP}\""
            fi
        else
            _INFO "Montage NFS déjà OK"
        fi
    else
        _LOG "Aucun montage NFS demandé"
    fi

    if [[ "${dr,,}" = "yes" ]]; then
        _RUNSILENT "" sudo systemctl daemon-reload
    fi

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

    # Nettoyage
    _RUNSILENT "" sudo rm -rvf -- "${tmp_dir}"
}

######################################################################################################################
SETUP_DATA() {
    _SECTION " Restauration des données privées de l'utilisateur ${USER} 🛢️ " "━" "${C_GREEN}"
    if [[ -e "${SOURCE}" ]]; then
        if ! _IS_PKG_INSTALLED xdg-user-dirs ; then
            _RUNSILENT "" _PKG_INSTALL xdg-user-dirs
        fi

        if [[ ${#DESTINATIONS[@]} -gt 0 ]]; then
            local profil file cmd ffile
            for profil in "${!DESTINATIONS[@]}"; do
                cmd=${COMMANDS["${profil}"]:-}
                # on récupère la sauvegarde la plus récente dans le dossier SOURCE pour le profil ${profil}
                file=$(find "${SOURCE}" -maxdepth 1 -name "${profil}_*.tar.gz" -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2- || true)
                if [[ -n "${cmd}" ]] && pgrep -x "${cmd}" >/dev/null; then
                    _ERR "Ferme ${cmd} d'abord !"
                else
                    if [[ -n "${file}" ]]; then
                        if _DIR_IS_SAFE_TO_RESTORE "${DESTINATIONS[${profil}]}"; then
                            ffile=$(basename "${file}")
                            _RUN "Restauration de ${profil} (de ${ffile} vers ${HOME})" tar -xzf "${file}" -C "${HOME}"
                            if [[ "${profil,,}" = "discord" ]]; then
                                rm -rf -- "${HOME}/.config/vesktop/themes"
                                if [[ "${RESTOW,,}" = "yes" ]]; then
                                    stow -v1 --dir="${DOTFILES_DIR}" --target="${HOME}" --restow "vesktop" &>>"${LOG_FILE}"
                                else
                                    stow -v1 --dir="${DOTFILES_DIR}" --target="${HOME}" "vesktop" &>>"${LOG_FILE}"
                                fi
                            fi
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
        _SECTION " Personnalisation de l'interface KDE Plasma 6 de l'utilisateur ${USER} 🛠️ " "━" "${C_GREEN}"
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
        local c colorok="no"
        local -a tela_colors=(standard black blue brown green grey orange pink purple red yellow manjaro ubuntu nord dracula)

        for c in "${tela_colors[@]}"; do
            if [[ "${c}" = "${VARIANT_COLOR_TELA_ICONS,,:-}" ]]; then
                colorok="yes"
                break
            fi
        done
        if [[ "${colorok}" = "no" ]]; then
            _LOG "couleur TELA inconnue (${VARIANT_COLOR_TELA_ICONS}), fallback sur 'standard'"
            VARIANT_COLOR_TELA_ICONS="standard"
        fi

        local testcolor
        if [[ "${VARIANT_COLOR_TELA_ICONS}" = "standard"  ]]; then
            testcolor=""
        else
            testcolor="-${VARIANT_COLOR_TELA_ICONS}"
        fi

        local temp_tela
        if [[ ! -d "${HOME}/.local/share/icons/Tela${testcolor}" ]] && [[ ! -d "${HOME}/.local/share/icons/Tela${testcolor}-dark" ]] && [[ ! -d "${HOME}/.local/share/icons/Tela${testcolor}-light" ]]; then
            temp_tela=$(mktemp -d)
            _RUN "Téléchargement des icônes Tela" git clone --depth=1 https://github.com/vinceliuice/Tela-icon-theme.git "${temp_tela}/tela"
            _RUN "Installation des icônes Tela ${VARIANT_COLOR_TELA_ICONS} (dans ${HOME}/.local/share/icons/)" bash -c "\"${temp_tela}\"/tela/install.sh -c \"${VARIANT_COLOR_TELA_ICONS}\" -d \"${HOME}\"/.local/share/icons"
            _RUNSILENT "" rm -rfv -- "${temp_tela}"
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
            top)    display_pos="haute" ;;
            right)  display_pos="droite" ;;
            left)   display_pos="gauche" ;;
            *)      display_pos="basse" ;;
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
        if [[ ! -f /var/lib/AccountsService/icons/"${USER}" ]] && [[ -f "${avatar}" ]]; then
            _RUN "Avatar pour ${USER} (${avatar##*/})" sudo cp -v "${avatar}" /var/lib/AccountsService/icons/"${USER}"
        fi
        # on redémarre l'interface pour appliquer de suite.
        if pgrep plasmashell >/dev/null 2>&1; then
            if [[ "${change}" -eq 1 ]]; then
                _RUN "Redémarrage de l'interface de KDE Plasma 6" bash -c "\
                kwriteconfig6 --file kdeglobals --group Icons --key Theme Tela-${VARIANT_COLOR_TELA_ICONS}-dark ;\
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
        echo ""
        _INFO "KDE Plasma non détecté, pas de personnalisation"
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
        _LOG "KDE Plasma non détecté, pas de changement du login-manager"
    fi
}

########################################################################################################################

_PLYMOUTH(){
    if [[ "${DISABLE_PLYMOUTH,,}" = "yes" ]]; then
        local dir file content
        dir="/etc/dracut.conf.d"
        file="${dir}/90-omit-plymouth.conf"
        content=$'omit_dracutmodules+=" plymouth "\n'

        _RUNSILENT "" sudo mkdir -pv "${dir}"
        _INSTALL_ETC_FILES "dracut sans plymouth" "${content}" "${file}" "644"
    fi
}

########################################################################################################################
SETUP_ETC() {
    _SECTION " Configuration générale du système ⚙️ " "━" "${C_GREEN}"
    _MSMTP
    _HOSTNAME
    _NETWORKMANAGER
    _SYSTEMD_RESOLVED
    _PLYMOUTH
    _KERNEL
    _DISABLE_COREDUMP
    _BRAVEPOLICIES
    _IOSCHEDULER
    _UDEVPERSIST
    _DISABLE_IPV6_IN_SERVICES
    _SETUP_ENV_DEV
    _HARDENING
    _SETUP_SYSTEMD
    _SETUP_FIREWALL
    _DISABLE_FPRINTD
    _LIBVIRT
    if [[ "${RESTARTSYSTEMDRESOLVED}" = "yes" ]]; then
        _RUNSILENT "Redémarrage du service systemd-resolved" sudo systemctl restart systemd-resolved.service
    fi
    if [[ "${RESTARTNM}" = "yes" ]]; then
        _RUNSILENT "Redémarrage du service NetworkManager" sudo systemctl restart NetworkManager.service
    fi
}

########################################################################################################################
SETUP_SSHD() {
    local sshservice
    sshservice="sshd.service"
    if [[ "${ACTIVATE_SSHD}" = "yes" ]]; then
        _SECTION " Configuration du service ssh 🔑 " "━" "${C_GREEN}"
        _RUNSILENT "" sudo mkdir -pv /etc/ssh/sshd_config.d
        local config_ssh_file full_ssh_content ssh_header ssh_config noipv6="" banner=""

        config_ssh_file="/etc/ssh/sshd_config.d/90-jotenakis.conf"
        ssh_header="# =======================================================================
# WARNING: Do not modify this file!
# It is automatically generated and managed by ${SCRIPTNAME}.
#
# To override these settings, create a new drop-in file with a
# higher priority number (e.g., /etc/ssh/sshd_config.d/99-custom.conf).
# ======================================================================="
        ssh_config='Protocol 2
LogLevel VERBOSE
UseDNS  no
AuthorizedKeysFile      .ssh/authorized_keys
LoginGraceTime 2m
PermitEmptyPasswords no
PasswordAuthentication yes
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
#AuthenticationMethods publickey
UsePAM no
PermitRootLogin no
MaxAuthTries 3
MaxSessions 2
MaxStartups 5:10:30
ClientAliveInterval 300
ClientAliveCountMax 2
AllowTcpForwarding no
AllowAgentForwarding no
TCPKeepAlive no
PrintMotd no
PrintLastLog yes
Subsystem sftp internal-sftp
'
        if [[ ${DISABLE_IPV6,,} = "yes" ]]; then
            noipv6='AddressFamily inet
ListenAddress 0.0.0.0
'
        fi
        if [[ ${HARDENING,,} = "yes" ]]; then
            banner='Banner /etc/issue.d/ssh.issue'
        fi
        readonly ssh_header sshservice config_ssh_file ssh_config

        # on concatène la conf
        full_ssh_content="${ssh_header}
Port ${SSHD_CONFIG_PORT:-22}
# config robuste
${ssh_config}
# only ipv4
${noipv6}
# bannière sécu
${banner}
"

        # Configuration (/etc/ssh/sshd_config remplacé par le drop_in et symlink)
        _INSTALL_ETC_FILES "sshd" "${full_ssh_content}" "${config_ssh_file}" "600"
        if sudo test -L /etc/ssh/sshd_config; then
            _RUNSILENT "" sudo rm -fv /etc/ssh/sshd_config
        fi
        printf '%s\n' "Include /etc/ssh/sshd_config.d/*.conf" | sudo tee "/etc/ssh/sshd_config" > /dev/null
        # Autorisation
        _SSHUSERAUTH
        # Banière
        _SSHBANNER
        # service systemd
        _SSHSYSTEMD
        if [[ "${HARDENING,,}" = "yes" ]]; then
            _SSHFAIL2BAN
        fi

    else
        if _IS_ENABLED "${sshservice}"; then
            _SECTION " Configuration du service ssh 🔑 " "━" "${C_GREEN}"
            _LOG "pas de service sshd demandé"
            _RUN "Désactivation de ${sshservice}" sudo systemctl --now disable "${sshservice}" sshd.socket ssh.service ssh.socket
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
#
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
        _LOG "Fond d'écran custo pour PLM introuvable : ${src}"
    fi
}

########################################################################################################################

INSTALL_DEPS() {
    local -a prerequisit=(zsh gawk curl ncurses git stow pciutils dnf-plugins-core binutils policycoreutils-python-utils)
    _MANAGE_TABLE _IS_PKG_INSTALLED _PKG_INSTALL "${prerequisit[@]}"
}

########################################################################################################################

INSTALL_FLATPAK_PACKAGES() {
    if [[ -n "${FLATPAK_PKGS[*]}" ]]; then
        _SECTION " Installation des paquets Flatpak personnalisés 📦 " "━" "${C_GREEN}"
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

        # 5bis flatpak update
        _LOG "Mise à jour des flatpak"
        _RUNSILENT "" flatpak update -y

        # 6. Petit nettoyage des runtimes inutilisés
        _LOG "Nettoyage des runtimes Flatpak orphelins"
        _RUNSILENT "" flatpak uninstall --unused -y
    else
        _LOG "Aucun paquet Flatpak demandé"
    fi
}

########################################################################################################################

END() {
    local duration file color
    if [[ "${ROOT,,}" = "yes" ]]; then
        color=${C_RED}
    else
        color=${C_GREEN}
    fi
    _SECTION " Finalisation de la post-installation 🏁 " "━" "${color}"
    duration=$(_CONVERT_SECONDS "$((SECONDS - START))")
    _INFO "${SCRIPTNAME} v${VERSION} a terminé avec succès en ${duration}."
    if [[ -n "${ETC_FILES[*]}" ]]; then
        _PRINT_ETC_FILES
        _INFO "REDÉMARREZ pour appliquer les modifications complètement !"
    else
        _INFO "Aucun fichier système crée ou modifié"
        _INFO "Il est plus prudent néanmoins de redémarrer"
    fi

    # LOG
    _INFO "Fichier log de la post-installation : ${LOG_FILE}"
    if ! _EXIST curl; then
        _RUNSILENT "" _PKG_INSTALL curl
    fi
    local url
    url="https://temp.sh/upload"
    file=$(curl -F file=@"${LOG_FILE}" "${url}" 2>/dev/null)
    if [[ -n "${file}" ]]; then
        _OK "Log téléversé : ${file}"
    fi
    #
    echo ""
}

########################################################################################################################

_JOURNALD() {
    local journald_content journald_file dir
    dir="/etc/systemd"
    journald_file="${dir}/journald.conf"
    _RUNSILENT "" sudo mkdir -pv "${dir}"
    journald_content=$'[Journal]\nSystemMaxUse=500M\nSystemKeepFree=1G\n'
    readonly journald_file journald_content
    _LOG "* journald *"
    _INSTALL_ETC_FILES "journal système" "${journald_content}" "${journald_file}" "644"
    if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
        _RUNSILENT "" sudo systemctl restart systemd-journald
    fi

}

########################################################################################################################

_HOSTNAME() {
    local currenthost newhost
    currenthost=$(hostnamectl --static)
    _LOG "* nom d'hôte *"
    if [[ -n "${MYHOSTNAME}" ]] && [[ "${currenthost}" != "${MYHOSTNAME}" ]]; then
        _RUN "Configuration nom de la machine (${MYHOSTNAME})" sudo hostnamectl set-hostname "${MYHOSTNAME}"
        newhost=$(hostnamectl hostname)
        _LOG "nouveau hostname : ${newhost}"
        _ETC_FILES_ADD "/etc/hostname"
    else
        _LOG "hostname déjà correctement défini"
    fi
    # on ajoute à /etc/hosts
    hosts=/etc/hosts
    if [[ ! -f "${hosts}" ]]; then
        sudo touch "${hosts}"
    fi
    if ! grep -Eq "[[:space:]]${MYHOSTNAME}([[:space:]]|\$)" "${hosts}"; then
        printf '127.0.1.1\t%s\n' "${MYHOSTNAME}" | sudo tee -a "${hosts}" >/dev/null
        _OK "Configuration de la résolution locale (${hosts})"
        _ETC_FILES_ADD "${hosts}"
    else
        _INFO "Résolution locale déjà OK (${hosts})"
    fi
}

########################################################################################################################

_MSMTP() {
    # par défaut msmtp ne crée pas le log system !
    if _IN_ARRAY "msmtp" "${SYSTEM_PACKAGES[@]}"; then
        if [[ ! -f /var/log/msmtp.log ]]; then
            _LOG "config log msmtp car paquet présent"
            sudo touch /var/log/msmtp.log
            _RUNSILENT "" bash -c "sudo chmod -v 600 /var/log/msmtp.log >>${LOG_FILE}"
            _ETC_FILES_ADD "/var/log/msmtp.log"
        fi
    fi
}

########################################################################################################################

_NETWORKMANAGER() {
    local nm_dns_conf file dir
    nm_dns_conf=$'[main]\ndns=systemd-resolved\n'
    dir="/etc/NetworkManager/conf.d"
    file="${dir}/90-global-dns.conf"
    readonly nm_dns_conf file dir
    declare -g RESTARTNM="no"
    _LOG "* dns : NetworkManager *"

    _INSTALL_ETC_FILES "backend DNS de NetworkManager" "${nm_dns_conf}" "${file}" "644"
    if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
        RESTARTNM="yes"
    fi
    {
        ls -l "${file}"
        cat "${file}"
        echo ""
    } >>"${LOG_FILE}"

    if [[ "${WIFI_POWERSAVE,,}" = "yes" ]]; then
        local nm_wifipowersave file2
        nm_wifipowersave=$'[connection]\nwifi.powersave = 2\n'
        file2="${dir}/90-wifi-powersave.conf"
        readonly nm_wifipowersave file2

        _INSTALL_ETC_FILES "wifi powersave" "${nm_wifipowersave}" "${file2}" "644"
        if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
            RESTARTNM="yes"
        fi
        {
        ls -l "${file2}"
        cat "${file2}"
        echo ""
        } >>"${LOG_FILE}"
    fi

}

########################################################################################################################

_SYSTEMD_RESOLVED() {
    local resolved_10_conf dnsfile llmnrfile dir
    dir="/etc/systemd/resolved.conf.d"
    dnsfile="${dir}/90-dns_servers.conf"
    llmnrfile="${dir}/10-disable-llmnr.conf"
    resolved_10_conf=$'[Resolve]\nLLMNR=no\n'
    readonly resolved_10_conf dir dnsfile llmnrfile
    declare -g RESTARTSYSTEMDRESOLVED="no"
    _LOG "* dns : systemd-resolved *"
    _RUNSILENT "" _SYMLINK "../run/systemd/resolve/stub-resolv.conf" "/etc/resolv.conf"

    if [[ ! -f "${dnsfile}" ]] || [[ ! -f "${llmnrfile}" ]]; then
        _OK "Configuration serveurs DNS (dans ${dir})"
        printf '%s' "${RESOLVED_DNS_SERVERS}" | sudo tee "${dnsfile}" >/dev/null
        printf '%s' "${resolved_10_conf}" | sudo tee "${llmnrfile}" >/dev/null
        _RUNSILENT "" bash -c "sudo chmod -v 644 ${dnsfile} ${llmnrfile} >>${LOG_FILE}"
        RESTARTSYSTEMDRESOLVED="yes"
        #_RUNSILENT "Redémarrage du service systemd-resolved" sudo systemctl restart systemd-resolved.service
        _ETC_FILES_ADD "${dnsfile}"
        _ETC_FILES_ADD "${llmnrfile}"
    else
        _INFO "Configuration DNS déjà OK (dans ${dir})"
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
    local sysctlfile sysctl_header full_sysctl_content nodump="" harden="" swappiness=""
    sysctlfile="/etc/sysctl.d/90-jotenakis.conf"
    if [[ "${DISABLE_COREDUMP,,}" = "yes" ]]; then
        nodump=$'# no dump\nfs.suid_dumpable=0\nkernel.core_pattern=|/bin/false\n'
    fi
    if [[ "${HARDENING,,}" = "yes" ]]; then
        harden='# hardening
kernel.kptr_restrict = 2
kernel.printk = 3 3 3 3
dev.tty.ldisc_autoload = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
kernel.core_uses_pid = 1
kernel.ctrl-alt-del = 0
kernel.perf_event_paranoid = 4
kernel.randomize_va_space = 2
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
kernel.yama.ptrace_scope = 3
kernel.dmesg_restrict = 1
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
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.conf.default.rp_filter = 1
'
    fi
    swappiness=$(_GET_SWAPPINESS)
    local forward
    forward="net.ipv4.ip_forward = 0"
    if _IS_PKG_INSTALLED qemu; then
        forward="net.ipv4.ip_forward = 1"
    fi

    sysctl_header="# =======================================================================
# WARNING: Do not modify this file!
# It is automatically generated and managed by ${SCRIPTNAME}.
#
# To override these settings, create a new drop-in file with a
# higher priority number (e.g., /etc/sysctl.d/99-custom.conf).
# ======================================================================="
    readonly sysctlfile sysctl_header
    full_sysctl_content="${sysctl_header}

# swappiness computed by post-install script by Jotenakis based on RAM/ZRAM/ZSWAP
vm.swappiness = ${swappiness}

${SYSCTL_CONF}
${nodump}
${harden}

# routage
${forward}
"

    _LOG "* sysctl *"
    _INSTALL_ETC_FILES "noyau" "${full_sysctl_content}" "${sysctlfile}" "644"
    if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
        _RUNSILENT "" sudo sysctl -p "${sysctlfile}"
    fi

    # chargement anticipé de bbr et fq
    local qdisc congestion file dir content initramfsrebuild="dracut"
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)

    if [[ "${qdisc}" = "fq" ]] || [[ "${congestion}" = "bbr" ]]; then
        dir="/etc/modules-load.d"
        file="${dir}/net.conf"
        content=$'tcp_bbr\nsch_fq\n'
        _INSTALL_ETC_FILES "modules tcp_bbr et sch_fq" "${content}" "${file}" "644"
        if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
            # shellcheck disable=SC2248
            _RUN "Configuration initramfs" sudo ${initramfsrebuild} -fv --regenerate-all
        fi

    fi

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
    local rules_file rules_content dir
    dir="/etc/udev/rules.d"
    _RUNSILENT "" sudo mkdir -pv "${dir}"
    rules_file="${dir}/60-ioschedulers.rules"
    rules_content=$'ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"\nACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"\nACTION=="add|change", KERNEL=="mmcblk[0-9]", ATTR{queue/scheduler}="mq-deadline"\nACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"\n'
    _LOG "* IO scheduler *"
    _INSTALL_ETC_FILES "règles d'ordonnancement des E/S" "${rules_content}" "${rules_file}" "644"
    if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
        _RUNSILENT "" sudo udevadm control --reload-rules
        _RUNSILENT "" sudo udevadm trigger
    fi
}

########################################################################################################################

_UDEVPERSIST() {
    # --- udev static custom rule, eg usb key
    _LOG "* udev persist custom *"
    if [[ -n "${UDEVRULE}" ]]; then
        local udevfilename rules_file
        udevfilename="99-persist-key.rules"
        rules_file="/etc/udev/rules.d/${udevfilename}"

        _INSTALL_ETC_FILES "règle udev persistante (${UDEVDESCR})" "${UDEVRULE}" "${rules_file}" "644"
        if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
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

    if getent group libvirt >/dev/null 2>&1; then # libvirt existe
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

_DISABLE_IPV6_IN_SERVICES() {
    if [[ "${DISABLE_IPV6,,}" = "yes" ]]; then
        _LOG "désactivation IPV6 dans les services"

        # Chrony
        local chrony_file chrony_content dir
        dir="/etc/sysconfig"
        _RUNSILENT "" sudo mkdir -pv "${dir}"
        chrony_file="${dir}/chronyd"
        chrony_content=$'# Command-line options for chronyd\nOPTIONS="-F 2 -4"\n'
        readonly chrony_file chrony_content

        if _IS_PKG_INSTALLED chrony; then
            _INSTALL_ETC_FILES "IPv6 chronyd" "${chrony_content}" "${chrony_file}" "644"
            if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
                _RUNSILENT "" sudo systemctl try-restart chronyd
                _LOG "IPv6 désactivé pour chrony"
                cat "${chrony_file}" >> "${LOG_FILE}"
            fi
        else
            _LOG "Chrony n'est pas installé"
        fi

        # /etc/hosts
        local hostsfile="/etc/hosts"
        if grep -qE '^\s*(::1|fe80::[^[:space:]]*)' "${hostsfile}"; then
            if [[ ! -e "${hostsfile}.origin" ]]; then
                _RUNSILENT "" sudo cp -av "${hostsfile}" "${hostsfile}.origin"
            fi
            _RUNSILENT "" sudo cp -fav "${hostsfile}" "${hostsfile}.bak"
            _RUN "Configuration IPv6 de l'hôte (${hostsfile})" sudo sed -i -E '/^\s*(::1|fe80::[^[:space:]]*)/d' "${hostsfile}"
            _LOG "Entrées IPv6 supprimées de ${hostsfile} (backup: ${hostsfile}.bak et ${hostsfile}.origin)"
            cat "${hostsfile}" >> "${LOG_FILE}"
            _ETC_FILES_ADD "${hostsfile}"
        else
            _INFO "Entrée IPv6 dans ${hostsfile} déjà supprimée"
        fi

        # avahi
        local avahi_conf
        avahi_conf="/etc/avahi/avahi-daemon.conf"
        if grep -qE '^\s*use-ipv6\s*=\s*no' "${avahi_conf}"; then
            _INFO "IPv6 avahi-daemon déjà OK (${avahi_conf})"
        else
            if [[ ! -e "${avahi_conf}.origin" ]]; then
                _RUNSILENT "" sudo cp -av "${avahi_conf}" "${avahi_conf}.origin"
            fi
            _RUNSILENT "" sudo cp -fav "${avahi_conf}" "${avahi_conf}.bak"
            if grep -qE '^\s*use-ipv6\s*=' "${avahi_conf}"; then
                # La clé existe avec une autre valeur → on la remplace
                _RUN "Configuration IPv6 avahi-daemon (${avahi_conf})" sudo sed -i -E 's/^\s*use-ipv6\s*=.*/use-ipv6=no/' "${avahi_conf}"
            else
                # La clé est absente → on l'injecte sous [server]
                _RUN "Configuration IPv6 avahi-daemon (${avahi_conf})" sudo sed -i -E '/^\[server\]/a use-ipv6=no' "${avahi_conf}"
            fi
            _LOG "IPv6 désactivé pour ${avahi_conf} (backup: ${avahi_conf}.bak et ${avahi_conf}.origin)"
            grep use-ipv6 "${avahi_conf}" >> "${LOG_FILE}"
            _ETC_FILES_ADD "${avahi_conf}"
        fi

        # NetworkManager
        if _IS_ENABLED NetworkManager.service; then
            local uuid type current
            if _EXIST nmcli; then
                sudo nmcli -t -f UUID,TYPE connection show | while IFS=: read -r uuid type; do
                    if [[ "${type}" = loopback ]]; then continue; fi
                    current=$(sudo nmcli -g ipv6.method connection show "${uuid}" 2>/dev/null || true)
                    if [[ "${current}" = disabled ]]; then
                        _LOG "IPv6 pour la connection NetworkManager ${uuid}:${type} déjà désactivée"
                        continue
                    fi
                    sudo nmcli connection modify "${uuid}" ipv6.method disabled
                    _OK "Désactivation IPv6 pour la connection NetworkManager ${uuid}:${type}"
                done
            else
                _LOG "nmcli non détecté"
            fi
        else
            _LOG "NetworkManager non détecté, on zappe désactivation IPv6 pour NetworkManager"
        fi
        # Netconfig
        _DISABLE_IPV6_NETCONFIG

    else
        _LOG "IPv6 est conservé à la demande de l'utilisateur"
    fi
}

########################################################################################################################

_DISABLE_IPV6_NETCONFIG() {
    local file="/etc/netconfig"

    if ! sudo test -f "${file}"; then
        _LOG "${file} n'existe pas"
    else
        if ! sudo grep -q "^udp6\\|^tcp6" "${file}"; then
            _LOG "aucune entrée IPv6 détectée dans ${file}"
            cat "${file}" >> "${LOG_FILE}"
            _INFO "Configuration IPv6 netconfig déjà OK (${file})"
        else
            sudo sed -i -E 's/^(udp6|tcp6)/#\1/' "${file}"
            _OK "Configuration IPv6 netconfig (${file})"
            _ETC_FILES_ADD "${file}"
        fi
    fi

}

########################################################################################################################

_DISABLE_COREDUMP(){
    if [[ "${DISABLE_COREDUMP,,}" = "yes" ]]; then
        local file content dir limits_file dirlimits dirprofile profile
        dir="/etc/systemd/coredump.conf.d"
        dirlimits="/etc/security/limits.d"
        dirprofile="/etc/profile.d"
        sudo mkdir -p "${dir}" "${dirlimits}" "${dirprofile}"

        _LOG "* coredump disable *"

        # security limits
        limits_file="${dirlimits}/disable-coredump.conf"
        if ! grep -qxF "* soft core 0" "${limits_file}" 2>/dev/null; then
            printf '* soft core 0\n* hard core 0\n' | sudo tee "${limits_file}" > /dev/null
            _OK "Configuration coredump (${limits_file})"
            _ETC_FILES_ADD "${limits_file}"
        else
            _INFO "Coredump déja OK (${limits_file})"
        fi
        { ls -l "${limits_file}" ; cat "${limits_file}" ; echo "" ; } >> "${LOG_FILE}"

        # systemd
        file="${dir}/disable.conf"
        content=$'[Coredump]\nStorage=none\nProcessSizeMax=0\n'
        _INSTALL_ETC_FILES "coredump systemd" "${content}" "${file}" "644"
        if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
            _RUNSILENT "" sudo systemctl daemon-reload
        fi
        { ls -l "${file}" ; cat "${file}" ; echo "" ; } >> "${LOG_FILE}"


        # shell
        profile="${dirprofile}/coredump.sh"
        content=$'ulimit -c 0\n'
        _INSTALL_ETC_FILES "coredump shell" "${content}" "${profile}" "644"
        { ls -l "${profile}" ; cat "${profile}" ; echo "" ; } >> "${LOG_FILE}"
    else
        _LOG "Les coredumps ne sont pas désactivés, à la demande de l'utilisateur."
    fi

}

########################################################################################################################

_INSTALL_USER_CRONTAB(){ # sheldon update/ tldr update
    local cron_job1 cron_job2
    _LOG "* crontab ${USER} *"
    if ! _EXIST crontab; then
        _RUNSILENT "" _PKG_INSTALL cronie
    fi
    if _EXIST sheldon; then
        cron_job1='0 21 * * * sheldon lock --update >/tmp/sheldon_update.log 2>&1'
        if ! crontab -l 2>/dev/null | grep -qF "sheldon lock --update"; then
            _RUN "Tâche cron \"sheldon update\" ajoutée pour ${USER}" bash -c "( crontab -l 2>/dev/null; echo \"${cron_job1}\" ) | crontab -"
        else
            _INFO "Tâche cron \"sheldon update\" déjà là pour ${USER}"
        fi
    fi
    if _EXIST tldr; then
        cron_job2='5 */4 * * * tldr -u >/tmp/tldr_update.log 2>&1'
        if ! crontab -l 2>/dev/null | grep -qF "tldr -u"; then
            _RUN "Tâche cron \"tldr update\" ajoutée pour ${USER}" bash -c "( crontab -l 2>/dev/null; echo \"${cron_job2}\" ) | crontab -"
        else
            _INFO "Tâche cron \"tldr update\" déjà là pour ${USER}"
        fi
    fi
    _RUNSILENT "" crontab -l
}

########################################################################################################################

_DO_CLEAN(){
    local f
    tput cvvis || true # Show cursor, ignore errors if unsupported

    for f in "${SUDOTMP[@]+"${SUDOTMP[@]}"}"; do
        if [[ -n "${f}" ]]; then sudo rm -f -- "${f}"; fi
    done
    sudo rm -rf -- "${STATUSFILE:-}" "${LINKFILE:-}"
}

########################################################################################################################

_DO_LOG(){
    if [[ -s "${LOG_FILE:-}" ]]; then
        _OK "Extrait du Log :"
        tail -5 "${LOG_FILE:-}" 2>/dev/null
        _DIE "Log complet : ${LOG_FILE:-}"
    fi
    echo -e "${C_RESET}"
}

########################################################################################################################

_CLEANUP() {
    echo -e "${C_BOLD}${C_RED} Plantage !${C_RESET}"
    _DO_CLEAN
    _PRINT_ETC_FILES
    echo -e "${C_BOLD}${C_RED}"
    _DO_LOG
}

########################################################################################################################

_INTERRUPT() {
    echo -e "${C_BOLD}${C_GREEN} Arrêt du script demandé par l'utilisateur...${C_RESET}"
    _DO_CLEAN
    _PRINT_ETC_FILES
    echo -e "${C_BOLD}${C_GREEN}"
    _DO_LOG
}

########################################################################################################################

_HARDENING(){
    if [[ "${HARDENING,,}" = "yes" ]]; then
        # Ajustement droits fichiers critiques
        _LOG "* hardening : droits sur fichiers critiques *"
        local rights file dir
        dir="/etc/tmpfiles.d"
        file="${dir}/hardening-perms.conf"
        _RUNSILENT "" sudo mkdir -pv "${dir}"
        rights=$'\nz /etc/cron.deny    0600 root root -\nz /etc/cron.allow   0600 root root -\nz /etc/at.deny      0600 root root -\nz /etc/at.allow     0600 root root -\nz /etc/crontab      0600 root root -\nz /etc/cron.d       0700 root root -\nZ /etc/cron.hourly  0700 root root -\nZ /etc/cron.daily   0700 root root -\nZ /etc/cron.weekly  0700 root root -\nZ /etc/cron.monthly 0700 root root -\n'
        _INSTALL_ETC_FILES "robustification droits de fichiers critiques" "${rights}" "${file}" "644"
        if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
            _RUNSILENT "" sudo systemd-tmpfiles --create "${file}"
        fi

        # Désactivation de protocoles réseaux inutiles
        _LOG "* hardening : Désactivation de certains protocoles réseaux *"
        local net_content net_file dir
        dir="/etc/modprobe.d"
        _RUNSILENT "" sudo mkdir -pv "${dir}"
        net_file="${dir}/disable-network-protocols.conf"
        net_content=$'# network special protocols deactivated by post-install script by jotenakis\ninstall dccp /bin/false\ninstall sctp /bin/false\ninstall rds /bin/false\ninstall tipc /bin/false\ninstall n-hdlc /bin/false\ninstall ax25 /bin/false\ninstall netrom /bin/false\ninstall x25 /bin/false\ninstall rose /bin/false\ninstall decnet /bin/false\ninstall econet /bin/false\ninstall af_802154 /bin/false\ninstall ipx /bin/false\ninstall appletalk /bin/false\ninstall psnap /bin/false\ninstall p8023 /bin/false\ninstall p8022 /bin/false\ninstall can /bin/false\ninstall atm /bin/false\n'

        _INSTALL_ETC_FILES "suppresion de protocoles réseaux inutilisés" "${net_content}" "${net_file}" "644"

        # nom de machine dans /etc/hosts


        # Firewalld zone public par défaut pour toutes les interfaces
        # local iface current_zone default_zone
        # local reload_needed=0
        #
        # default_zone="$(sudo firewall-cmd --get-default-zone 2>/dev/null)"
        # if [[ "${default_zone}" != "public" ]]; then
        #     _RUN "Zone publique par défaut définie dans firewalld" sudo firewall-cmd --set-default-zone=public
        # else
        #     _INFO "Publique est déjà la zone firewalld par défaut"
        # fi
        #
        # tmp="$(mktemp)"
        # _GET_PHYSICAL_IFACE > "${tmp}"
        #
        # while IFS= read -r iface; do
        #     current_zone="$(sudo firewall-cmd --get-zone-of-interface="${iface}" 2>/dev/null)" || true
        #     [[ "${current_zone}" == "public" ]] && continue
        #     _RUN "Zone publique pour l'interface ${iface}" sudo firewall-cmd --permanent --zone=public --change-interface="${iface}"
        #     reload_needed=1
        # done < "${tmp}"
        # rm -f "${tmp}"
        #
        # if [[ "${reload_needed}" -eq 1 ]]; then
        #     _RUNSILENT "" sudo firewall-cmd --reload
        # fi
        # _LOG "Zones firewalld"
        # sudo firewall-cmd --get-active-zones | sudo tee -a "${LOG_FILE}" >/dev/null



    else
        _LOG "hardening non demandé"
    fi
}

########################################################################################################################

_SSHFAIL2BAN(){
    _LOG "* fail2ban *"
    if ! _IS_PKG_INSTALLED fail2ban; then
        _RUN "Installation de fail2ban" _PKG_INSTALL fail2ban
    else
        _INFO "Fail2ban déjà installé"
    fi
    local jailfile jaildir jailcontent jailservice new
    jailservice="fail2ban.service"
    jaildir="/etc/fail2ban/jail.d"
    new=""
    sudo mkdir -p "${jaildir}"
    jailfile="${jaildir}/sshd.local"
    jailcontent="# created by ${SCRIPTNAME} by jotenakis
[sshd]
enabled   = true
mode      = aggressive
port      = ${SSHD_CONFIG_PORT:-22}
filter    = sshd
backend   = systemd
maxretry  = 3
findtime  = 1h
bantime   = 24h
banaction = firewallcmd-rich-rules
"
    _INSTALL_ETC_FILES "prison fail2ban sshd" "${jailcontent}" "${jailfile}" "644"
    if grep -qxF 0 "${STATUSFILE}" 2>/dev/null; then
        new="yes"
    fi

    if _IS_ENABLED "${jailservice}"; then
        if _IS_ACTIVE "${jailservice}"; then
            if [[ "${new}" = "yes" ]]; then
                _RUN "Chargement de la configuration de ${jailservice}" sudo systemctl reload "${jailservice}"
            fi
        else
            _RUN "Lancement de de ${jailservice}" sudo systemctl start "${jailservice}"
        fi
    else
        _RUN "Activation/lancement de ${jailservice}" sudo systemctl enable --now "${jailservice}"
    fi
    if sudo test -f /var/log/fail2ban.log; then
        sudo cat /var/log/fail2ban.log | sudo tee -a "${LOG_FILE}" >/dev/null
    fi
}

########################################################################################################################

_SSHSYSTEMD(){
    # gestion service ssh
    local sshservice
    sshservice="sshd.service"
    if _IS_ENABLED "${sshservice}"; then
        if _IS_ACTIVE "${sshservice}"; then
            _LOG "${sshservice} OK, activé et démarré"
            _RUNSILENT "" sudo systemctl reload "${sshservice}"
        else
            _LOG "${sshservice} activé mais pas démarré"
            _RUNSILENT "" sudo systemctl start "${sshservice}"
        fi
    else
        _RUN "Activation/lancement de ${sshservice}" sudo systemctl --now enable "${sshservice}"
    fi
}

########################################################################################################################

_SSHBANNER(){
    local banner_file dir banner_content
    dir="/etc/issue.d"
    _RUNSILENT "" sudo mkdir -pv "${dir}"
    banner_file="${dir}/ssh.issue"
    banner_content='
#################################################################
#                   _    _           _   _                      #
#                  / \  | | ___ _ __| |_| |                     #
#                 / _ \ | |/ _ \ |__| __| |                     #
#                / ___ \| |  __/ |  | |_|_|                     #
#               /_/   \_\_|\___|_|   \__(_)                     #
#                                                               #
#  You are entering into a secured area! Your IP, Login Time,   #
#   Username has been noted and has been sent to the server     #
#                       administrator!                          #
#   This service is restricted to authorized users only. All    #
#            activities on this system are logged.              #
#  Unauthorized access will be fully investigated and reported  #
#        to the appropriate law enforcement agencies.           #
#################################################################
'
    if sudo test -L "${banner_file}"; then
        sudo rm -f -- "${banner_file}"
    fi
    _INSTALL_ETC_FILES "bannière sshd" "${banner_content}" "${banner_file}" "644"

    if [[ "${HARDENING,,}" = "yes" ]]; then
        # hardening je kill les /etc/issue* et remplace par symlink
        local f status
        for f in /etc/issue /etc/issue.net; do
            _RUNSILENT "" _SYMLINK "${banner_file}" "${f}"
            status=$(head -1 "${LINKFILE}")
            if [[ "${status}" = "1" ]]; then
                _RUNSILENT "" sudo rm -f -- "${f}"
                _RUNSILENT "" _SYMLINK "${banner_file}" "${f}"
                if grep -qxF 0 "${LINKFILE}" 2>/dev/null; then
                    _ETC_FILES_ADD "${f}"
                fi
            elif [[ "${status}" = "O" ]]; then
                _ETC_FILES_ADD "${f}"
            fi
        done
    fi
}

########################################################################################################################

_SSHUSERAUTH(){ # config sshd AllowUsers
    local config_ssh_allow content_ssh_allow
    config_ssh_allow="/etc/ssh/sshd_config.d/92-AllowUsers.conf"
    content_ssh_allow="# automatically generated and managed by ${SCRIPTNAME} - can be modified to allow other users ======
AllowUsers ${USER}
# ===========================================================================================================
"
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
}

########################################################################################################################

_DISABLE_FPRINTD(){
    if [[ "${DISABLE_FINGERPRINT}" = "yes"  ]]; then
        local change=0
        local status
        local service="fprintd.service"

        # PAM
        if authselect current 2>/dev/null | grep -q 'with-fingerprint'; then
            _RUNSILENT "" sudo authselect disable-feature with-fingerprint
            _RUNSILENT "" sudo authselect apply-changes
            change=1
        else
            _LOG "PAM n'a pas la fonction fprint activée"
        fi

        # systemd
        status=$(systemctl is-enabled "${service}" 2>/dev/null || true)
        if [[ "${status}" != "masked" ]]; then
            _RUNSILENT "" sudo systemctl stop fprintd.service
            _RUNSILENT "" sudo systemctl mask "${service}"
            change=1
        else
            _LOG "status ${service} : ${status}"
        fi

        if [[ "${change}" = "1" ]]; then
            _OK "Fonction du capteur d'empreintes désactivée"
        else
            _INFO "Fonction du capteur d'empreintes déjà désactivée"
        fi
    else
        _LOG "On ne touche pas au service de capteur d'empreintes"
    fi
}

########################################################################################################################

_SETUP_ENV_DEV(){
    local envcontent envfile envdir

# ENV GO/RUST local pour systemd
    envcontent="RUSTUP_HOME=${RUSTUP_HOME}
CARGO_HOME=${CARGO_HOME}
GOROOT=${GOROOT}
GOPATH=${GOPATH}
GOBIN=${GOBIN}
PATH=${CARGO_HOME}/bin:${GOROOT}/bin:${GOBIN}:\$PATH
"
    envdir="${HOME}/.config/environment.d"
    envfile="${envdir}/dev-env.conf"
    mkdir -p "${envdir}"
    _INSTALL_ETC_FILES "Environment GO et RUST pour systemd (${USER})" "${envcontent}" "${envfile}" "644"
    _RUNSILENT "" sudo chown "${USER}":"${USER}" "${envfile}"

# ENV GO/RUST pour systemd system-wide
    envcontent="[Manager]
DefaultEnvironment=RUSTUP_HOME=${RUSTUP_HOME} CARGO_HOME=${CARGO_HOME} GOROOT=${GOROOT} GOPATH=${GOPATH} GOBIN=${GOBIN}
"
    envdir="/etc/systemd/system.conf.d"
    envfile="${envdir}/dev-env.conf"
    sudo mkdir -p "${envdir}"
    _INSTALL_ETC_FILES "Environment GO et RUST pour systemd (système)" "${envcontent}" "${envfile}" "644"

# ENV GO/RUST local pour shells interactifs
    envcontent="#!/bin/bash
export RUSTUP_HOME=\"${RUSTUP_HOME}\"
export CARGO_HOME=\"${CARGO_HOME}\"
export GOROOT=\"${GOROOT}\"
export GOPATH=\"${GOPATH}\"
export GOBIN=\"${GOBIN}\"
export PATH=\"\$PATH:\$CARGO_HOME/bin:\$GOROOT/bin:\$GOBIN\"
"
    envdir="/etc/profile.d"
    envfile="${envdir}/dev-env.sh"
    sudo mkdir -p "${envdir}"
    _INSTALL_ETC_FILES "Environment GO et RUST pour les shells interactifs (système)" "${envcontent}" "${envfile}" "644"

}

########################################################################################################################

_ENSURE_LVM_SWAP() {
    local vg_name=""
    local lv_name=""
    local swap_dev=""
    local fstab_line=""

    vg_name="$(sudo lvs --noheadings -o vg_name,lv_name --separator '|' 2>/dev/null \
        | awk -F'|' '
            {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                if ($2 ~ /(^|[-_])(swap|lv_swap)([-_]|$)/ || $2 == "swap" || $2 == "lv_swap") {
                    print $1
                    exit
                }
            }')"

    lv_name="$(sudo lvs --noheadings -o vg_name,lv_name --separator '|' 2>/dev/null \
        | awk -F'|' '
            {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
                if ($2 ~ /(^|[-_])(swap|lv_swap)([-_]|$)/ || $2 == "swap" || $2 == "lv_swap") {
                    print $2
                    exit
                }
            }')"

    if [[ -z ${vg_name} || -z ${lv_name} ]]; then
        _LOG "Aucun LV swap LVM détecté"
        return 0
    fi

    swap_dev="/dev/mapper/${vg_name//-/'--'}-${lv_name//-/'--'}"

    if [[ ! -b ${swap_dev} ]]; then
        _LOG "Périphérique introuvable: ${swap_dev}"
        return 0
    fi

    if ! sudo blkid -t TYPE=swap "${swap_dev}" >/dev/null 2>&1; then
        _RUNSILENT "" sudo mkswap "${swap_dev}"
    fi

    fstab_line="${swap_dev} none swap sw,nofail 0 0"

    if ! sudo grep -qF "${swap_dev} none swap" /etc/fstab; then
        printf '%s\n' "${fstab_line}" | sudo tee -a /etc/fstab >/dev/null
        _RUNSILENT "" sudo systemctl daemon-reload
    fi

    local swap_dev_real
    swap_dev_real=$(readlink -f "${swap_dev}" 2>/dev/null) || true
    if ! grep -Fq "${swap_dev_real}" </proc/swaps; then
        _RUN "Activation du swap (${swap_dev})" sudo swapon "${swap_dev}"
    fi

}

########################################################################################################################

SETUP_GRUB() {
    local is_grub
    local grub_file="/etc/default/grub"
    local current_cmdline=""
    local current_default=""
    local current_timeout=""
    local full_cmdline=""
    local changed="no"
    local token

    # shellcheck disable=SC2034
    local -a cmdline_tokens=()
    local -a zswap_tokens
    local -a noswap_tokens
    noswap_tokens=(
            "zswap.enabled=0"
            "systemd.zram=0"
    )
    zswap_tokens=(
            "zswap.enabled=1"
            "zswap.shrinker_enabled=1"
            "zswap.compressor=lz4"
            "zswap.max_pool_percent=30"
            "systemd.zram=0"
    )

    is_grub=$(_DETECT_GRUB)

    _SECTION " Configuration de GRUB ⚙️ " "━" "${C_GREEN}"

    if [[ "${is_grub}" != "true" ]]; then
        _ERR "GRUB n'a pas été détecté, par prudence je ne change rien au bootloader actuel"
        return 0 # on continue (return 1 arrêterait le script à cause de set -e )
    fi

    if [[ ! -f "${grub_file}" ]]; then
        _ERR "${grub_file} introuvable"
        return 0
    fi

    if _EXIST grub-editenv; then
        _RUNSILENT "" sudo grub-editenv - unset menu_auto_hide
    elif _EXIST grub2-editenv; then
        _RUNSILENT "" sudo grub2-editenv - unset menu_auto_hide
    fi

    current_cmdline=$(_GRUB_GET_CMDLINE "${grub_file}")
    current_default=$(_GRUB_GET_VALUE "${grub_file}" "GRUB_DEFAULT")
    current_timeout=$(_GRUB_GET_VALUE "${grub_file}" "GRUB_TIMEOUT")

    _GRUB_CMDLINE_TO_ARRAY "${current_cmdline}" cmdline_tokens # on stocke la cmdline mots à mots dans un tableau

    if [[ "${DISABLE_PLYMOUTH,,}" = "yes" ]]; then
        _GRUB_ARRAY_REMOVE_TOKEN cmdline_tokens "rhgb"
        _GRUB_ARRAY_REMOVE_TOKEN cmdline_tokens "quiet"
    else
        _GRUB_ARRAY_ADD_TOKEN cmdline_tokens "rhgb"
        _GRUB_ARRAY_ADD_TOKEN cmdline_tokens "quiet"
    fi

    if [[ "${DISABLE_IPV6,,}" = "yes" ]]; then
        _GRUB_ARRAY_ADD_TOKEN cmdline_tokens "ipv6.disable=1"
    fi

    if [[ "${ZSWAP,,}" = "yes" ]]; then
        for token in "${zswap_tokens[@]}"; do
            _GRUB_ARRAY_ADD_TOKEN cmdline_tokens "${token}"
        done
    fi

    if [[ "${NOSWAP,,}" = "yes" ]]; then # on désactive ZSWAP et ZRAM
        for token in "${zswap_tokens[@]}"; do
            _GRUB_ARRAY_REMOVE_TOKEN cmdline_tokens "${token}"
        done
        for token in "${noswap_tokens[@]}"; do
            _GRUB_ARRAY_ADD_TOKEN cmdline_tokens "${token}"
        done
    fi

    _GRUB_ARRAY_ADD_FROM_STRING cmdline_tokens "${CMDLINE}"
    _GRUB_ARRAY_ADD_FROM_STRING cmdline_tokens "${TTY_COLOR}"

    # on transforme le tableau de mots 'tokens' en chaine
    full_cmdline=$(_GRUB_ARRAY_JOIN cmdline_tokens)

    if [[ "${current_cmdline}" != "${full_cmdline}" ]] || [[ "${current_default}" != "saved" ]] || [[ "${current_timeout}" != "2" ]]; then
        if [[ ! -f "${grub_file}.origin" ]]; then
            _RUNSILENT "" sudo cp -av "${grub_file}" "${grub_file}.origin"
        fi
        _RUNSILENT "" sudo cp -av "${grub_file}" "${grub_file}.bak"

        _RUN "Mise à jour de GRUB_DEFAULT" _GRUB_SET_KV "${grub_file}" "GRUB_DEFAULT" "saved"
        _RUN "Mise à jour de GRUB_TIMEOUT" _GRUB_SET_KV "${grub_file}" "GRUB_TIMEOUT" "2"
        _RUN "Mise à jour de GRUB_CMDLINE_LINUX" _GRUB_SET_CMDLINE "${grub_file}" "${full_cmdline}"

        _LOG "Options de démarrage du noyau dans GRUB :"
        _PRINT_LIST "${full_cmdline}" | tee -a "${LOG_FILE:-/dev/null}" >/dev/null

        _RUN "Regénération de la configuration GRUB" _GRUB_REGENERATE_CONFIG
        _ETC_FILES_ADD "${grub_file}"
        changed="yes"
    else
        _INFO "GRUB déjà OK (${grub_file})"
    fi

    {
        sudo ls -l "${grub_file}"
        sudo cat "${grub_file}"
    } >> "${LOG_FILE}"

    if [[ "${changed}" == "yes" ]]; then
        _LOG "Configuration GRUB mise à jour avec succès"
    fi
}

#!/usr/bin/env bash
# shellcheck disable=SC2310
# TODO sshd : email quand conn.
set -euo pipefail
# shellcheck source=./post-install-common.sh
source ./post-install-common.sh
declare -A SWAPS=()
ROOT="no" # variable si script lancé en mode ROOT => shell only mode
export ROOT

########################################################################################################################
# FONCTIONS SPECIFIQUES FEDORA                                                                                         #
########################################################################################################################

########################################################################################################################
CHECK() {
    if [[ -z "${BASH_VERSION:-}" ]]; then
        echo "Ce script requiert bash."
        exit 1
    fi
    if [[ "${BASH_VERSINFO[0]}" -lt 5 ]]; then
        echo "Bash >= 5 requis (actuel : ${BASH_VERSION})."
        exit 1
    fi
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi
    # Vérification explicite des droits root
    if [[ "${EUID}" -eq 0 ]]; then
        local reponse
        echo "${SCRIPTNAME} lancé en tant que root, le mode \"SHELL ONLY\" est imposé :"
        echo " - Les dépots GIT seront clonés (programmes non installés)."
        echo " - Le SHELL zsh sera configuré."
        echo " - Les dotfiles clonés seront déployés pour l'utilisateur root."
        echo " - Pour que tout le script soit exécuté il doit être lancé en utilisateur avec droits sudo."
        echo ""
        read -r -p "On continue en mode \"SHELL ONLY\" ? [o/N] " reponse
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
    #
    local fedora_rel
    fedora_rel=$(cat /etc/fedora-release)
    if [[ "${ROOT,,}" = "yes" ]]; then
        echo "Environnement valide : ${fedora_rel}, utilisateur root, mode shellonly."
    else
        echo "Environnement valide : ${fedora_rel}, utilisateur ${USER} avec droits sudo OK"
    fi
}

########################################################################################################################
REMOVE_SYSTEM_PACKAGES() {
    _SECTION " Suppression des paquets systèmes indésirables 📤 " "━" "${C_GREEN}"
    local pkg wants_systemd_networkd_removal wants_akonadi_removal
    wants_systemd_networkd_removal=0
    wants_akonadi_removal=0
    #
    if [[ "${DISABLE_PLYMOUTH,,}" = "yes" ]]; then
        if _IS_PKG_INSTALLED plymouth-core-libs; then
            _INFO "Suppression boot graphique demandée"
        else
            _LOG "Boot graphique déjà supprimée"
        fi
        SYSTEM_REMOVE+=("plymouth-core-libs")
    fi

    if [[ "${DISABLE_DNF_GUI,,}" = "yes" ]]; then
        if _IS_PKG_INSTALLED PackageKit-glib; then
            _INFO "Suppression GUI de dnf demandée"
        else
            _LOG "GUI de dnf déjà supprimée"
        fi
        if ! _IN_ARRAY gnome-software "${SYSTEM_REMOVE[@]}" ; then SYSTEM_REMOVE+=("gnome-software"); fi
        if ! _IN_ARRAY plasma-discover "${SYSTEM_REMOVE[@]}" ; then SYSTEM_REMOVE+=("plasma-discover"); fi
        if ! _IN_ARRAY PackageKit-glib "${SYSTEM_REMOVE[@]}" ; then SYSTEM_REMOVE+=("PackageKit-glib"); fi
    fi

    for pkg in "${SYSTEM_REMOVE[@]}"; do
        if [[ "${pkg}" == "systemd-networkd" ]]; then
            wants_systemd_networkd_removal=1
            continue
        fi
        if [[ "${pkg}" == "akonadi-server" ]]; then
            wants_akonadi_removal=1
            continue
        fi
    done
    if ((wants_systemd_networkd_removal)); then # on retire systemd-networkd des paquets à retirer car il sera retiré après avec des précautions
        local tmp=()
        for pkg in "${SYSTEM_REMOVE[@]}"; do
            if [[ "${pkg}" != "systemd-networkd" ]]; then tmp+=("${pkg}"); fi
        done
        SYSTEM_REMOVE=("${tmp[@]}")
    fi

    _MANAGE_TABLE _IS_PKG_REMOVED _PKG_REMOVE "${SYSTEM_REMOVE[@]}"

    if ((wants_systemd_networkd_removal)); then # par sécurité (si demandé) on ne dégage systemd-networkd qu'après assurance que NM est présent et actif
        if _IS_ACTIVE NetworkManager; then
            if _IS_PKG_INSTALLED systemd-networkd; then
                _RUN "Suppression systemd-networkd après vérification que NetworkManager est actif" _PKG_REMOVE systemd-networkd
            else
                _LOG "systemd-networkd déjà supprimé"
            fi
        else
            _INFO "NetworkManager inactif, systemd-networkd conservé par sécurité"
        fi
    fi
    if ((wants_akonadi_removal)); then
        _RUNSILENT "" rm -rf -- "${HOME}/.local/share/akonadi"*
        _RUNSILENT "" rm -rf -- "${HOME}/.config/akonadi"*
        _RUNSILENT "" rm -rf -- "${HOME}/.cache/akonadi"*
    fi

}

########################################################################################################################
INSTALL_REPOS() {
    _SECTION " Installation des dépôts systèmes additionnels 🔗 " "━" "${C_GREEN}"
    local fedora_ver rpmf type
    declare -i cache=0
    local rpmfusion_list="free nonfree"
    fedora_ver=$(rpm -E '%fedora')

    for rpmf in ${rpmfusion_list}; do
        type="rpmfusion-${rpmf}-release"
        if _IS_PKG_INSTALLED "${type}"; then
            _INFO "Dépôt ${type} déjà OK"
        else
            _RUN "Ajout du dépôt ${type}" _PKG_INSTALL https://mirrors.rpmfusion.org/"${rpmf}"/fedora/"${type}"-"${fedora_ver}".noarch.rpm
            _RUN "Ajout du dépôt ${type}-tainted" _PKG_INSTALL "${type}"-tainted
            cache=1
        fi
    done

    if [[ "${TERRA,,}" = "yes" ]]; then
        if _IS_PKG_INSTALLED terra-release; then
            _INFO "Dépôt Terra déjà OK"
        else
            # shellcheck disable=SC2016
            _RUN "Ajout du dépôt Terra" sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
            cache=1
        fi
    fi

    # repo brave si besoin
    if _IN_ARRAY brave-browser "${SYSTEM_PACKAGES[@]}"; then
        if dnf repolist 2>/dev/null | grep -q "brave-browser"; then
            _INFO "Dépôt Brave déjà OK"
        else
            _RUN "Ajout du dépôt Brave" sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
            cache=1
        fi
    fi

    # copr si besoin psd et cachos
    if _IN_ARRAY profile-sync-daemon "${SYSTEM_PACKAGES[@]}"; then
        _LOG "* repo copr psd *"
        _ADD_COPR "bigmenpixel/profile-sync-daemon" cache
    fi
    if [[ "${ENABLE_CACHYOS_KERNEL,,}" = "yes" ]]; then
        _LOG "* repos copr cachyos *"
        _ADD_COPR "bieszczaders/kernel-cachyos" cache
        _ADD_COPR "bieszczaders/kernel-cachyos-addons" cache
    fi

    _CLEANUP_APPSTREAM

    if [[ "${cache}" -eq 1 ]]; then
        echo ""
        _RUN "Mise à jour du cache des métadonnées des dépôts" sudo dnf makecache --refresh
    fi
}

########################################################################################################################

_ADD_COPR(){
    local repo
    local -n localcache="$2"
    repo="$1"
    : "${localcache}" # juste pour shellcheck
    if dnf repolist 2>/dev/null | grep -q "${repo//\//:}"; then
        _INFO "Dépôt COPR ${repo} déjà OK"
    else
        _RUN "Ajout du dépôt COPR ${repo}" sudo dnf copr enable -y "${repo}"
        localcache=1
    fi
}

########################################################################################################################
INSTALL_FONTS() {
    local header=""
    if [[ "${FONTS[*]}" != "" ]]; then
        _SECTION " Installation de polices d'affichage personnelles 🔤 " "━" "${C_GREEN}"
        header="yes"
        _MANAGE_TABLE _IS_PKG_INSTALLED _PKG_INSTALL_SKIP "${FONTS[@]}"
    else
        _LOG "Aucune police additionnelles demandées"
    fi

    if [[ -n "${VCONSOLE_FONT}" ]]; then
        if [[ ${header} = "" ]]; then
            _SECTION " Installation de polices d'affichage personnelles 🔤 " "━" "${C_GREEN}"
        fi
        _SETUP_VCONSOLE_FONT
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
        _LOG "Police console '${font}' introuvable — vérifier le paquet terminus-fonts"
    else
        if grep -q "^FONT=" "${vconsole}" 2>/dev/null; then
            if grep -q "^FONT=${font}" "${vconsole}" 2>/dev/null; then
                _INFO "Police console TTY déjà à jour (${vconsole})"
                grep FONT "${vconsole}" >>"${LOG_FILE}"
            else
                _RUNSILENT "" sudo sed -i "s/^FONT=.*/FONT=${font}/" "${vconsole}"
                _OK "Modification de la police console TTY (${vconsole})"
                _ETC_FILES_ADD "${vconsole}"
                _LOG "Police console définie :"
                cat "${vconsole}" 2>/dev/null >>"${LOG_FILE}"
            fi
        else
            printf '%s' "FONT=${font}" | sudo tee -a "${vconsole}" >/dev/null
            _OK "Ajout de la police console TTY (${vconsole})"
            _ETC_FILES_ADD "${vconsole}"
            _LOG "Police console définie :"
            cat "${vconsole}" 2>/dev/null >>"${LOG_FILE}"
        fi
    fi
}

########################################################################################################################
INSTALL_CODECS() {
    _SECTION " Installation des codecs multimédias additionnels 🎵 " "━" "${C_GREEN}"
    # codecs
    if ! _IS_PKG_INSTALLED ffmpeg; then
        _RUN "Échange ffmpeg-free <=> ffmpeg (rpmfusion)" sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
        _RUN "Mise à jour groupe multimedia" sudo dnf group upgrade multimedia --exclude=PackageKit-gstreamer-plugin -y
    else
        _INFO "ffmpeg (rpmfusion) déjà OK"
        _LOG "Groupe multimedia déjà à jour"
    fi
    if ! dnf repolist --enabled | grep -q '^fedora-cisco-openh264'; then
        _RUNSILENT "Activation Cisco h264." sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 -y
    else
        _LOG "Cisco h264 déjà OK"
    fi

    # mesa swap
    local gpu_vendor
    gpu_vendor=$(lspci | grep -iE 'VGA|3D' | head -1 | tr '[:upper:]' '[:lower:]')
    _LOG "GPU détecté : ${gpu_vendor}"

    if echo "${gpu_vendor}" | grep -q "amd\|radeon\|advanced micro"; then
        if ! _IS_PKG_INSTALLED mesa-va-drivers-freeworld; then
            _RUN "Installation mesa-va-drivers (rpmfusion)" _PKG_INSTALL_SKIP mesa-va-drivers-freeworld
        else
            _INFO "mesa-va-drivers (rpmfusion) déjà OK"
        fi
    elif echo "${gpu_vendor}" | grep -q "intel"; then
        if ! _IS_PKG_INSTALLED intel-media-driver; then
            _RUN "Installation intel-media-driver (rpmfusion)" _PKG_INSTALL_SKIP intel-media-driver
        else
            _INFO "intel-media-driver (rpmfusion) déjà OK"
        fi
    else
        _INFO "GPU : ni AMD ni Intel, pas de d'échange mesa <=> mesa (rpmfusion) à faire"
    fi
}

########################################################################################################################
INSTALL_SYSTEM_PACKAGES() {
    if [[ "${SYSTEM_PACKAGES[*]}" != "" ]]; then
        _SECTION " Installation des paquets systèmes personnalisés 📥 " "━" "${C_GREEN}"

        if [[ "${ENABLE_CACHYOS_KERNEL,,}" = "yes" ]]; then
            _LOG " ajout du noyau Linux de cachyOS dans les paquets à installer "

            if ! _IN_ARRAY kernel-cachyos "${SYSTEM_PACKAGES[@]}"; then
                if ! _IS_PKG_INSTALLED kernel-cachyos; then
                    _INFO "Noyau linux cachyOS demandé"
                fi
                SYSTEM_PACKAGES+=("kernel-cachyos")
            fi

            if ! _IN_ARRAY kernel-cachyos-core "${SYSTEM_PACKAGES[@]}"; then
                SYSTEM_PACKAGES+=("kernel-cachyos-core")
            fi

            if ! _IN_ARRAY kernel-cachyos-devel "${SYSTEM_PACKAGES[@]}"; then
                SYSTEM_PACKAGES+=("kernel-cachyos-devel")
            fi

            if ! _IN_ARRAY kernel-cachyos-devel-matched "${SYSTEM_PACKAGES[@]}"; then
                SYSTEM_PACKAGES+=("kernel-cachyos-devel-matched")
            fi

            if ! _IN_ARRAY kernel-cachyos-modules "${SYSTEM_PACKAGES[@]}"; then
                SYSTEM_PACKAGES+=("kernel-cachyos-modules")
            fi

            if ! _IN_ARRAY ananicy-cpp "${SYSTEM_PACKAGES[@]}"; then
                SYSTEM_PACKAGES+=("ananicy-cpp")
            fi

            if ! _IN_ARRAY cachyos-ananicy-rules "${SYSTEM_PACKAGES[@]}"; then
                SYSTEM_PACKAGES+=("cachyos-ananicy-rules")
            fi

        fi

        _MANAGE_TABLE _IS_PKG_INSTALLED _PKG_DOWNLOAD_THEN_INSTALL "${SYSTEM_PACKAGES[@]}"
    else
        _LOG "Aucun paquets systèmes additionnels demandés"
    fi
}

########################################################################################################################
_SETUP_FIREWALL() {
    _LOG "* configuration firewall *"
    # 1. Vérification de l'installation du paquet
    if ! _EXIST firewalld; then
        _RUN "Installation de firewalld" _PKG_INSTALL firewalld
    fi

    # 2. Vérification et activation du service
    if ! _IS_ACTIVE firewalld.service; then
        _RUN "Démarrage du firewall" sudo systemctl enable --now firewalld.service
    else
        _INFO "Firewall déjà actif"
        if ! _IS_ENABLED firewalld.service; then
            _RUNSILENT "" sudo systemctl enable firewalld.service
        fi
    fi

    # 3. Configuration des services essentiels
    local firewall_changed=false
    local service
    if [[ "${ACTIVATE_SSHD}" = "yes" ]]; then
        FIREWALL_SERVICES+=("ssh")
    fi
    for service in "${FIREWALL_SERVICES[@]}"; do
        if sudo firewall-cmd --permanent --query-service="${service}" >/dev/null 2>&1; then
            _LOG "Service ${service} déjà autorisé"
        else
            _RUN "Autorisation du service ${service}" sudo firewall-cmd --permanent --add-service="${service}"
            firewall_changed=true
        fi
    done

    # 4. Si on a fait au moins une modification, on recharge le pare-feu
    if [[ "${firewall_changed}" == true ]]; then
        _RUN "Rechargement des règles de firewalld (${FIREWALL_SERVICES[*]})" sudo firewall-cmd --reload
    else
        _INFO "Règles firewall déjà OK"
    fi
}

########################################################################################################################
SETUP_SWAP_BACKEND_FOR_ZSWAP() {
    if [[ "${ZSWAP,,}" = "yes" ]]; then
        _LOG "* swap *"
        _ENSURE_LVM_SWAP
        _GET_SWAP SWAPS
        if [[ "${#SWAPS[@]}" -gt 0 ]]; then
            local swappath allswap=""
            for swappath in "${!SWAPS[@]}"; do
                allswap="${allswap:+${allswap} }${swappath}"
            done
            _LOG "Au moins un swap sur disque a été détecté (${allswap}), pas nécessaire d'en construire un autre"
            return 0
        fi

        local target_size ram_total_kib SWAP_SIZE SWAP_MAX
        local recreate_swap=false
        local swapdir="/var/swap"

        ram_total_kib=$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)
        # SWAP = "2 x RAMtotal + 1Go" avec MAX 16Go
        SWAP_SIZE=$((1 + ram_total_kib * 2 / 1024 / 1024))
        SWAP_MAX=16
        if [[ "${SWAP_SIZE}" -gt "${SWAP_MAX}" ]]; then
            SWAP_SIZE=${SWAP_MAX}
        fi
        target_size=$((SWAP_SIZE * 1024 * 1024 * 1024))

        if [[ -f "${swapdir}/swapfile" ]]; then
            local current_size
            current_size=$(sudo stat -c %s "${swapdir}/swapfile" 2>/dev/null || echo 0)

            if [[ "${current_size}" -ne "${target_size}" ]]; then
                _INFO "${swapdir}/swapfile existant mais taille différente de celle demandée (${current_size} octets). Recréation..."
                _RUNSILENT "" sudo swapoff "${swapdir}/swapfile"
                _RUNSILENT "" sudo rm -fv -- "${swapdir}/swapfile"
                recreate_swap=true
            else
                _LOG "${swapdir}/swapfile est déjà correctement installé"
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
                        _INFO "Sous-volume BTRFS ${swapdir} existe déjà"
                    else
                        _RUNSILENT "" sudo rm -rvf -- "${swapdir}"
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
            _ETC_FILES_ADD "${swapdir}/swapfile"
            find "${swapdir}" -ls | sudo tee -a "${LOG_FILE}" >/dev/null
        fi

        if ! swapon --show | grep -q "${swapdir}/swapfile"; then
            _RUN "Activation du swap" sudo swapon "${swapdir}/swapfile"
        else
            _INFO "Swap déjà actif"
        fi

        # --- 2.5 SELinux : Autorisation pour systemd-logind ---
        _LOG "* SELINUX SWAP *"
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

            cat <<<"${selinux_content}" >"${selinux_tmp}.te"
            _RUNSILENT "" sudo checkmodule -M -m -o "${selinux_tmp}.mod" "${selinux_tmp}.te"
            _RUNSILENT "" sudo semodule_package -o "${selinux_tmp}.pp" -m "${selinux_tmp}.mod"
            _RUN "Installation du module SELinux systemd_swap_search" sudo semodule -i "${selinux_tmp}.pp"
            _RUNSILENT "" sudo rm -vf -- "${selinux_tmp}.te" "${selinux_tmp}.mod" "${selinux_tmp}.pp"
        else
            _LOG "Le module SELinux systemd_swap_search est déjà actif"
        fi
    else
        _LOG "zswap n'est pas demandé (variable ZSWAP = ${ZSWAP,,}) => on ne crée pas de swap physique"
    fi
}

########################################################################################################################
SETUP_SUDO_RS() {
    if [[ "${SUDORS}" = "yes" ]]; then
        _SECTION " Configuration de sudo-rs 🔐 " "━" "${C_GREEN}"
        local change=0
        # 1. On installe sudo-rs
        if ! _EXIST sudo-rs; then
            _RUN "Installation de sudo-rs" _PKG_INSTALL sudo-rs
            change=1
        fi

        # 2. Copie (sans suppression) des fichiers vers le monde sudo-rs
        local f_sudoers_rs="/etc/sudoers-rs"
        local d_sudoers_rs_d="/etc/sudoers-rs.d"

        if [[ -f "/etc/sudoers" && ! -f "${f_sudoers_rs}" ]]; then
            _RUN "Création du fichier ${f_sudoers_rs} depuis /etc/sudoers" sudo cp -a /etc/sudoers "${f_sudoers_rs}"
            _ETC_FILES_ADD "${f_sudoers_rs}"
            change=1
        fi

        if [[ -d "/etc/sudoers.d" && ! -d "${d_sudoers_rs_d}" ]]; then
            _RUN "Création du dossier ${d_sudoers_rs_d} depuis /etc/sudoers.d" sudo cp -a /etc/sudoers.d "${d_sudoers_rs_d}"
            _ETC_FILES_ADD "${d_sudoers_rs_d}"
            change=1
        fi

        # 3. Assurer la présence stricte des inclusions dans le nouveau fichier
        # CORRECTION : Utilisation de ~ comme délimiteur sed pour ne pas interférer avec le OU (|)
        if ! sudo grep -q "@includedir /etc/sudoers-rs.d" "${f_sudoers_rs}"; then
            _RUNSILENT "" sudo bash -c "
                sed -i -E 's~^(@|#)includedir[[:space:]]+/etc/sudoers\.d~@includedir /etc/sudoers-rs.d~g' '${f_sudoers_rs}'

                if ! grep -qE '^(@|#)includedir[[:space:]]+/etc/sudoers-rs\.d' '${f_sudoers_rs}'; then
                    echo -e '\n@includedir /etc/sudoers-rs.d' >> '${f_sudoers_rs}'
                fi

                if ! grep -qE '^(@|#)includedir[[:space:]]+/etc/sudoers\.d' '${f_sudoers_rs}'; then
                    echo -e '# Fallback pour les paquets Fedora\n@includedir /etc/sudoers.d' >> '${f_sudoers_rs}'
                fi
            "
            change=1
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

        if [[ "${current_link}" != "${sudo_rs_bin}" ]]; then
            # CORRECTION : On regroupe le 'mv' et le 'ln' dans le même appel sudo pour ne pas bloquer le système !
            _RUN "Remplacement du binaire sudo" sudo bash -c "
                if [[ -f '${sys_sudo}' && ! -L '${sys_sudo}' ]]; then
                    mv -f '${sys_sudo}' '${sys_sudo_bak}'
                fi
                ln -sf '${sudo_rs_bin}' '${sys_sudo}'
            "
            change=1
        fi

        _PASS
        #_RUN "Symlink prioritaire /usr/local/bin/sudo -> sudo-rs" sudo ln -svf "${sudo_rs_bin}" "${local_bin_sudo}"
        _SYMLINK "${sudo_rs_bin}" "${local_bin_sudo}"
        if grep -qxF 0 "${LINKFILE}" 2>/dev/null; then
            change=1
            _ETC_FILES_ADD "${local_bin_sudo}"
        fi # le lien a bien été crée
        _RUNSILENT "" sudo chmod -v 4111 "${sudo_rs_bin}"
        _RUNSILENT "" sudo chmod -v 0000 "${sys_sudo_bak}"

        # 5. Déploiement des règles spécifiques
        if _IN_ARRAY profile-sync-daemon "${SYSTEM_PACKAGES[@]}"; then
            local pattern="%wheel ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper"
            local file="${d_sudoers_rs_d}/90-profile-sync-daemon"
            if sudo test -f "${file}"; then
                if ! sudo grep -q "${pattern}" "${file}" >/dev/null; then
                    _RUN "Mise à jour de la règle \"profile-sync-daemon\"" sudo bash -c "echo \"${pattern}\" > \"${file}\""
                    change=1
                    _ETC_FILES_ADD "${file}"
                fi
            else
                _RUN "Création de la règle \"profile-sync-daemon\"" sudo bash -c "echo \"${pattern}\" > \"${file}\""
                change=1
                _ETC_FILES_ADD "${file}"
            fi
        fi
        local pattern="Defaults pwfeedback,timestamp_timeout=60"
        local file2="${d_sudoers_rs_d}/99-timeout"
        if sudo test -f "${file2}"; then
            if ! sudo grep -q "${pattern}" "${file2}" >/dev/null; then
                _RUN "Mise à jour de la règle \"timeout\"" sudo bash -c "echo \"${pattern}\" > \"${file2}\""
                change=1
                _ETC_FILES_ADD "${file2}"
            fi
        else
            _RUN "Création de la règle \"timeout\"" sudo bash -c "echo \"${pattern}\" > \"${file2}\""
            change=1
            _ETC_FILES_ADD "${file2}"
        fi

        _RUNSILENT "" sudo chmod -v 0440 "${f_sudoers_rs}"
        _RUNSILENT "" sudo chmod -v 0750 "${d_sudoers_rs_d}"
        _RUNSILENT "" sudo chmod -v 0440 "${file}" "${file2}"

        # 6. Nettoyage radical des anciens fichiers
        if [[ -f "/etc/sudoers" && ! -L "/etc/sudoers" ]]; then
            _RUNSILENT "" sudo mv -vf /etc/sudoers /etc/sudoers.bak
            change=1
        fi

        if [[ -d "/etc/sudoers.d" ]]; then
            _RUNSILENT "" sudo rm -rf /etc/sudoers.d
        fi
        _RUNSILENT "" sudo mkdir -pv /etc/sudoers.d
        _RUNSILENT "" sudo chmod -v 0750 /etc/sudoers.d

        # 7. Blocage propre des futures mises à jour du vieux sudo par DNF
        if ! sudo dnf versionlock list | grep -q sudo; then
            _RUNSILENT "" sudo dnf versionlock add sudo
            change=1
        fi
        if ! sudo grep -q "excludepkgs=sudo" /etc/dnf/dnf.conf 2>/dev/null; then
            #_RUNSILENT "" sudo crudini --verbose --set /etc/dnf/dnf.conf main excludepkgs 'sudo'
            _RUNSILENT "" sudo dnf config-manager setopt excludepkgs=sudo
            change=1
            _ETC_FILES_ADD "/etc/dnf/dnf.conf"
        fi
        if [[ "${change}" -eq 1 ]]; then
            _OK "sudo-rs OK (remplace sudo)"
        else
            _INFO "sudo-rs déjà OK"
        fi
    else
        _LOG "sudo-rs n'est pas demandé (variable SUDORS = ${SUDORS}) => on laisse sudo tel quel."
    fi
}

########################################################################################################################

_CLEANUP_APPSTREAM() {
    if [[ "${DISABLE_DNF_GUI,,}" = "yes" ]]; then
        local -a appstream=()
        if _IS_PKG_INSTALLED rpmfusion-free-appstream-data; then
            appstream+=("rpmfusion-free-appstream-data")
        fi
        if _IS_PKG_INSTALLED rpmfusion-nonfree-appstream-data; then
            appstream+=("rpmfusion-nonfree-appstream-data")
        fi
        if [[ ${#appstream[@]} -gt 0 ]]; then
            _RUN "Suppression métadonnées appstream RPMFusion" _PKG_REMOVE "${appstream[@]}"
        fi
    fi
}

########################################################################################################################

SETUP_CACHYOS_KERNEL() {
    if [[ "${ENABLE_CACHYOS_KERNEL,,}" = "yes" ]] && _IS_PKG_INSTALLED kernel-cachyos-core; then
         _SECTION " Configuration du noyau Linux de cachyOS 🐧 " "━" "${C_GREEN}"

        # Noyau CachyOS par défaut dans grub
        _LOG "* cachysOS GRUB *"
        local linux is_grub
        linux=$(printf '%s\n' /boot/vmlinuz*cachy* | sort -V | tail -1)
        is_grub=$(_DETECT_GRUB)
        if [[ "${is_grub}" == "true" ]]; then
            _RUN "Noyau ${linux} configuré par défaut dans GRUB" sudo grubby --set-default="${linux}"
        else
            _OK "GRUB non détecté, pas de changement dans l'ordre de priorité des noyaux installés"
            _LOG "Noyau cachyOS : ${linux}"
        fi

        # Secure Boot
        if ! _IS_PKG_INSTALLED mokutil ; then
            _RUNSILENT "" _PKG_INSTALL mokutil
        fi
        local sb_enabled
        sb_enabled=$(mokutil --sb-state 2>/dev/null | awk '{print $2}') || true
        if [[ "${sb_enabled}" = "enabled" ]]; then
            #_OK "On va devoir signer le noyau cachyos pour qu'il supporte un Secure boot actif => TODO"
            if ! _EXIST pesign; then
                _RUNSILENT "" _PKG_INSTALL pesign
            fi
            local contentcachyos dircachyos filecachyos
            dircachyos="/etc/kernel/postinst.d"
            _RUNSILENT "" sudo mkdir -pv "${dircachyos}"
            filecachyos="${dircachyos}/00-signing"
            # shellcheck disable=SC2016
            contentcachyos=$(cat <<'EOF'
#!/bin/sh
set -e

MOK_KEY_NICKNAME='CachyOS Secure Boot'

logger -t kernel-postinst "script appelé : $0 args: $*"

if [ "$#" -ne 2 ]; then
    logger -t kernel-postinst "problèmes d'arguments"
    exit 1
fi

KERNEL_IMAGE=$2

case $KERNEL_IMAGE in
    *cachyos*) logger -t kernel-postinst "Noyau cachyos à signer" ;;
    *) logger -t kernel-postinst "Pas de noyau cachyos à signer"; exit 0 ;;
esac

if ! command -v pesign >/dev/null 2>&1; then
    logger -t kernel-postinst "pesign non détecté"
    exit 1
fi

if [ ! -w "$KERNEL_IMAGE" ]; then
    logger -t kernel-postinst "kernel image non modifiable donc non signable: $KERNEL_IMAGE"
    exit 1
fi

logger -t kernel-postinst "Signature noyau $KERNEL_IMAGE..."
pesign --verbose --certificate "$MOK_KEY_NICKNAME" --in "$KERNEL_IMAGE" --sign --out "$KERNEL_IMAGE.signed"
mv -f -- "$KERNEL_IMAGE.signed" "$KERNEL_IMAGE"

EOF
)
        _INSTALL_ETC_FILES "chiffrement kernel cachyos" "${contentcachyos}" "${filecachyos}" "755"

        filecachyos="${dircachyos}/999-setdefaultbootkernel"
        contentcachyos=$(cat <<'EOF'
#!/bin/sh
set -eu

logger -t kernel-postinst "script appelé : $0 args: $*"

kernel="$(find /boot -maxdepth 1 -type f -name 'vmlinuz-*cachy*' -printf '%f\n' | sort -V | tail -n 1)"

[ -n "${kernel}" ] || {
  logger -t kernel-postinst "aucun noyau cachyOS détecté"
  exit 1
}

id="${kernel#vmlinuz-}"
entry="/boot/loader/entries/*-${id}.conf"

set -- $entry
[ -f "$1" ] || {
  logger -t kernel-postinst "aucune entrée GRUB trouvée pour $id"
  exit 1
}

saved_entry="$(basename "${1%.conf}")"
grub2-editenv - set "saved_entry=$saved_entry"
logger -t kernel-postinst "entrée GRUB par défaut : $saved_entry"


EOF
)
        if [[ "${is_grub}" == "true" ]]; then
            _INSTALL_ETC_FILES "script post-install kernel cachyos" "${contentcachyos}" "${filecachyos}" "755"
        else
            _LOG "GRUB non détecté, pas de script post-install cachyos"
        fi

        elif [[ "${sb_enabled}" = "" ]]; then
            _LOG "EFI ou SB non supporté sur ce système ?"
        elif [[ "${sb_enabled}" = "disabled" ]]; then
            _INFO "Secure boot désactivé, le noyau cachyos n'a pas besoin d'être signé"
        else
            _LOG "état secure boot inconnu ${sb_enabled}"
        fi
    else
        _LOG "Pas de configuration du kernel cachyos, soit parce que non explicitement demandé soit parce qu'il n'a pas pu être installé !"
        {   echo "--- paquets cachyos :"
            rpm -qa | grep -i cachyos
            echo "---------------------"
        } >> "${LOG_FILE}"
    fi
}


######################
MAIN "$@"

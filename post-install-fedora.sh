#!/usr/bin/env bash
# shellcheck disable=SC2310
set -euo pipefail
source ./post-install-common.sh # fonctions distro-agnostique

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
    if [[ "${EUID}" -eq 0 ]]; then
        echo "Ne pas lancer en root. Le script gère sudo lui-même."
        exit 1
    fi
    if [[ ! -f /etc/fedora-release ]]; then
        echo "Fedora uniquement."
        exit 1
    fi

    # Vérification explicite des droits sudo (groupe wheel)
    if ! id -nG "${USER}" | grep -qw "wheel"; then
        echo "L'utilisateur ${USER} n'appartient pas au groupe 'wheel' (sudo). Abandon."
        exit 1
    fi
    #
    local fedora_rel
    fedora_rel=$(cat /etc/fedora-release)
    echo "Environnement valide — ${fedora_rel}, utilisateur ${USER} avec droits sudo"
    sleep 1
}

########################################################################################################################
REMOVE_RPM_PACKAGES() {
    _SECTION " Suppression des paquets RPM indésirables " "━" "${C_GREEN}"
    local pkg wants_systemd_networkd_removal wants_akonadi_removal
    wants_systemd_networkd_removal=0
    wants_akonadi_removal=0
    #
    if [[ "${DISABLE_PLYMOUTH,,}" = "yes" ]]; then
#        _INFO "Suppression boot graphique (plymouth)"
        DNF_REMOVE+=("plymouth-core-libs")
    fi

    if [[ "${DISABLE_DNF_GUI,,}" = "yes" ]]; then
 #       _INFO "Suppression outils graphiques de gestion des paquets"
        if ! _IN_ARRAY gnome-software "${DNF_REMOVE[@]}" ; then DNF_REMOVE+=("gnome-software"); fi
        if ! _IN_ARRAY plasma-discover "${DNF_REMOVE[@]}" ; then DNF_REMOVE+=("plasma-discover"); fi
        if ! _IN_ARRAY PackageKit-glib "${DNF_REMOVE[@]}" ; then DNF_REMOVE+=("PackageKit-glib"); fi
    fi

    for pkg in "${DNF_REMOVE[@]}"; do
        if [[ "${pkg}" == "systemd-networkd" ]]; then
            wants_systemd_networkd_removal=1
            continue
        fi
        if [[ "${pkg}" == "akonadi-server" ]]; then
            wants_akonadi_removal=1
            continue
        fi
    done
    _MANAGE_TABLE _IS_PKG_REMOVED _PKG_REMOVE "${DNF_REMOVE[@]}"

    if [[ "${ZSWAP,,}" = "yes" ]]; then # on dégage zram si zswap est demandé
        if _IS_PKG_INSTALLED zram-generator-defaults; then
            _RUN "Suppression zram pour remplacer par zswap" _PKG_REMOVE zram-generator-defaults
        fi
        _LOG "ZSWAP est demandé : zram est supprimé"
    fi

    if ((wants_systemd_networkd_removal)); then # par sécurité (si demandé) on ne dégage systemd-networkd qu'après assurance que NM est présent et actif
        if _IS_ACTIVE NetworkManager; then
            if _IS_PKG_INSTALLED systemd-networkd; then
                _RUN "Suppression systemd-networkd" _PKG_REMOVE systemd-networkd
            else
                _INFO "systemd-networkd déjà supprimé"
            fi
        else
            _INFO "NetworkManager inactif, systemd-networkd conservé par sécurité"
        fi
    fi
    if ((wants_akonadi_removal)); then
        _RUNSILENT "" rm -rf "${HOME}/.local/share/akonadi"*
        _RUNSILENT "" rm -rf "${HOME}/.config/akonadi"*
        _RUNSILENT "" rm -rf "${HOME}/.cache/akonadi"*
    fi

}

########################################################################################################################
INSTALL_REPOS() {
    _SECTION " Installation des dépôts RPM additionnels " "━" "${C_GREEN}"
    local fedora_ver rpmf cache=0 type
    local rpmfusion_list="free nonfree"
    fedora_ver=$(rpm -E '%fedora')

    for rpmf in ${rpmfusion_list}; do
        type="rpmfusion-${rpmf}-release"
        if _IS_PKG_INSTALLED "${type}"; then
            _INFO "Dépôt ${type} déjà présent"
        else
            _RUN "Ajout du dépôt ${type} (f${fedora_ver})" _PKG_INSTALL https://mirrors.rpmfusion.org/"${rpmf}"/fedora/"${type}"-"${fedora_ver}".noarch.rpm
            _RUN "Ajout du dépôt ${type}-tainted (f${fedora_ver})" _PKG_INSTALL "${type}"-tainted
            cache=1
        fi
    done

    if _IS_PKG_INSTALLED terra-release; then
        _INFO "Dépôt Terra déjà présent"
    else
        # shellcheck disable=SC2016
        _RUN "Ajout du dépôt Terra (f${fedora_ver})" sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
        cache=1
    fi

    if dnf repolist 2>/dev/null | grep -q "bigmenpixel:profile-sync-daemon"; then
        _INFO "Dépôt COPR profile-sync-daemon déjà présent"
    else
        _RUN "Ajout du dépôt COPR profile-sync-daemon" sudo dnf copr enable -y bigmenpixel/profile-sync-daemon
        cache=1
    fi

    if dnf repolist 2>/dev/null | grep -q "brave-browser"; then
        _INFO "Dépôt Brave déjà présent"
    else
        _RUN "Ajout du dépôt Brave" sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        cache=1
    fi

    _CLEANUP_APPSTREAM

    if [[ "${cache}" -eq 1 ]]; then
        _RUN "Mise à jour du cache des métadonnées des dépôts" sudo dnf makecache --refresh
    fi
}

########################################################################################################################
INSTALL_FONTS() {
    local header=""
    if [[ "${FONTS[*]}" != "" ]]; then
        _SECTION " Installation de polices d'affichage personnelles " "━" "${C_GREEN}"
        header="yes"
        _MANAGE_TABLE _IS_PKG_INSTALLED _PKG_INSTALL_SKIP "${FONTS[@]}"
    else
        _LOG "Aucune police additionnelles demandées"
    fi

    if [[ -n "${VCONSOLE_FONT}" ]]; then
        if [[ ${header} = "" ]]; then
            _SECTION " Installation de polices d'affichage personnelles " "━" "${C_GREEN}"
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
    _SECTION " Installation des codecs multimédias additionnels " "━" "${C_GREEN}"
    # codecs
    if ! _IS_PKG_INSTALLED ffmpeg; then
        _RUN "Échange ffmpeg-free <=> ffmpeg (rpmfusion)" sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
        _RUN "Mise à jour groupe multimedia" sudo dnf group upgrade multimedia --exclude=PackageKit-gstreamer-plugin -y
    else
        _INFO "ffmpeg (rpmfusion) déjà présent"
        _LOG "Groupe multimedia déjà à jour"
    fi
    if ! dnf repolist --enabled | grep -q '^fedora-cisco-openh264'; then
        _RUNSILENT "Activation Cisco h264." sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 -y
    else
        _LOG "Cisco h264 déjà activé"
    fi

    # mesa swap
    local gpu_vendor
    gpu_vendor=$(lspci | grep -iE 'VGA|3D' | head -1 | tr '[:upper:]' '[:lower:]')
    _LOG "GPU détecté : ${gpu_vendor}"

    if echo "${gpu_vendor}" | grep -q "amd\|radeon\|advanced micro"; then
        if ! _IS_PKG_INSTALLED mesa-va-drivers-freeworld; then
            _RUN "Swap mesa-va-drivers → rpmfusion (AMD)" sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
        else
            _INFO "Mesa (rpmfusion) déjà présent"
        fi
    elif echo "${gpu_vendor}" | grep -q "intel"; then
        if ! _IS_PKG_INSTALLED intel-media-driver; then
            _RUN "intel-media-driver" _PKG_INSTALL intel-media-driver
        else
            _INFO "intel-media-driver déjà présent"
        fi
    else
        _INFO "GPU ni AMD ni Intel, pas de d'échange mesa <=> mesa (rpmfusion) à faire"
    fi
}

########################################################################################################################
INSTALL_RPM_PACKAGES() {
    if [[ "${DNF_PACKAGES[*]}" != "" ]]; then
        _SECTION " Installation des paquets RPM personnalisés " "━" "${C_GREEN}"
        _MANAGE_TABLE _IS_PKG_INSTALLED _PKG_DOWNLOAD_THEN_INSTALL "${DNF_PACKAGES[@]}"
    else
        _LOG "Aucun paquets RPM additionnels demandés"
    fi
}

########################################################################################################################
SETUP_GRUB() {
    is_grub=$(_DETECT_GRUB)

    _SECTION " Configuration de GRUB " "━" "${C_GREEN}"

    if [[ "${is_grub}" == "true" ]]; then
        local is_grub zswap="" ipv6="" plymouth=""

        if [[ "${ZSWAP,,}" = "yes" ]]; then
            zswap="zswap.enabled=1 zswap.compressor=zstd"
            _LOG "ZSWAP est demandé : \"${zswap}\" ajouté à GRUB"
        fi
        if [[ "${DISABLE_IPV6,,}" = "yes" ]]; then
            ipv6="ipv6.disable=1"
        fi
        if [[ "${DISABLE_PLYMOUTH,,}" != "yes" ]]; then
            plymouth="rhgb quiet"
        fi

        local luks_param="" target_cmdline="" current_cmdline="" current_default=""
        if grep -q 'rd\.luks\.uuid=' /etc/default/grub; then
            luks_param=$(grep -oP 'rd\.luks\.uuid=\S+' /etc/default/grub | head -n 1)
        fi

        target_cmdline="${luks_param} ${plymouth} ${zswap} ${ipv6} ${CMDLINE} ${TTY_COLOR}"
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
            _RUN "Mise à jour des paramètres de GRUB (/etc/default/grub)" sudo sed -i -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=menu/' -e "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${target_cmdline}\"|" /etc/default/grub
            _LOG "Options de démarrage du noyau ajoutées à GRUB : "
            _PRINT_LIST "${target_cmdline}" | tee -a "${LOG_FILE:-/dev/null}" >/dev/null

            if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
                _RUN "Délai GRUB 2 sec (/etc/default/grub)" sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
            else
                _RUN "Délai GRUB 2 sec (/etc/default/grub)" sudo bash -c "echo 'GRUB_TIMEOUT=2' >> /etc/default/grub"
            fi

            _RUN "Regénération de la configuration de GRUB" sudo grub2-mkconfig -o /boot/grub2/grub.cfg
            _LOG "sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
            _ETC_FILES_ADD "/etc/default/grub"
        else
            _INFO "GRUB déjà OK (/etc/default/grub)"
        fi
        {
            sudo ls -l /etc/default/grub
            sudo cat /etc/default/grub
        } >>"${LOG_FILE}"
    else
        _ERR "GRUB n'a pas été détecté, je ne change rien au bootloader."
    fi
}

########################################################################################################################
SETUP_FIREWALL() {
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
SETUP_SWAP() { # que si zswap est demandé
    if [[ "${ZSWAP,,}" = "yes" ]]; then
        _LOG "* swap *"
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
                _RUNSILENT "" sudo rm -fv "${swapdir}/swapfile"
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

            _RUNSILENT "" rm -fv "${selinux_tmp}.*"
        else
            _LOG "Le module SELinux systemd_swap_search est déjà actif"
        fi
    else
        _LOG "zswap n'est pas demandé (variable ZSWAP = ${ZSWAP,,}) => on ne crée pas de swap physique."
    fi
}

########################################################################################################################
SETUP_SUDO_RS() {
    if [[ "${SUDORS}" = "yes" ]]; then
        _SECTION " Configuration de sudo-rs " "━" "${C_GREEN}"
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
            _RUN "Création du fichier ${f_sudoers_rs} depuis l'original" sudo cp -a /etc/sudoers "${f_sudoers_rs}"
            _ETC_FILES_ADD "${f_sudoers_rs}"
            change=1
        fi

        if [[ -d "/etc/sudoers.d" && ! -d "${d_sudoers_rs_d}" ]]; then
            _RUN "Création du dossier ${d_sudoers_rs_d} depuis l'original" sudo cp -a /etc/sudoers.d "${d_sudoers_rs_d}"
            _ETC_FILES_ADD "${d_sudoers_rs_d}"
            change=1
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
            _RUN "Remplacement radical du binaire sudo" sudo bash -c "
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
        local pattern="%wheel ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper"
        local file="${d_sudoers_rs_d}/90-profile-sync-daemon"
        if sudo test -f "${file}"; then
            if ! sudo grep -q "${pattern}" "${file}" >/dev/null; then
                _RUN "Mise à jour de la règle \"profile-sync-daemon\"." sudo bash -c "echo \"${pattern}\" > \"${file}\""
                change=1
                _ETC_FILES_ADD "${file}"
            fi
        else
            _RUN "Création de la règle \"profile-sync-daemon\"." sudo bash -c "echo \"${pattern}\" > \"${file}\""
            change=1
            _ETC_FILES_ADD "${file}"
        fi

        local pattern="Defaults pwfeedback,timestamp_timeout=60"
        local file2="${d_sudoers_rs_d}/99-timeout"
        if sudo test -f "${file2}"; then
            if ! sudo grep -q "${pattern}" "${file2}" >/dev/null; then
                _RUN "Mise à jour de la règle \"timeout\"." sudo bash -c "echo \"${pattern}\" > \"${file2}\""
                change=1
                _ETC_FILES_ADD "${file2}"
            fi
        else
            _RUN "Création de la règle \"timeout\"." sudo bash -c "echo \"${pattern}\" > \"${file2}\""
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
        if ! sudo grep -q sudo /etc/dnf/dnf.conf 2>/dev/null; then
            _RUNSILENT "" sudo crudini --verbose --set /etc/dnf/dnf.conf main excludepkgs 'sudo'
            change=1
            _ETC_FILES_ADD "/etc/dnf/dnf.conf"
        fi
        if [[ "${change}" -eq 1 ]]; then
            _OK "sudo-rs en place, remplace définitivement sudo"
        else
            _INFO "sudo-rs déjà correctement configuré"
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
_PKG_CONFIG() {
    local dnf="/etc/dnf/dnf.conf"
    if ! sudo grep -q "defaultyes = true" "${dnf}" 2>/dev/null || ! sudo grep -q "max_parallel_downloads = 10" "${dnf}" 2>/dev/null || ! sudo grep -q "countme = False" "${dnf}" 2>/dev/null; then
        _ETC_FILES_ADD "${dnf}"
    fi
    _RUNSILENT "" sudo crudini --verbose --set "${dnf}" main defaultyes true
    _RUNSILENT "" sudo crudini --verbose --set "${dnf}" main max_parallel_downloads 10
    _RUNSILENT "" sudo crudini --verbose --set "${dnf}" main countme False
}

_PKG_INSTALL_SKIP() {
    sudo dnf install --skip-unavailable -y "$@"
}

_PKG_INSTALL() {
    sudo dnf install -y "$@"
}

_PKG_DOWNLOAD_THEN_INSTALL() {
    local arch
    arch=$(uname -m)
    echo "Téléchargement depuis les dépôts... "
    _RUNSILENT "" sudo dnf download --skip-unavailable -y --arch "${arch}" --arch noarch --resolve --destdir="${DOWNLOAD_DIR}" "$@"
    echo "installation depuis le cache local..."
    if ! compgen -G "${DOWNLOAD_DIR}/*.rpm" > /dev/null; then
        _ERR "Aucun RPM à installer"
        _RUNSILENT "" sudo rm -rvf "${DOWNLOAD_DIR}"
        return 0
    fi
    _RUNSILENT "" sudo dnf install --skip-unavailable -y "${DOWNLOAD_DIR}"/*.rpm
    _RUNSILENT "" sudo rm -rvf "${DOWNLOAD_DIR}"
}

_SYS_UPDATE() {
    sudo dnf upgrade -y
}

_PKG_REMOVE() {
    sudo dnf remove -y "$@"
}

_IS_PKG_REMOVED() {
    ! rpm -q "$@" &>>"${LOG_FILE}"
}

_IS_PKG_INSTALLED() {
    rpm -q "$@" &>>"${LOG_FILE}"
}

_REFRESH_SYS_CACHE() {
    local sentinel="/var/cache/dnf/.last_makecache"
    local max_age=3600
    local now sentinel_mtime age

    now=$(date +%s)
    sentinel_mtime=$(stat -c %Y "${sentinel}" 2>/dev/null || echo 0)
    age=$((now - sentinel_mtime))

    if [[ ${age} -gt ${max_age} ]]; then
        _RUN "Mise à jour du cache des métadonnées des dépôts" sudo dnf makecache --refresh
        sudo touch "${sentinel}"
    else
        _LOG "Cache DNF à jour (${age}s < ${max_age}s)"
    fi
}

########################################################################################################################

######################
MAIN "$@"

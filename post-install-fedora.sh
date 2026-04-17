#!/usr/bin/env bash
set -euo pipefail
source post-install-common.sh   # fonctions distro-agnostique


########################################################################################################################
# FONCTIONS SPECIFIQUES FEDORA                                                                                         #
########################################################################################################################

########################################################################################################################
CHECK_ENV() {
    _SECTION " Préparation " "━" "${C_GREEN}"

    [[ -n "${BASH_VERSION:-}" ]]       || _DIE "Ce script requiert bash."
    [[ "${BASH_VERSINFO[0]}" -ge 5 ]]  || _DIE "Bash >= 5 requis (actuel : ${BASH_VERSION})."
    [[ "${EUID}" -ne 0 ]]              || _DIE "Ne pas lancer en root. Le script gère sudo lui-même."
    [[ -f /etc/fedora-release ]]       || _DIE "Fedora uniquement."

    # Vérification explicite des droits sudo (groupe wheel)
    if ! id -nG "${USER}" | grep -qw "wheel"; then
        _DIE "L'utilisateur ${USER} n'appartient pas au groupe 'wheel' (sudo). Abandon."
    fi

    # dépendances
    local deps
    local -a missing=()

    _OK "Contrôle des dépendances obligatoires"
    for deps in curl git stow pciutils dnf-plugins-core binutils policycoreutils-python-utils; do
        if ! rpm -q --quiet "${deps}"; then
            missing+=("${deps}")
        fi
    done

    if ((${#missing[@]})); then
        _RUN "Installation des dépendances obligatoires : ${missing[*]}" sudo dnf install -y "${missing[@]}"
    fi

    #
    local fedora_rel
    fedora_rel=$(cat /etc/fedora-release)
    _OK "Environnement valide — ${fedora_rel}, utilisateur ${USER} avec droits sudo"

    local heure
    heure=$(date '+%T')
    _OK "Heure de démarrage de la post-installation : ${heure}"
    _OK "Fichier log de la post-installation : ${LOG_FILE}"
}

########################################################################################################################
REMOVE_RPM_PACKAGES() {
    _SECTION " Suppression paquets indésirables " "━" "${C_GREEN}"

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
            _OK "${pkg} déjà supprimé"
        fi
    done

    if (( wants_systemd_networkd_removal )); then # par sécurité (si demandé) on ne dégage systemd-networkd qu'après assurance que NM est présent et actif
        if systemctl is-active --quiet NetworkManager; then
            if rpm -q systemd-networkd &>/dev/null; then
                _RUN "Suppression systemd-networkd (NetworkManager est bien actif)" sudo dnf remove -y systemd-networkd
            else
                _OK "systemd-networkd déjà supprimé"
            fi
        else
            _INFO "NetworkManager inactif — systemd-networkd conservé"
        fi
    fi
}

########################################################################################################################
INSTALL_REPOS() {
    _SECTION " Dépôts RPM " "━" "${C_GREEN}"

    local fedora_ver cache=0
    fedora_ver=$(rpm -E '%fedora')

    if ! rpm -q rpmfusion-free-release &>/dev/null; then
        _RUN "Ajout du dépôt RPM Fusion free (f${fedora_ver})" sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"${fedora_ver}".noarch.rpm
        _RUN "Ajout du dépôt RPM Fusion free tainted (f${fedora_ver})" sudo dnf install -y rpmfusion-free-release-tainted
        cache=1
    else
        _OK "Dépôt RPM Fusion free déjà présent"
    fi

    if ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
        _RUN "Ajout du dépôt RPM Fusion nonfree (f${fedora_ver})" sudo dnf install -y https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"${fedora_ver}".noarch.rpm
        _RUN "Ajout du dépôt RPM Fusion nonfree tainted (f${fedora_ver})" sudo dnf install -y rpmfusion-nonfree-release-tainted
        cache=1
    else
        _OK "Dépôt RPM Fusion nonfree déjà présent"
    fi

    if rpm -q rpmfusion-free-appstream-data &>/dev/null; then
        _RUN "Suppression métadonnées appstream free" sudo dnf remove -y rpmfusion-free-appstream-data
    fi
    if rpm -q rpmfusion-nonfree-appstream-data &>/dev/null; then
        _RUN "Suppression métadonnées appstream nonfree" sudo dnf remove -y rpmfusion-nonfree-appstream-data
    fi

    if ! rpm -q terra-release &>/dev/null; then
        # shellcheck disable=SC2016
        _RUN "Ajout du dépôt Terra (f${fedora_ver})" sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
        cache=1
    else
        _OK "Dépôt Terra déjà présent"
    fi

    if ! dnf repolist 2>/dev/null | grep -q "bigmenpixel:profile-sync-daemon"; then
        _RUN "Ajout du dépôt COPR profile-sync-daemon" sudo dnf copr enable -y bigmenpixel/profile-sync-daemon
        cache=1
    else
        _OK "Dépôt COPR profile-sync-daemon déjà présent"
    fi

    if ! dnf repolist 2>/dev/null | grep -q "brave-browser"; then
        _RUN "Ajout du dépôt Brave" sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        cache=1
    else
        _OK "Dépôt Brave déjà présent"
    fi
    if [[ "${cache}" -eq 1 ]]; then
        _RUN "Rafraîchissement des métadonnées" sudo dnf makecache
    fi
}

########################################################################################################################
INSTALL_FONTS() {
    _SECTION " Nerd Fonts " "━" "${C_GREEN}"

    local font
    for font in "${FONTS[@]}"; do
        if ! rpm -q "${font}" &>/dev/null; then
            _RUN "Installation ${font}" sudo dnf install -y "${font}"
        else
            _OK "${font} déjà présente"
        fi
    done
}

########################################################################################################################
INSTALL_CODECS() {
    _SECTION " Codecs multimédia " "━" "${C_GREEN}"

    # codecs
    if ! rpm -q ffmpeg &>/dev/null; then
        _RUN "Swap ffmpeg-free →  ffmpeg" sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
        _RUNSILENT "Mise à jour groupe multimedia." sudo dnf group upgrade multimedia --exclude=PackageKit-gstreamer-plugin -y
    else
        _OK "ffmpeg (rpmfusion) déjà présent"
        _OK "Groupe multimedia déjà à jour"
    fi
    if ! dnf repolist --enabled | grep -q '^fedora-cisco-openh264'; then
        _RUNSILENT "Activation Cisco h264." sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 -y
    else
        _OK "Cisco h264 déjà activé"
    fi

    # mesa swap
    local gpu_vendor
    gpu_vendor=$(lspci | grep -iE 'VGA|3D' | head -1 | tr '[:upper:]' '[:lower:]')
    _INFO "GPU détecté : ${gpu_vendor}"

    if echo "${gpu_vendor}" | grep -q "amd\|radeon\|advanced micro"; then
        if ! rpm -q mesa-va-drivers-freeworld &>/dev/null; then
            _RUN "Swap mesa-va-drivers → freeworld (AMD)" sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
        else
            _OK "Mesa freeworld déjà présent"
        fi
    elif echo "${gpu_vendor}" | grep -q "intel"; then
        if ! rpm -q intel-media-driver &>/dev/null; then
            _RUN "intel-media-driver" sudo dnf install -y intel-media-driver
        else
            _OK "intel-media-driver déjà présent"
        fi
    else
        _INFO "GPU ni AMD ni Intel => Pas de swap mesa à faire."
    fi
}

########################################################################################################################
INSTALL_RPM_PACKAGES() {
    _SECTION " Paquets RPM " "━" "${C_GREEN}"
    local pkg arch download_dir miss
    local -a missing_packages
    arch=$(uname -m)
    download_dir="./dnf-packages$$"
    missing_packages=()

    for pkg in "${DNF_PACKAGES[@]}"; do
        if ! rpm -q "${pkg}" &>/dev/null; then
            missing_packages+=("${pkg}")
        fi
    done

    if ((${#missing_packages[@]})); then
        miss=$(_FORMAT_LIST "${missing_packages[@]}")
        _RUNSILENT "" mkdir -pv "${download_dir}"
        _OK "Paquets manquants : ${miss}"
        _RUN "Téléchargement des paquets et dépendances manquants" sudo dnf download --skip-unavailable --arch "${arch}" --arch noarch --resolve --destdir="${download_dir}" -y "${missing_packages[@]}"
        _RUN "Installation des paquets manquants depuis le cache de téléchargement" sudo dnf install --skip-unavailable -y "${download_dir}"/*.rpm
        _RUNSILENT "" rm -rvf "${download_dir}"
    else
        _OK "Tous les paquets RPM demandés sont déjà installés"
    fi
}

########################################################################################################################
INSTALL_FLATPAK_PACKAGES() {
    _SECTION " Paquets Flatpak " "━" "${C_GREEN}"

    # 1. Vérification et installation de Flatpak
    # shellcheck disable=SC2310
    if ! _EXIST flatpak; then
        _RUN "Installation de Flatpak" sudo dnf install -y flatpak
    else
        _OK "Flatpak est déjà installé"
    fi

    # 2. Ajout de Flathub s'il n'existe pas
    if ! flatpak --columns=name remotes | grep -q "^flathub$"; then
        _RUN "Ajout du dépôt Flathub" sudo flatpak --verbose remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    else
        _OK "Dépot flathub déjà présent"
    fi

    # 3. Activation de Flathub sans filtre
    _RUNSILENT "" sudo flatpak --verbose remote-modify --no-filter --enable flathub

    # 4. Vérification et suppression du dépôt Fedora
    if flatpak remotes --columns=name | grep -q "^fedora$"; then
        _RUN "Suppression du dépôt Fedora Flatpak" sudo flatpak --verbose remote-delete --force fedora
    else
        _OK "Le dépôt Fedora Flatpak a déjà été supprimé"
    fi

    # 5. Installation des paquets depuis Flathub (System-wide par défaut avec sudo)
    if [[ ${#FLATPAK_PKGS[@]} -gt 0 ]]; then
        for pkg in "${FLATPAK_PKGS[@]}"; do
            if flatpak info "${pkg}" >/dev/null 2>&1; then
                _OK "Flatpak '${pkg}' est déjà installé"
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
SETUP_CHRONY() {
    # --- Configuration Chrony (IPv4 only si IPv6 désactivé) ---
    if echo "${CMDLINE}" | grep -q 'ipv6.disable=1'; then
        local chrony_file chrony_content
        chrony_file="/etc/sysconfig/chronyd"
        chrony_content=$'# Command-line options for chronyd\nOPTIONS="-F 2 -4"\n'
        readonly chrony_file chrony_content
        if [[ -f "${chrony_file}" ]] && echo "${chrony_content}" | sudo cmp -s - "${chrony_file}"; then
            _OK "Configuration chronyd déjà à jour (${chrony_file})"
        else
            _RUN "Configuration de chronyd (${chrony_file})" sudo install -v -m 644 -o root -g root /dev/stdin "${chrony_file}" <<< "${chrony_content}"
           _RUNSILENT "" sudo systemctl try-restart chronyd
        fi
    fi
}

########################################################################################################################
SETUP_GRUB(){
    local is_grub zswap
    is_grub=$(_DETECT_GRUB)
    zswap="zswap.enabled=1 zswap.compressor=lz4" # on force l'usage d'un zswap, plus efficace que zram car s'appuie sur un backend physique en plus (file ou part)

    _SECTION " Configuration de GRUB " "━" "${C_GREEN}"

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
            _RUN "Mise à jour des paramètres de GRUB (/etc/default/grub)" sudo sed -i -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=menu/' -e "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"${target_cmdline}\"|" /etc/default/grub

            if grep -q '^GRUB_TIMEOUT=' /etc/default/grub; then
                _RUN "Délai GRUB 2 sec (/etc/default/grub)" sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
            else
                _RUN "Délai GRUB 2 sec (/etc/default/grub)" sudo bash -c "echo 'GRUB_TIMEOUT=2' >> /etc/default/grub"
            fi

            _RUN "Regénération de la configuration de GRUB pour inclure les nouveaux paramètres (grub2-mkconfig)" sudo grub2-mkconfig -o /boot/grub2/grub.cfg
        else
            _OK "GRUB est déjà correctement configuré"
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
        _OK "Le service firewalld est déjà actif"
    fi

    # 3. Configuration des services essentiels
    local firewall_changed=false
    local service
    for service in "${FIREWALL_SERVICES[@]}"; do
        if sudo firewall-cmd --permanent --query-service="${service}" >/dev/null 2>&1; then
            _OK "Le service '${service}' est déjà autorisé"
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
SETUP_SWAP(){
    local target_size ram_total_kib
    local recreate_swap=false
    local swapdir="/var/swap"

    ram_total_kib=$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo)
    # SWAP = 2 x RAMtotal avec MAX 16Go
    SWAP_SIZE=$(( ram_total_kib * 2 / 1024 / 1024 ))
    SWAP_MAX=16
    if [[ "${SWAP_SIZE}" -gt "${SWAP_MAX}" ]]; then
        SWAP_SIZE=${SWAP_MAX}
    fi
    target_size=$(( SWAP_SIZE * 1024 * 1024 * 1024 ))


    if [[ -f "${swapdir}/swapfile" ]]; then
        local current_size
        current_size=$(sudo stat -c %s "${swapdir}/swapfile" 2>/dev/null || echo 0)

        if [[ "${current_size}" -ne "${target_size}" ]]; then
            _INFO "${swapdir}/swapfile existant mais taille différente de celle demandée (${current_size} octets). Recréation..."
            _RUNSILENT "" sudo swapoff "${swapdir}/swapfile"
            _RUNSILENT "" sudo rm -fv "${swapdir}/swapfile"
            recreate_swap=true
        else
            _OK "${swapdir}/swapfile est déjà correctement installé"
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
                    _OK "Sous-volume BTRFS ${swapdir} existe déjà"
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
        _OK "Swap déjà actif"
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
        _OK "Le module SELinux systemd_swap_search est déjà actif"
    fi
}

########################################################################################################################
SETUP_SUDO_RS() {
    _SECTION " Configuration sudo-rs " "━" "${C_GREEN}"
    local change=0
    # 1. On installe sudo-rs
    # shellcheck disable=SC2310
    if ! _EXIST sudo-rs; then
        _RUN "Installation de sudo-rs" sudo dnf install -y sudo-rs
        change=1
    fi

    # 2. Copie (sans suppression) des fichiers vers le monde sudo-rs
    local f_sudoers_rs="/etc/sudoers-rs"
    local d_sudoers_rs_d="/etc/sudoers-rs.d"

    if [[ -f "/etc/sudoers" && ! -f "${f_sudoers_rs}" ]]; then
        _RUN "Création de ${f_sudoers_rs} depuis l'original" sudo cp -a /etc/sudoers "${f_sudoers_rs}"
        change=1
    fi

    if [[ -d "/etc/sudoers.d" && ! -d "${d_sudoers_rs_d}" ]]; then
        _RUN "Création de ${d_sudoers_rs_d} depuis l'original" sudo cp -a /etc/sudoers.d "${d_sudoers_rs_d}"
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
    #shellcheck disable=SC2181
    [[ "${STATUSSYMLINK}" -eq 0 ]] && change=1 # le lien a bien été crée
    _RUNSILENT "" sudo chmod -v 4111 "${sudo_rs_bin}"
    _RUNSILENT "" sudo chmod -v 0000 "${sys_sudo_bak}"

    # 5. Déploiement des règles spécifiques
    local pattern="%wheel ALL=(ALL) NOPASSWD: /usr/bin/psd-overlay-helper"
    local file="${d_sudoers_rs_d}/90-profile-sync-daemon"
    if sudo test -f "${file}"; then
        if ! sudo grep -q "${pattern}" "${file}" > /dev/null; then
            _RUN "Mise à jour de la règle \"profile-sync-daemon\"." sudo bash -c "echo \"${pattern}\" > \"${file}\""
            change=1
        fi
    else
        _RUN "Création de la règle \"profile-sync-daemon\"." sudo bash -c "echo \"${pattern}\" > \"${file}\""
        change=1
    fi

    local pattern="Defaults pwfeedback,timestamp_timeout=60"
    local file2="${d_sudoers_rs_d}/99-timeout"
    if sudo test -f "${file2}"; then
        if ! sudo grep -q "${pattern}" "${file2}" > /dev/null; then
            _RUN "Mise à jour de la règle \"timeout\"." sudo bash -c "echo \"${pattern}\" > \"${file2}\""
            change=1
        fi
    else
        _RUN "Création de la règle \"timeout\"." sudo bash -c "echo \"${pattern}\" > \"${file2}\""
        change=1
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
        _RUNSILENT "" sudo rm -vrf /etc/sudoers.d
    fi
    _RUNSILENT "" sudo mkdir -pv /etc/sudoers.d
    _RUNSILENT "" sudo chmod -v 0750 /etc/sudoers.d

    # 7. Blocage propre des futures mises à jour du vieux sudo par DNF
    if ! sudo dnf versionlock list | grep -q sudo; then
        _RUNSILENT "" sudo dnf versionlock add sudo
        change=1
    fi
    if ! sudo grep -q sudo /etc/dnf/dnf.conf; then
        _RUNSILENT "" sudo crudini --verbose --set /etc/dnf/dnf.conf main excludepkgs 'sudo'
        change=1
    fi
    if [[ "${change}" -eq 1 ]]; then
        _OK "sudo-rs est en place et remplace définitivement sudo"
    else
        _OK "sudo-rs est déjà correctement configuré"
    fi
}



######################
MAIN "$@"

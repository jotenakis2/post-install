#!/usr/bin/env bash
# shellcheck disable=SC2310
# TODO sshd : email quand conn.
set -euo pipefail
if [[ -f ./post-install-common.sh ]]; then
    # shellcheck source=./post-install-common.sh
    source ./post-install-common.sh
else
    echo "post-install-common.sh manquant !"
    exit 1
fi
ROOT="no" # variable si script lancé en mode ROOT => shell only mode
DISTRO="unknown"
export ROOT DISTRO

########################################################################################################################
# FONCTIONS SPECIFIQUES FEDORA                                                                                         #
########################################################################################################################

########################################################################################################################
CHECK() {
    _BASH_CHECK
    if [[ ! -f /etc/fedora-release ]]; then
        echo -e "${C_RED}Fedora uniquement, abandon.${C_RESET}"
        exit 1
    fi
    _ROOT_CHECK
    #
    local fedora_rel
    fedora_rel=$(cat /etc/fedora-release)
    DISTRO="Fedora"
    echo ""
    if [[ "${ROOT,,}" = "yes" ]]; then
        echo -e "${C_GREEN}Environnement valide : ${fedora_rel}, utilisateur root, mode shellonly${C_RESET}"
    else
        echo -e "${C_GREEN}Environnement valide : ${fedora_rel}, utilisateur ${USER} avec droits sudo OK${C_RESET}"
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
            _INFO "Déjà OK : dépôt ${type}"
        else
            _RUN "Ajout du dépôt ${type}" _PKG_INSTALL https://mirrors.rpmfusion.org/"${rpmf}"/fedora/"${type}"-"${fedora_ver}".noarch.rpm
            _RUN "Ajout du dépôt ${type}-tainted" _PKG_INSTALL "${type}"-tainted
            cache=1
        fi
    done

    if [[ "${TERRA,,}" = "yes" ]]; then
        if _IS_PKG_INSTALLED terra-release; then
            _INFO "Déjà OK : dépôt Terra"
        else
            # shellcheck disable=SC2016
            _RUN "Ajout du dépôt Terra" sudo dnf install -y --nogpgcheck --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' terra-release
            cache=1
        fi
    fi

    # repo brave si besoin
    if _IN_ARRAY brave-browser "${SYSTEM_PACKAGES[@]}"; then
        if dnf repolist 2>/dev/null | grep -q "brave-browser"; then
            _INFO "Déjà OK : dépôt Brave"
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
        _INFO "Déjà OK : dépôt COPR ${repo}"
    else
        _RUN "Ajout du dépôt COPR ${repo}" sudo dnf copr enable -y "${repo}"
        localcache=1
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
        _INFO "Déjà OK : ffmpeg (rpmfusion)"
        _INFO "Déjà OK : groupe multimedia"
    fi
    if ! dnf repolist --enabled | grep -q '^fedora-cisco-openh264'; then
        _RUNSILENT "Activation Cisco h264." sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 -y
    else
        _LOG "Déjà OK : cisco h264"
    fi

    # mesa swap
    local gpu_vendor
    gpu_vendor=$(lspci | grep -iE 'VGA|3D' | head -1 | tr '[:upper:]' '[:lower:]')
    _LOG "GPU détecté : ${gpu_vendor}"

    if echo "${gpu_vendor}" | grep -q "amd\|radeon\|advanced micro"; then
        if ! _IS_PKG_INSTALLED mesa-va-drivers-freeworld; then
            _RUN "Installation mesa-va-drivers-freeworld" _PKG_INSTALL_SKIP mesa-va-drivers-freeworld
        else
            _INFO "Déjà OK : mesa-va-drivers-freeworld"
        fi
    elif echo "${gpu_vendor}" | grep -q "intel"; then
        if ! _IS_PKG_INSTALLED intel-media-driver; then
            _RUN "Installation intel-media-driver (rpmfusion)" _PKG_INSTALL_SKIP intel-media-driver
        else
            _INFO "Déjà OK : intel-media-driver (rpmfusion)"
        fi
    else
        _LOG "GPU : ni AMD ni Intel, pas de d'échange mesa <=> mesa (rpmfusion) à faire"
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

        # 2. Copie (sans suppression) des fichiers/dossiers vers le monde "sudo-rs"
        local f_sudoers_rs="/etc/sudoers-rs"
        local d_sudoers_rs_d="/etc/sudoers-rs.d"

        if [[ -f "/etc/sudoers" && ! -f "${f_sudoers_rs}" ]]; then
            _BACKUP_FILE "/etc/sudoers"
            _RUN "Création du fichier ${f_sudoers_rs} depuis /etc/sudoers" sudo cp -av /etc/sudoers "${f_sudoers_rs}"
            _ETC_FILES_ADD "${f_sudoers_rs}"
            change=1
        fi

        if [[ -d "/etc/sudoers.d" && ! -d "${d_sudoers_rs_d}" ]]; then
            _RUN "Création du dossier ${d_sudoers_rs_d} depuis /etc/sudoers.d" sudo cp -av /etc/sudoers.d "${d_sudoers_rs_d}"
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
                    echo -e '## Fallback pour les paquets Fedora\n@includedir /etc/sudoers.d' >> '${f_sudoers_rs}'
                fi
            "
            change=1
            _RUNSILENT "" sudo sed -i 's/(the # here does not mean a comment)$//' "${f_sudoers_rs}"
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

        if [[ "${current_link}" != "${sudo_rs_bin}" ]]; then # on backup le binaire sudo et on le remplace par un symlink vers sudo-rs
            _RUN "Remplacement du binaire sudo" sudo bash -c "
                if [[ -f '${sys_sudo}' && ! -L '${sys_sudo}' ]]; then
                    mv -vf '${sys_sudo}' '${sys_sudo_bak}'
                fi
                ln -svf '${sudo_rs_bin}' '${sys_sudo}'
            "
            change=1
        fi

        _PASS
        _SYMLINK "${sudo_rs_bin}" "${local_bin_sudo}"
        if grep -qxF 0 "${LINKFILE}" 2>/dev/null; then
            change=1
            _ETC_FILES_ADD "${local_bin_sudo}"
        fi # le lien a bien été crée
        _RUNSILENT "" sudo chmod -v 4111 "${sudo_rs_bin}"
        _RUNSILENT "" sudo chmod -v 0000 "${sys_sudo_bak}"

        # 5. Déploiement des règles spécifiques
        if _IN_ARRAY profile-sync-daemon "${SYSTEM_PACKAGES[@]}";then
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
        local file2="${d_sudoers_rs_d}/95-timeout"
        if sudo test -f "${file2}"; then
            if ! sudo grep -q "${pattern}" "${file2}" >/dev/null; then
                _RUN "Mise à jour de la règle \"timeout 60 minutes\"" sudo bash -c "echo \"${pattern}\" > \"${file2}\""
                change=1
                _ETC_FILES_ADD "${file2}"
            fi
        else
            _RUN "Création de la règle \"timeout 60 minutes\"" sudo bash -c "echo \"${pattern}\" > \"${file2}\""
            change=1
            _ETC_FILES_ADD "${file2}"
        fi

        _RUNSILENT "" sudo chmod -v 0440 "${f_sudoers_rs}"
        _RUNSILENT "" sudo chmod -v 0750 "${d_sudoers_rs_d}"
        _RUNSILENT "" sudo chmod -v 0440 "${file}" "${file2}"

        # 6. Nettoyage des anciens fichiers
        if [[ -f "/etc/sudoers" && ! -L "/etc/sudoers" ]]; then
            _BACKUP_FILE "/etc/sudoers"
            _RUNSILENT "" sudo rm -vf -- "/etc/sudoers"
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
            _BACKUP_FILE "/etc/dnf/dnf.conf"
            _RUNSILENT "" sudo dnf config-manager setopt excludepkgs=sudo
            change=1
            _ETC_FILES_ADD "/etc/dnf/dnf.conf"
        fi
        if [[ "${change}" -eq 1 ]]; then
            _OK "sudo-rs OK (remplace sudo)"
        else
            _INFO "Déjà OK : sudo-rs remplace sudo"
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
        is_grub=$(_DETECT_GRUB)
        if [[ "${is_grub}" = "true" ]]; then
            linux=$(printf '%s\n' /boot/vmlinuz*cachy* | sort -V | tail -1)
            _RUN "Noyau ${linux} configuré par défaut dans GRUB" sudo grubby --set-default="${linux}"

            # script pour forcer le dernier kernel cachyos dans GRUB
            local contentscript scriptfile dirscript
            contentscript=$(cat <<'EOF'
#!/usr/bin/env bash
linux=$(find /boot/vmlinuz*cachy* 2>/dev/null | sort -V | tail -1) || true
if [[ -n "${linux}" ]]; then
        echo "Noyau cachyos : ${linux}"
        if command -v grubby &>/dev/null; then
                sudo grubby --set-default="${linux}"
        else
                echo "grubby non trouvé"
                exit 1
        fi
else
        echo "Aucun noyau cachyos détecté"
fi


EOF
)
            dirscript="/usr/local/bin"
            scriptfile="${dirscript}/set-cachyos_kernel-default-in-GRUB.sh"
            _RUNSILENT "" sudo mkdir -pv "${dirscript}"
            _INSTALL_ETC_FILES "Script set-cachyos_kernel-default-in-GRUB.sh" "${contentscript}" "${scriptfile}" "755"
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
            rpm -qa | grep -i cachyos || true
            echo "---------------------"
        } >> "${LOG_FILE:-/dev/null}"
    fi
}


######################
MAIN "$@"

#!/usr/bin/env bash
set -euo pipefail

################################################################
#   Paramètres utilisateur de post-install-fedora.sh           #
################################################################
# Note: le script ne permet un retour en arrière si l'utilisateur change d'avis !


XDG_PICTURES_DIR="$(xdg-user-dir PICTURES)"
XDG_DOCUMENTS_DIR="$(xdg-user-dir DOCUMENTS)"

################################################################
# Activation/désactivation de certaines fonctions : yes/no     #
################################################################



# remplace sudo par sudo-rs
SUDORS="yes"

# activation / configuration server ssh
ACTIVATE_SSHD="yes"

# si yes, zram éventuel supprimé et remplacé par zswap avec un backend swapfile
ZSWAP="yes"

# pour télécharger oh-my-posh pour l'utilisateur qui lance le script
USE_OH_MY_POSH_PROMPT="yes"

# force une maj des repos git à chaque exécution du script
UPDATE_GIT_REPOS="yes"

# force une maj des liens symboliques des dotfiles utilisateurs (reSTOW)
RESTOW="yes"

# pour empécher la génération de dump mémoire en cas de crash d'une app
DISABLE_COREDUMP="yes"

# pour désactiver le boot graphique (plymouth sera désinstallé)
DISABLE_PLYMOUTH="yes"

# diverses robustifications de sécurité
HARDENING="yes"

# supprime support ipv6 dans le kernel et services
DISABLE_IPV6="yes"

# supprime gnome-logiciels et/ou plasma-discover (ainsi que PackageKit)
DISABLE_DNF_GUI="yes"

# si capteur d'empreinte non supporté autant tout désactiver autour de cette fonction
DISABLE_FINGERPRINT="yes"

# installation/configuration du noyau optimisé de cachyOS (via un copr fedora)
ENABLE_CACHYOS_KERNEL="yes"

# pour installer le dépôt additionnel Terra (Fedora)
TERRA="yes"

# standard, black, blue, brown, green, grey, orange, pink, purple, red, yellow, manjaro, ubuntu, nord, ou dracula.
VARIANT_COLOR_TELA_ICONS="purple"

# WIFI économie d'énergie OFF (parfois utile si déco/reco fréquente)
WIFI_POWERSAVE="yes"

################################################################
# Configurations diverses                                      #
################################################################

# nom de la machine (si vide on ne change pas le nom de l'installer) ---------------------------------------------------------
MYHOSTNAME="MyFedoraBTW"

# paquets système à installer ----------------------------------------------------------------------------------------------------
SYSTEM_PACKAGES=(
    fastfetch alacritty fzf bat-extras grc axel rclone procs msmtp s-nail chkrootkit rkhunter
    wl-clipboard glow expect sqlite btop atop glances nvtop iftop gdu duf kate shfmt ShellCheck inxi
    nodejs-bash-language-server make mpv vlc libdvdcss foliate imv plasma-login-manager thunderbird helium-browser-bin
    vesktop qbittorrent qemu virt-manager virt-viewer gum stress-ng lynis
    libreoffice-langpack-fr nss-tools ldns-utils profile-sync-daemon htop micro konversation libpcap-devel
    # Ajoute tes autres paquets ici
)

# paquets système à désinstaller -------------------------------------------------------------------------------------------------
SYSTEM_REMOVE=(
    rsyslog akonadi-server kdeconnectd nano libreswan at systemd-networkd catatonit
    plasma-drkonqi ibus imsettings maliit-keyboard abrt sudo-python-plugin sssd-common mcelog
    # cockpit
    cockpit-bridge cockpit-networkmanager cockpit-storaged cockpit-system cockpit-ws cockpit-ws-selinux
    # fonts asiatiques
    default-fonts-cjk-mono
    default-fonts-cjk-sans
    default-fonts-cjk-serif
    default-fonts-other-mono
    default-fonts-other-sans
    default-fonts-other-serif
    # firmware inutile sur HP EliteBook 645 14 inch G9 Notebook PC :
    nxpwireless-firmware
    tiwilink-firmware
    brcmfmac-firmware
    alsa-sof-firmware
    qcom-wwan-firmware
    realtek-firmware
    iwlwifi-mld-firmware
    iwlwifi-mvm-firmware
    iwlwifi-dvm-firmware
    iwlegacy-firmware
    libertas-firmware
    intel-audio-firmware
    cirrus-audio-firmware
    mt7xxx-firmware
    intel-vsc-firmware
    intel-gpu-firmware
    # Ajoute tes autres paquets ici
)

# polices à installer (les 2 nerd font ici sont dans le dépôt Terra qui est ajouté automatiquement) --------------------------
FONTS=(
    jetbrainsmono-nerd-fonts
    iosevka-nerd-fonts
    terminus-fonts-console
    # Ajoute tes autres paquets ici
)

# font console
VCONSOLE_FONT="ter-v18b"

# paquets flatpak à installer
FLATPAK_PKGS=(
    "com.ktechpit.whatsie"
    "io.github.giantpinkrobots.flatsweep"
    "com.github.tchx84.Flatseal"
    "io.github.forkgram.tdesktop"
    # Ajoute tes autres paquets ici
)

# outils cargo (rust) à installer
CARGO_PACKAGES=(
    cargo-update bandwhich bat bottom diskus fd-find hyperfine netscanner parallel-disk-usage resvg 
    ripgrep sd sheldon tealdeer 
    yazi-fm yazi-cli
    zoxide zsh-patina eza netwatch-tui syswatch shuck-cli sdctl
    # Ajoute tes autres paquets ici
)

# mapping cargo "nom paquet" <=> "binaire installé"
declare -A BIN_MAPPING=(
    ["yazi-fm"]="yazi"
    ["yazi-cli"]="ya"
    ["shuck-cli"]="shuck"
    ["tealdeer"]="tldr"
    ["parallel-disk-usage"]="pdu"
    ["fd-find"]="fd"
    ["bottom"]="btm"
    ["ripgrep"]="rg"
    ["netwatch-tui"]="netwatch"
    ["cargo-update"]="cargo-install-update cargo-install-update-config"
    # Ajoute tes autres correspondances nécessaires ici
)

# outils GO
declare -A GO_PACKAGES=(
    ["stormy"]="github.com/ashish0kumar/stormy@latest"
    ["golazo"]="github.com/0xjuanma/golazo@latest"
    ["radiogogo"]="github.com/zi0p4tch0/radiogogo@latest"
    ["xytz"]="github.com/xdagiz/xytz@latest"
    ["speedtest-go"]="github.com/showwin/speedtest-go@latest"
    # Ajoute tes autres paquets ici
)

# Repos git à installer (repo dotfiles obligatoire, autres optionnels)
MYREPOS="https://codeberg.org/jotenakis"
DOTFILES_REPO="${MYREPOS}/dotfiles"
DOTFILES_DIR="${HOME}/dotfiles"
GIT_REPOS=(
    "${MYREPOS}/fedupdate"
    "${MYREPOS}/backupsystem"
    "${MYREPOS}/scripts"
    "https://github.com/JeromeTDev/radiosh"
    # Ajoute tes autres repos ici
)

# services réseaux à autoriser dans le pare-feu
FIREWALL_SERVICES=(
    "mdns"
    "ipp-client"
    "samba-client"
    # ajoute tes autres services réseaux à autoriser ici
)

# services systemd à désactiver
declare -A SERVICES_TO_DISABLE=(
    ["ModemManager.service"]="service ModemManager (modem 4G/5G)"
    ["switcheroo-control.service"]="service switcheroo (GPU hybride)"
    ["flatpak-add-fedora-repos.service"]="service fedora flatpak repo"
    ["mdmonitor.service"]="service Software RAID monitoring and management"
    #["lvm2-monitor.service"]="service Monitoring LVM"
    ["pcscd.socket"]="socket PC/SC Smart Card Daemon"
    ["lm_sensors.service"]="service Hardware Monitoring Sensors (collecte)"
    ["authselect-apply-changes.service"]="service Apply authselect changes (PAM)"
    ["raid-check.timer"]="timer Weekly RAID setup health check"
    ["iscsid.socket"]="socket Open-iSCSI iscsid"
    ["iscsiuio.socket"]="socket Open-iSCSI iscsiuio"
    #["lvm2-lvmpolld.socket"]="socket LVM poll"
    ["systemd-oomd.socket"]="socket Out of Memory Killer"
    ["systemd-oomd.service"]="service Out of Memory Killer"
    ["thermald.service"]="service thermald"
    ["NetworkManager-wait-online.service"]="service d'attente réseau"
    # ajoute tes autres services systemd à désactiver ici
)

# services systemd --user à activer
declare -A USER_SERVICES_TO_ENABLE=(
    ["psd.service"]="service profile-sync-daemon"
    # ajoute tes autres services systemd à désactiver ici
)

# configuration du noyau
SYSCTL_CONF='# optimisation by post-install script by jotenakis
vm.vfs_cache_pressure = 50
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
vm.dirty_bytes = 335544320
vm.dirty_background_bytes = 167772160
vm.dirty_writeback_centisecs = 1000
vm.dirty_expire_centisecs = 2000
net.core.somaxconn = 8192
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
kernel.task_delayacct = 1
kernel.soft_watchdog = 0
kernel.watchdog = 0
'

# configuration pour débloater brave browser
# shellcheck disable=SC2089
BRAVE_POLICIES='{
    "BraveRewardsDisabled": true,
    "BraveWalletDisabled": true,
    "BraveVPNDisabled": 1,
    "BraveAIChatEnabled": false,
    "TorDisabled": true,
    "PasswordManagerEnabled": false,
    "DnsOverHttpsMode": "automatic"
}
'

# config DNS
RESOLVED_DNS_SERVERS='[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net
FallbackDNS=1.1.1.1#one.one.one.one
Domains=~.
DNSOverTLS=yes
DNSSEC=yes
'

# port du service SSH
SSHD_CONFIG_PORT="22"

# Couleur du TTY (console virtuelle non graphique)
TTY_COLOR="vt.default_red=30,243,166,249,137,245,148,186,88,243,166,249,137,245,148,166 vt.default_grn=30,139,227,226,180,194,226,194,91,139,227,226,180,194,226,173 vt.default_blu=46,168,161,175,250,231,213,222,112,168,161,175,250,231,213,200" #catppuccin mocha

# paramètres additionels optionnels de la ligne de commande du noyau
CMDLINE="" #skew_tick=1

# position du panneau de KDE (top, bottom, right, left)
KDEPANEL="top"

# Partage NFS
NFS_SHARE="192.168.50.51:/mnt/usbdrive/data"

# Point de montage NFS
NFS_MP="/media/NAS"

# règle udev persistante (par ex : clé usb) personnalisé
# shellcheck disable=SC2089,SC2016
UDEVRULE='# clé NVMe
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="b6fed99c-7c1a-4146-a445-f2660c01146e", ENV{UDISKS_IGNORE}="1", RUN{program}+="/usr/bin/systemd-mount --no-block --automount=yes --collect $devnode /media/cleNVME", RUN{program}+="/bin/chown -R 1000:1000 /media/cleNVME"
'

# description de la règle udev persistante
UDEVDESCR="NVMeKEY"

#Données privées à restaurer : dossier source
SOURCE="/media/NAS/backup/data2restore"

#Données privées à restaurer : binaire à surveiller
declare -A COMMANDS=(
    ["FIREFOX"]="firefox"
    ["BRAVE"]="brave"
    ["IPTVNATOR"]="iptvnator.bin"
    ["HELIUM"]="helium"
    ["DISCORD"]="vesktop"
    # Ajoute les liens binaires à tuer avant de restaurer pour chaque PROFIL (important pour les navigateurs)
)

#Données privées à restaurer : dossiers de destinations
# shellcheck disable=SC2154
declare -A DESTINATIONS=(
    ["FIREFOX"]="${HOME}/.mozilla/firefox"
    ["BRAVE"]="${HOME}/.config/BraveSoftware/Brave-Browser"
    ["SSH"]="${HOME}/.ssh"
    ["IPTVNATOR"]="${HOME}/.config/iptvnator"
    ["SSHMANAGER"]="${HOME}/.local/share/sshmanager"
    ["HELIUM"]="${HOME}/.config/net.imput.helium"
    ["MSMTP"]="${HOME}/.config/msmtp"
    ["MOK"]="${HOME}/mok-cachyos"
    ["DISCORD"]="${HOME}/.config/vesktop"
    ["IMAGES"]="${XDG_PICTURES_DIR:-}"
    ["DOCUMENTS"]="${XDG_DOCUMENTS_DIR:-}"
    ["ZSH_HISTORY"]="${HOME}/.local/share/zsh"
)









###################################################################
# /!\              NE RIEN MODIFIER CI-DESSOUS               /!\  #
###################################################################
export SYSTEM_PACKAGES
export SYSTEM_REMOVE
export FONTS
export FLATPAK_PKGS
export CARGO_PACKAGES
export BIN_MAPPING
export GO_PACKAGES
export MYREPOS
export DOTFILES_REPO
export DOTFILES_DIR
export GIT_REPOS
export FIREWALL_SERVICES
export SERVICES_TO_DISABLE
export USER_SERVICES_TO_ENABLE
export SYSCTL_CONF
# shellcheck disable=SC2090
export BRAVE_POLICIES
export RESOLVED_DNS_SERVERS
export TTY_COLOR
export CMDLINE
export KDEPANEL
export NFS_SHARE
export NFS_MP
# shellcheck disable=SC2090
export UDEVRULE
export UDEVDESCR
export MYHOSTNAME
export SOURCE
export COMMANDS
export DESTINATIONS
export SSHD_CONFIG_PORT
export ACTIVATE_SSHD
export VCONSOLE_FONT
export ZSWAP
export SUDORS
export USE_OH_MY_POSH_PROMPT
export UPDATE_GIT_REPOS
export RESTOW
export DISABLE_COREDUMP
export DISABLE_PLYMOUTH
export HARDENING
export DISABLE_IPV6
export DISABLE_DNF_GUI
export DISABLE_FINGERPRINT
export ENABLE_CACHYOS_KERNEL
export XDG_PICTURES_DIR
export XDG_DOCUMENTS_DIR
export TERRA
export VARIANT_COLOR_TELA_ICONS
export WIFI_POWERSAVE
###############################################################################################################################

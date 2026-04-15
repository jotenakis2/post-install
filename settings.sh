#!/usr/bin/env bash
########################################################
#   Paramètres utilisateur de post-install-fedora.sh   #
########################################################

# nom de la machine (si vide on ne change pas le nom de l'installer) #--------------------------------------------------------
HOSTNAME="MyFedoraBTW"
#-----------------------------------------------------------------------------------------------------------------------------


# paquets RPM à installer #---------------------------------------------------------------------------------------------------
DNF_PACKAGES=(
    zsh fastfetch util-linux-script foot ghostty fzf bat-extras grc axel rclone procs
    wl-clipboard glow expect sqlite btop atop glances nvtop gping iftop gdu duf speedtest-cli kate shfmt ShellCheck inxi
    nodejs-bash-language-server make mpv vlc libdvdcss foliate imv plasma-login-manager thunderbird helium-browser-bin
    vesktop telegram-desktop qbittorrent brave-browser qemu virt-manager virt-viewer gum stress-ng
    libreoffice-langpack-fr nss-tools ldns-utils profile-sync-daemon htop micro konversation
    # Ajoute tes autres paquets ici
)
#-----------------------------------------------------------------------------------------------------------------------------


# paquets RPM à désinstaller #------------------------------------------------------------------------------------------------
DNF_REMOVE=(
    zram-generator-defaults PackageKit-glib google-noto-sans-mono-cjk-vf-fonts akonadi-server kdeconnectd
    libreswan plasma-drkonqi ibus imsettings maliit-keyboard abrt plasma-discover rsyslog konsole konsole-part
    # Ajoute tes autres paquets ici
)
#-----------------------------------------------------------------------------------------------------------------------------


# polices à installer (les 2 nerd font ici sont dans le dépôt Terra qui est ajouté automatiquement) #-------------------------
FONTS=(
    jetbrainsmono-nerd-fonts
    iosevka-nerd-fonts
    # Ajoute tes autres paquets ici
)
#-----------------------------------------------------------------------------------------------------------------------------


# paquets flatpak à installer #-----------------------------------------------------------------------------------------------
FLATPAK_PKGS=(
    "com.ktechpit.whatsie"
    "io.github.giantpinkrobots.flatsweep"
    "com.github.tchx84.Flatseal"
    # Ajoute tes autres paquets ici
)
#-----------------------------------------------------------------------------------------------------------------------------


# outils cargo (rust) à installer et mapping "nom paquet" <=> "binaire installé" #--------------------------------------------
CARGO_PACKAGES=(
    cargo-update bandwhich bat bottom diskus fd-find hyperfine netscanner parallel-disk-usage resvg
    ripgrep sd sheldon tealdeer yazi-fm yazi-cli zoxide zsh-patina eza
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
#-----------------------------------------------------------------------------------------------------------------------------


# outils GO #-----------------------------------------------------------------------------------------------------------------
declare -A GO_PACKAGES=(
    ["stormy"]="github.com/ashish0kumar/stormy@latest"
    ["golazo"]="github.com/0xjuanma/golazo@latest"
    ["radiogogo"]="github.com/zi0p4tch0/radiogogo@latest"
    ["xytz"]="github.com/xdagiz/xytz@latest"
    ["matcha"]="github.com/floatpane/matcha@latest"
    # Ajoute tes autres paquets ici
)
#-----------------------------------------------------------------------------------------------------------------------------


# mes repos git à installer (dotfiles obligatoire) #--------------------------------------------------------------------------
MYREPOS="https://codeberg.org/jotenakis"
DOTFILES_REPO="${MYREPOS}/dotfiles"
DOTFILES_DIR="${HOME}/dotfiles"
GIT_REPOS=(
    "${MYREPOS}/fedupdate|${HOME}/fedupdate"
    "${MYREPOS}/backupsystem|${HOME}/backupsystem"
    "${MYREPOS}/scripts|${HOME}/scripts"
    "${DOTFILES_REPO}|${DOTFILES_DIR}"
    # Ajoute tes autres "repos|dossierlocaux" ici
)
#-----------------------------------------------------------------------------------------------------------------------------


# services réseaux à autoriser dans le pare-feu #-----------------------------------------------------------------------------
FIREWALL_SERVICES=(
    "mdns"
    "ipp-client"
    "samba-client"
    # ajoute tes autres services réseaux à autoriser ici
)
#-----------------------------------------------------------------------------------------------------------------------------


# services systemd à désactiver #---------------------------------------------------------------------------------------------
declare -A SERVICES_TO_DISABLE=(
    ["ModemManager.service"]="service ModemManager"
    ["switcheroo-control.service"]="service switcheroo"
    # ajoute tes autres services systemd à désactiver ici
)
#-----------------------------------------------------------------------------------------------------------------------------


# configuration du noyau #----------------------------------------------------------------------------------------------------
SYSCTL_CONF='
# optimizing
vm.swappiness = 10
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
net.ipv4.conf.default.rp_filter = 1
'
#-----------------------------------------------------------------------------------------------------------------------------


# configuration pour débloater brave browser #--------------------------------------------------------------------------------
# shellcheck disable=SC2089
BRAVE_POLICIES='{
    "BraveRewardsDisabled": true,
    "BraveWalletDisabled": true,
    "BraveVPNDisabled": 1,
    "BraveAIChatEnabled": false,
    "TorDisabled": true,
    "PasswordManagerEnabled": false,
    "DnsOverHttpsMode": "automatic"
}'
#-----------------------------------------------------------------------------------------------------------------------------


# conf DNS #------------------------------------------------------------------------------------------------------------------
RESOLVED_DNS_SERVERS='[Resolve]
DNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net
FallbackDNS=1.1.1.1#one.one.one.one
Domains=~.
DNSOverTLS=yes
DNSSEC=yes
' # dot quad9, fallback dot cloudflare, DNSSEC on, pour toutes les résolutions externes.
#-----------------------------------------------------------------------------------------------------------------------------


# taille du fichier swap en GiB (/var/swap/swapfile) #------------------------------------------------------------------------
SWAP_SIZE=8
#-----------------------------------------------------------------------------------------------------------------------------


# Couleur du TTY (console virtuelle non graphique) #--------------------------------------------------------------------------
TTY_COLOR="vt.default_red=30,243,166,249,137,245,148,186,88,243,166,249,137,245,148,166 vt.default_grn=30,139,227,226,180,194,226,194,91,139,227,226,180,194,226,173 vt.default_blu=46,168,161,175,250,231,213,222,112,168,161,175,250,231,213,200" #catppuccin mocha
#-----------------------------------------------------------------------------------------------------------------------------


# paramètres additionels de la ligne de commande du noyau (zswap sera automatiquement ajouté même si non spécifié ici) -------
CMDLINE="ipv6.disable=1"
#-----------------------------------------------------------------------------------------------------------------------------


# paramètres additionels de la ligne de commande du noyau (zswap sera automatiquement ajouté même si non spécifié ici) -------
KDEPANEL="top"
#-----------------------------------------------------------------------------------------------------------------------------


# Montage NFS #---------------------------------------------------------------------------------------------------------------
NFS_SHARE="192.168.50.51:/mnt/usbdrive/data"
NFS_MP="/media/NAS"
#-----------------------------------------------------------------------------------------------------------------------------


# règle udev persistante #----------------------------------------------------------------------------------------------------
UDEVDESCR="Clé NVME"
UDEVFILE="99-nvme-key.rules"
# shellcheck disable=SC2089,SC2016
UDEVRULE='# clé nvme
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="b6fed99c-7c1a-4146-a445-f2660c01146e", ENV{UDISKS_IGNORE}="1", RUN{program}+="/usr/bin/systemd-mount --no-block --automount=yes --collect $devnode /media/cleNVME", RUN{program}+="/bin/chown -R 1000:1000 /media/cleNVME"
'
#-----------------------------------------------------------------------------------------------------------------------------


# Données privées à restaurer #-----------------------------------------------------------------------------------------------
SOURCE="/media/NAS/backup/data2restore"
declare -A COMMANDS=(
   ["FIREFOX"]="firefox"
   ["BRAVE"]="brave"
   ["SSH"]=""
   ["IPTVNATOR"]="iptvnator.bin"
   ["SSHMANAGER"]=""
   ["HELIUM"]="helium"
        # Ajoute les liens binaires à tuer avant de restaurer pour chaque PROFIL (important pour les navigateurs)
)
declare -A DESTINATIONS=(
   ["FIREFOX"]="${HOME}/.mozilla/firefox/"
   ["BRAVE"]="${HOME}/.config/BraveSoftware/Brave-Browser/"
   ["SSH"]="${HOME}/.ssh/"
   ["IPTVNATOR"]="${HOME}/.config/iptvnator/"
   ["SSHMANAGER"]="${HOME}/.local/share/sshmanager/"
   ["HELIUM"]="${HOME}/.config/net.imput.helium/"
)
#-----------------------------------------------------------------------------------------------------------------------------


###############################################################################################################################
###############################################################################################################################
###############################################################################################################################
export DNF_PACKAGES
export DNF_REMOVE
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
export SYSCTL_CONF
# shellcheck disable=SC2090
export BRAVE_POLICIES
export RESOLVED_DNS_SERVERS
export SWAP_SIZE
export TTY_COLOR
export CMDLINE
export KDEPANEL
export NFS_SHARE
export NFS_MP
export UDEVFILE
# shellcheck disable=SC2090
export UDEVRULE
export UDEVDESCR
export HOSTNAME
export PROFILES
export SOURCE
export COMMANDS
export DESTINATIONS
###############################################################################################################################

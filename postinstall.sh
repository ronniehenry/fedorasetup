#!/usr/bin/env bash
#
# Fedora post-install script
# Usage: ./postinstall.sh --host <hostname>

set -euo pipefail

log() { echo -e "\n\033[1;32m==>\033[0m $*"; }

# dnf swap requires the "remove" package to be currently installed - it fails
# on a rerun once the swap has already happened. This guards it so the script
# is safe to run again on an already-provisioned system.
swap_if_installed() {
    local remove_pkg="$1" install_pkg="$2"
    if rpm -q "$remove_pkg" &>/dev/null; then
        sudo dnf swap -y "$remove_pkg" "$install_pkg" --allowerasing
    else
        log "$remove_pkg not installed, skipping swap (assuming $install_pkg already in place)"
        sudo dnf install -y "$install_pkg"
    fi
}

# ---- parse args ----
MYHOSTNAME=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --host) MYHOSTNAME="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$MYHOSTNAME" ]]; then
    echo "Error: --host <hostname> is required"
    exit 1
fi

# ---- dnf tuning ----
log "Configuring /etc/dnf/dnf.conf"
sudo tee /etc/dnf/dnf.conf > /dev/null << 'EOF'
[main]
max_parallel_downloads=20
fastestmirror=True
EOF
sudo dnf -y upgrade

# ---- RPM Fusion ----
log "Setting up RPM Fusion"
sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

# ---- core upgrade ----
log "Upgrading core group and system packages"
sudo dnf group upgrade -y core
sudo dnf -y update

# ---- Snapper + grub-btrfs rollback protection ----
# Placed here (after RPM Fusion/core upgrade, before firmware/codecs/etc.) so a
# rollback point exists before the riskier repo/codec steps below run.
# This is deliberately NOT timed snapshots - snapper-timeline.timer is disabled.
# python3-dnf-plugin-snapper is DNF4-only and does not hook into dnf5, which is
# Fedora's default `dnf` since F41 - that's why snapshots never fired
# automatically. libdnf5-plugin-actions is the dnf5-native replacement; the
# actions file below reimplements the same pre/post transaction behavior.
log "Setting up Snapper + grub-btrfs"
sudo dnf install -y snapper libdnf5-plugin-actions

if ! sudo snapper list-configs | grep -q '^root'; then
    sudo snapper -c root create-config /
else
    log "Snapper root config already exists, skipping create-config"
fi
sudo chmod a+rx /.snapshots

sudo mkdir -p /etc/dnf/libdnf5-plugins/actions.d
sudo tee /etc/dnf/libdnf5-plugins/actions.d/snapper.actions > /dev/null << 'EOF'
# Emulates the old DNF4 snapper plugin under dnf5's actions-plugin architecture.
# Creates a pre snapshot before the transaction, storing its number + description.
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_desc=$(ps\ -o\ command\ --no-headers\ -p\ '${pid}')"
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ create\ -t\ pre\ -c\ number\ -p\ -d\ '${tmp.snapper_desc}')"
# Creates the matching post snapshot once the transaction completes.
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ create\ -t\ post\ -c\ number\ --pre-number\ "${tmp.snapper_pre_number}"\ -d\ "${tmp.snapper_desc}";\ echo\ tmp.snapper_pre_number\ ;\ echo\ tmp.snapper_desc
EOF

# dnf-triggered pre/post snapshots have no Cleanup algorithm by default, so
# with snapper-timeline disabled nothing would ever prune them. Cap by count
# instead so snapper-cleanup.timer (still enabled) has something to act on.
sudo snapper -c root set-config NUMBER_CLEANUP=yes NUMBER_LIMIT=20 NUMBER_LIMIT_IMPORTANT=10

sudo systemctl disable --now snapper-timeline.timer 2>/dev/null || true
sudo systemctl enable --now snapper-cleanup.timer

sudo dnf copr enable -y kylegospo/grub-btrfs
sudo dnf install -y grub-btrfs

# Fedora's default layout makes .snapshots a nested subvolume, not a real mount
# point, so the packaged grub-btrfs.path unit's mount dependency never
# resolves. Override it to watch the path directly instead.
sudo tee /etc/systemd/system/grub-btrfs.path > /dev/null << 'EOF'
[Unit]
Description=Monitors for new snapshots

[Path]
PathModified=/.snapshots

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now grub-btrfs.path
sudo grub2-mkconfig -o "$(readlink -f /etc/grub2.cfg)"

log "REMINDER: reboot and confirm the 'Fedora Linux snapshots' submenu appears in GRUB before trusting this setup."

# ---- firmware ----
log "Checking firmware updates"
sudo fwupdmgr refresh --force
sudo fwupdmgr get-devices
sudo fwupdmgr get-updates || true   # exits non-zero if no updates available; don't kill the script
sudo fwupdmgr update -y || rc=$?
if [[ ${rc:-0} -ne 0 && ${rc:-0} -ne 2 ]]; then
    log "fwupdmgr update failed with exit code $rc"
    exit "$rc"
fi

# ---- Flatpak / Flathub ----
log "Configuring Flathub"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# ---- media codecs ----
log "Installing multimedia codecs"
sudo dnf group install -y multimedia
swap_if_installed 'ffmpeg-free' 'ffmpeg'
sudo dnf upgrade -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf group install -y sound-and-video

# ---- HW video decoding (VA-API) ----
log "Setting up VA-API hardware video decoding"
sudo dnf install -y ffmpeg-libs libva libva-utils
swap_if_installed libva-intel-media-driver intel-media-driver

# ---- H.264 for Firefox ----
log "Enabling H.264 support for Firefox"
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
sudo dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264

# ---- hostname ----
log "Setting hostname to $MYHOSTNAME"
sudo hostnamectl set-hostname "$MYHOSTNAME"

# ---- default editor ----
log "Switching default editor to vim"
sudo dnf remove -y nano-default-editor
sudo dnf install -y vim-default-editor

# ---- change terminal ----
log "Removing Pytxis and installing Ghostty"
sudo dnf copr enable -y scottames/ghostty
sudo dnf install -y ghostty
sudo dnf remove -y ptyxis
gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty'

# ---- GNOME Shell extensions ----
log "Installing GNOME Shell extensions"
sudo dnf install -y \
    gnome-shell-extension-dash-to-dock \
    gnome-shell-extension-user-theme \
    gnome-shell-extension-appindicator

# Extensions are left disabled here - gnome-extensions enable requires a live
# D-Bus session that hasn't scanned these yet, so enable them manually via
# Extension Manager or GNOME Extensions after logging in.

# ---- package groups + individual packages ----
log "Installing package groups and dev tools"
sudo dnf group install -y development-tools c-development editors vlc
sudo dnf install -y gnome-tweaks gimp inkscape transmission-gtk

# ---- VS Code ----
log "Installing VS Code"
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
sudo tee /etc/yum.repos.d/vscode.repo > /dev/null << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
sudo dnf check-update || true   # returns exit code 100 when updates are available; not a failure
sudo dnf install -y code

# ---- flatpak apps ----
log "Installing Flatpak apps"
flatpak install -y flathub \
    org.strawberrymusicplayer.strawberry \
    io.github.getnf.embellish \
    com.mattjakeman.ExtensionManager

# ---- archive support ----
log "Installing archive format support"
sudo dnf install -y unzip p7zip p7zip-plugins unrar

# ---- install custom cursors ----
log "Installing custom cursors"
sudo dnf copr enable -y peterwu/rendezvous
sudo dnf install -y bibata-cursor-themes

# ---- install favorite fonts ----
log "Installing custom fonts"
sudo dnf install -y lato-fonts

# ---- install custom icons ----
log "Installing custom icons"
sudo dnf install -y papirus-icon-theme

# ---- set icon colors ----
log "Installing script to set custom icon colors"
wget -qO- https://git.io/papirus-folders-install | sh
papirus-folders -C green --theme Papirus-Dark

# ---- zsh + oh-my-zsh ----
log "Installing zsh and Oh My Zsh"
sudo dnf install -y zsh
# --unattended: skip the interactive prompt and don't auto-launch a new zsh shell,
# which would otherwise take over the terminal and halt the rest of the script.
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

log "Setting Oh My Zsh theme to bira"
sed -i 's/^ZSH_THEME=.*/ZSH_THEME="bira"/' "$HOME/.zshrc"

log "Setting zsh as the default shell"
chsh -s $(which zsh)

log "Post-install complete. A reboot is recommended for firmware/kernel updates to take effect."

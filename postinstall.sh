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

# ---- package groups + individual packages ----
log "Installing package groups and dev tools"
sudo dnf group install -y development-tools c-development editors vlc
sudo dnf install -y gimp inkscape

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
    io.github.getnf.embellish

# ---- archive support ----
log "Installing archive format support"
sudo dnf install -y unzip p7zip p7zip-plugins unrar

# ---- install favorite fonts ----
log "Installing custom fonts"
sudo dnf install -y lato-fonts

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

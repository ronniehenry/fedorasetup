#!/bin/sh

# setup RPM Fusion
sudo dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# upgrade core package
sudo dnf group upgrade -y core
sudo dnf4 group install -y core
sudo dnf -y update

# Update firmware
sudo fwupdmgr refresh --force
sudo fwupdmgr get-devices # Lists devices with available updates.
sudo fwupdmgr get-updates # Fetches list of available updates.
sudo fwupdmgr update

# Install Flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Install AppImage support
sudo dnf install -y fuse fuse-libs
flatpak install it.mijorus.gearlever

# Install media codecs
sudo dnf4 group install multimedia
sudo dnf swap 'ffmpeg-free' 'ffmpeg' --allowerasing # Switch to full FFMPEG.
sudo dnf upgrade @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin # Installs gstreamer components. Required if you use Gnome Videos and other dependent applications.
sudo dnf group install -y sound-and-video # Installs useful Sound and Video complementary packages.

# HW Video Decoding (VA-API)
sudo dnf install -y ffmpeg-libs libva libva-utils
sudo dnf swap libva-intel-media-driver intel-media-driver --allowerasing
sudo dnf install -y libva-intel-driver

# Setup h264 for Firefox
sudo dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

# Set hostname (replace negomi)
hostnamectl set-hostname negomi

# switch default editor to vim
sudo dnf remove -y nano-default-editor
sudo dnf install -y vim-default-editor

# Install package groups
sudo dnf group install development-tools c-development vlc editors

# Install favorite gnome apps
sudo dnf install -y gnome-tweaks timeshift solaar gimp inkscape transmission-gtk

# install compressed files support
sudo dnf install -y unzip p7zip p7zip-plugins unrar

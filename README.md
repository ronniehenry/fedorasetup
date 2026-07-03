# Fedora Post-Install Script

Idempotent post-install setup script for a fresh (or already-running) Fedora
Workstation system. Handles repo setup, codecs, dev tools, GNOME extensions,
and shell config in one pass.

## Usage

```bash
chmod +x postinstall.sh
./postinstall.sh --host <hostname>
```

`--host` is required and sets the machine's hostname via `hostnamectl`.

## What it does

1. **dnf tuning** — overwrites `/etc/dnf/dnf.conf` with `max_parallel_downloads=20`
   and `fastestmirror=True`, then runs a full upgrade.
2. **RPM Fusion** — enables free and nonfree repos.
3. **Core upgrade** — `dnf group upgrade core` + full system update.
4. **Firmware** — refreshes and applies updates via `fwupdmgr`.
5. **Flatpak / Flathub** — adds the Flathub remote.
6. **AppImage support** — installs `fuse`/`fuse-libs` and Gear Lever.
7. **Multimedia codecs** — installs the `multimedia` and `sound-and-video`
   groups, swaps `ffmpeg-free` → `ffmpeg`.
8. **VA-API hardware video decoding** — installs `libva`/`ffmpeg-libs`, swaps
   to `intel-media-driver`.
9. **H.264 for Firefox** — enables the Cisco OpenH264 repo and installs the plugin.
10. **Hostname** — sets it to the value passed via `--host`.
11. **Default editor** — swaps `nano-default-editor` → `vim-default-editor`.
12. **GNOME Shell extensions** — installs via `dnf`: Blur My Shell, Dash to
    Dock, Just Perfection, User Themes, AppIndicator Support, Caffeine.
    Clipboard Indicator isn't packaged for Fedora, so it's installed via
    `gnome-extensions-cli` (`gext`) instead. **Extensions are installed but
    left disabled** — enable them manually via Extension Manager or GNOME
    Extensions after logging in.
13. **Dev tools & apps** — `development-tools`, `c-development`, `editors`,
    `vlc` groups, plus GNOME Tweaks, Timeshift, GIMP, Inkscape, Transmission.
14. **VS Code** — installed from Microsoft's official RPM repo.
15. **Flatpak apps** — Kdenlive, HandBrake, Strawberry, LocalSend, Embellish,
    Extension Manager, Zed, OBS Studio.
16. **Archive support** — unzip, p7zip, unrar.
17. **zsh + Oh My Zsh** — installed unattended, theme set to `bira`.

## Notes

- **Safe to rerun.** Package installs, group installs, and Flatpak installs
  are no-ops if already present. The two `dnf swap` calls are guarded with a
  `rpm -q` check so they don't fail once the swap has already happened.
- **`/etc/dnf/dnf.conf` is fully overwritten**, not merged — any existing
  settings in that file will be replaced.
- **GNOME extensions are not auto-enabled.** `gnome-extensions enable`
  requires a live D-Bus session that has already scanned the extension,
  which freshly-installed ones haven't been. Enable them manually after
  logging in.
- **A reboot is recommended** after running, since firmware and kernel
  updates may be pending.
- Requires `sudo` privileges throughout; you'll be prompted for your password.

## Requirements

- Fedora Workstation (tested on Fedora 44)
- A user account with `sudo` access
- Internet access (RPM Fusion, Flathub, Microsoft's VS Code repo, GitHub for
  Oh My Zsh, PyPI for `gnome-extensions-cli`)

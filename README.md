# Fedora Post-Install Script

Idempotent post-install setup script for a fresh (or already-running) Fedora
Workstation system. Handles repo setup, codecs, dev tools, terminal, GNOME
extensions, theming, and shell config in one pass.

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
4. **Snapper + grub-btrfs rollback protection** — installs `snapper` and
   `libdnf5-plugin-actions`, then writes
   `/etc/dnf/libdnf5-plugins/actions.d/snapper.actions` to create a pre/post
   snapshot around every dnf transaction (no timed snapshots —
   `snapper-timeline.timer` is explicitly disabled). **Uses the dnf5 actions
   plugin, not `python3-dnf-plugin-snapper`** — that package is DNF4-only and
   never hooks into dnf5, which is Fedora's default `dnf` since F41; using it
   silently produces zero automatic snapshots. Sets `NUMBER_CLEANUP=yes` with
   `NUMBER_LIMIT=20` / `NUMBER_LIMIT_IMPORTANT=10` so those dnf-triggered
   snapshots — which have no Cleanup algorithm by default — actually get
   pruned by `snapper-cleanup.timer` instead of accumulating forever. Also
   installs `grub-btrfs` via the `kylegospo/grub-btrfs` COPR so snapshots are
   bootable from the GRUB menu. Placed here, right after RPM Fusion/core
   upgrade, so a rollback point exists before the riskier repo/codec steps
   below run. Overrides the packaged `grub-btrfs.path` unit, since Fedora's
   default layout makes `.snapshots` a nested subvolume rather than a real
   mount point, which the shipped unit's mount dependency can't resolve.
5. **Firmware** — refreshes and applies updates via `fwupdmgr`. Exit code 2
   (nothing to do) is treated as success; any other non-zero code stops the
   script.
6. **Flatpak / Flathub** — adds the Flathub remote.
7. **Multimedia codecs** — installs the `multimedia` and `sound-and-video`
   groups, swaps `ffmpeg-free` → `ffmpeg`.
8. **VA-API hardware video decoding** — installs `libva`/`ffmpeg-libs`, swaps
   to `intel-media-driver`. **Intel-specific** — edit this section if running
   on AMD or Nvidia hardware.
9. **H.264 for Firefox** — enables the Cisco OpenH264 repo and installs the plugin.
10. **Hostname** — sets it to the value passed via `--host`.
11. **Default editor** — swaps `nano-default-editor` → `vim-default-editor`.
12. **Terminal** — enables a COPR repo for Ghostty, installs it, removes
    Ptyxis, and sets Ghostty as the default GNOME terminal.
13. **GNOME Shell extensions** — installs via `dnf`: Dash to Dock, User
    Themes, AppIndicator Support. **Installed but left disabled** — enable
    them manually via Extension Manager or GNOME Extensions after logging in.
14. **Dev tools & apps** — `development-tools`, `c-development`, `editors`,
    `vlc` groups, plus GNOME Tweaks, GIMP, Inkscape, Transmission.
15. **VS Code** — installed from Microsoft's official RPM repo.
16. **Flatpak apps** — Strawberry, Embellish, Extension Manager.
17. **Archive support** — unzip, p7zip, unrar.
18. **Custom cursors** — enables a COPR repo, installs the Bibata cursor theme.
19. **Custom fonts** — installs Lato.
20. **Custom icons** — installs the Papirus icon theme, then runs the
    upstream `papirus-folders` install script (fetched from `git.io`) to set
    folder color to green on the Dark variant.
21. **zsh + Oh My Zsh** — installed unattended, theme set to `bira`, and zsh
    is set as the default login shell via `chsh`.

## Notes

- **Safe to rerun.** Package installs, group installs, and Flatpak installs
  are no-ops if already present. The `dnf swap` calls are guarded with an
  `rpm -q` check so they don't fail once the swap has already happened.
- **`/etc/dnf/dnf.conf` is fully overwritten**, not merged — any existing
  settings in that file will be replaced.
- **GNOME extensions are not auto-enabled.** `gnome-extensions enable`
  requires a live D-Bus session that has already scanned the extension,
  which freshly-installed ones haven't been. Enable them manually after
  logging in.
- **The Papirus folder-color script is fetched via `git.io`**, a
  deprecated/archived GitHub URL shortener. Existing links are currently
  preserved but not guaranteed long-term — if this step ever fails, pull the
  script directly from the `papirus-folders` GitHub repo instead.
- **A reboot is recommended** after running, since firmware and kernel
  updates may be pending. This is also the only way to confirm the Snapper +
  grub-btrfs setup actually works — check the GRUB menu for a "Fedora Linux
  snapshots" submenu before trusting the rollback protection.
- **The `kylegospo/grub-btrfs` COPR is a real external dependency, not a
  Fedora-maintained package.** `set -euo pipefail` means the script fails
  loudly (not silently) if that project ever drops Fedora 44 support or is
  renamed — same failure this section previously hit with an earlier,
  wrong COPR name (`theoware/grub-btrfs`, which had no fedora-44 build).
- **The `grub-btrfs.path` systemd unit is overridden**, not used as shipped —
  the packaged unit depends on a `.snapshots.mount` unit that doesn't exist
  on Fedora's default (nested-subvolume) layout, so this script replaces it
  with one that watches `/.snapshots` directly.
- Requires `sudo` privileges throughout; you'll be prompted for your password.

## Requirements

- Fedora Workstation (tested on Fedora 44)
- A user account with `sudo` access
- Internet access (RPM Fusion, Flathub, Microsoft's VS Code repo, Fedora
  COPR for Ghostty, `grub-btrfs`, and Bibata cursors, GitHub for Oh My Zsh,
  `git.io` for the Papirus folder-color script)

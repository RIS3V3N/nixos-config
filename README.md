# NixOS Config

Personal NixOS and Home Manager configuration using flakes.

This repository contains my declarative Linux workstation setup, including:

- NixOS system configuration (flake-based)
- Home Manager user configuration
- Hyprland desktop setup
- Alacritty terminal configuration
- Waybar, Fuzzel, Dunst and related desktop tools
- Brave browser configuration
- Fonts, cursor themes and common desktop packages
- Automated encrypted backups via restic → OneDrive

## Structure

```text
.
├── flake.nix                    # inputs: nixpkgs, home-manager, hyprland
├── flake.lock
├── hosts/
│   └── nixhorse/
│       ├── configuration.nix    # system config (hardware, users, services)
│       └── hardware-configuration.nix
├── home/
│   └── dom.nix                  # user config: imports modules + machine-specific overrides
├── modules/
│   ├── hyprland.nix             # Hyprland WM, keybinds, workspaces, hypridle, hyprlock
│   ├── waybar.nix               # status bar config + CSS
│   ├── shell.nix                # bash, starship, alacritty, fzf, zoxide, fastfetch
│   ├── desktop.nix              # GTK, cursors, fuzzel, dunst, brave, dolphin
│   ├── dev.nix                  # VSCode, direnv, python/uv/ruff/pyright, CLI dev tools
│   └── backup.nix               # restic backup schedule via rclone → OneDrive
└── assets/
    └── gothic_ii_game_wp.jpg
```

## Setting up a new machine from scratch

### 1. Install NixOS

Boot from the NixOS installer ISO, partition and install as usual.
Generate hardware config:

```bash
sudo nixos-generate-config
```

### 2. Clone this repo

```bash
nix-shell -p git
git clone https://github.com/RIS3V3N/nixos-config /home/dom/code/nixos-config
cd /home/dom/code/nixos-config
```

### 3. Add a new host

Copy `hardware-configuration.nix` from the generated config:

```bash
mkdir -p hosts/<hostname>
cp /etc/nixos/hardware-configuration.nix hosts/<hostname>/
```

Create `hosts/<hostname>/configuration.nix` based on `hosts/nixhorse/configuration.nix`,
updating hostname, LUKS UUIDs and any hardware-specific options.

Add a new `nixosConfigurations.<hostname>` entry in `flake.nix`.

### 4. Apply the configuration

```bash
sudo nixos-rebuild switch --flake /home/dom/code/nixos-config#<hostname>
```

After the first successful build, the `rebuild` shell function is available:

```bash
rebuild
```

### 5. Set up OneDrive sync (one-time)

```bash
onedrive --synchronize
# Follow the auth URL printed in the terminal, paste the redirect URL back
```

The onedrive systemd user service then runs automatically on every login.

### 6. Set up rclone for backups (one-time)

```bash
# Configure rclone OneDrive remote — must be named "onedrive"
rclone config
# → n (new remote) → name: onedrive → type: onedrive → follow OAuth prompts
```

### 7. Initialise the restic backup repository (one-time)

```bash
# Generate and store the encryption password (do not lose this)
mkdir -p ~/.config/restic
pwgen -s 64 1 > ~/.config/restic/password
chmod 600 ~/.config/restic/password

# Initialise the remote repository
restic -r rclone:onedrive:Backups/<hostname> init \
  --password-file ~/.config/restic/password

# Trigger the first backup manually to verify
systemctl start restic-backups-home.service
journalctl -fu restic-backups-home.service
```

Subsequent backups run automatically on a daily systemd timer.

---

## Day-to-day usage

### Rebuild after config changes

```bash
rebuild
# expands to: sudo nixos-rebuild switch --flake /home/dom/code/nixos-config#$(hostname -s)
```

### Upgrade to a new NixOS release

Edit `flake.nix` and bump both input URLs (e.g. `nixos-25.11` → `nixos-26.05`),
bump `system.stateVersion` in `hosts/<hostname>/configuration.nix` and
`home.stateVersion` in `home/dom.nix`, then:

```bash
nix flake update
rebuild
```

### Roll back a broken build

```bash
sudo nixos-rebuild switch --rollback
```

Or select a previous generation from the systemd-boot menu at startup.

### Check backup status

```bash
# View snapshots
restic -r rclone:onedrive:Backups/nixhorse snapshots \
  --password-file ~/.config/restic/password

# Check last backup service run
systemctl status restic-backups-home.service
journalctl -u restic-backups-home.service --since "24 hours ago"
```

### Restore from backup

```bash
export RESTIC_REPOSITORY=rclone:onedrive:Backups/nixhorse
export RESTIC_PASSWORD_FILE=~/.config/restic/password

# List available snapshots
restic snapshots

# Restore a single file or directory to its original location
restic restore latest --target / --include /home/dom/.ssh

# Restore everything from the latest snapshot to its original location
restic restore latest --target /

# Restore to a staging directory first (safer — inspect before overwriting)
restic restore latest --target /tmp/restore-staging
# then copy what you need:
# cp -a /tmp/restore-staging/home/dom/.ssh ~/.ssh

# Restore from a specific snapshot (use snapshot ID from `restic snapshots`)
restic restore a1b2c3d4 --target / --include /home/dom/Dokumente
```

> **Tip:** `--include` accepts glob patterns, e.g. `--include '/home/dom/.config/rclone'`.
> Omit it to restore the full snapshot.

---

## Secrets

This repository must not contain secrets.

Do not commit:

- SSH private keys
- API tokens or passwords
- VPN credentials
- WiFi connection profiles
- `.env` files
- `~/.config/restic/password`
- `~/.config/rclone/rclone.conf`

Before pushing, check:

```bash
grep -RniE "password|token|secret|apikey|api_key|private|BEGIN .*PRIVATE KEY" .
```

NetworkManager WiFi profiles live outside this repo at:

```text
/etc/NetworkManager/system-connections/
```

---

## Useful commands

```bash
# Inspect Hyprland monitors
hyprctl monitors

# Inspect active keybinds
hyprctl binds

# Check Home Manager activation
systemctl status home-manager-dom.service

# Restart waybar after style changes
systemctl --user restart waybar

# Reload Hyprland config without logging out
hyprctl reload

# Full session logout (re-runs exec-once on next login)
# SUPER + SHIFT + E

# Kill entire user session including systemd services
loginctl terminate-user dom
```

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
- ZeroTier-based office network routing with per-interface split DNS

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
│   ├── work-network.nix         # ZeroTier office routing + split DNS toggle
│   ├── wireguard.nix            # personal WireGuard VPN (wg-up/down/toggle/status)
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

### 8. Set up git identity (one-time, not stored in repo)

`dev.nix` already declares the `includeIf` conditions that route each repo path to
the right identity file. You only need to create the identity files themselves —
they are kept outside the repo so your addresses are never committed.

Work repos must live under the corresponding subdirectory so the routing works:

| Service   | Clone into               |
| --------- | ------------------------ |
| GitLab    | `~/code/work/gitlab/`    |
| GitHub    | `~/code/work/github/`    |
| Bitbucket | `~/code/work/bitbucket/` |
| Personal  | `~/code/personal/`       |

```bash
mkdir -p ~/.config/git ~/code/work/gitlab ~/code/work/github ~/code/work/bitbucket ~/code/personal

# Personal identity (default fallback)
cat > ~/.config/git/local << 'EOF'
[user]
    email = your@personal.com
    name  = RIS3V3N
EOF
chmod 600 ~/.config/git/local

# Work GitLab
cat > ~/.config/git/work-gitlab << 'EOF'
[user]
    email = dom@company.com
    name  = Dom Lastname
EOF

# Work Bitbucket
cat > ~/.config/git/work-bitbucket << 'EOF'
[user]
    email = dom@company.com
    name  = Dom Lastname
EOF

# Work GitHub
cat > ~/.config/git/work-github << 'EOF'
[user]
    email = dom@company.com
    name  = Dom Lastname
EOF
```

Verify the right identity is picked up:

```bash
cd ~/code/work/gitlab/some-repo && git config user.email   # → dom@company.com
cd ~/code/personal/some-repo    && git config user.email   # → your@personal.com
```

### 9. Generate SSH keys (one-time)

Generate one key per hosting identity and add each public key to the
corresponding account:

```bash
# Personal GitHub (default)
ssh-keygen -t ed25519 -C "your@personal.com" -f ~/.ssh/id_personal

# Work GitLab  (~/code/work/repo)
ssh-keygen -t ed25519 -C "dom@company.com" -f ~/.ssh/id_work_gitlab

# Work Bitbucket  (~/code/work/repo)
ssh-keygen -t ed25519 -C "dom@company.com" -f ~/.ssh/id_work_bitbucket

# Work GitHub  (~/code/work/repo)
ssh-keygen -t ed25519 -C "dom@company.com" -f ~/.ssh/id_work_github
```

Create `~/.ssh/config.local` for site-specific host entries (never committed):

```
Host bitbucket-work
    HostName bitbucket.yourcompany.com
    Port     7999
```

This file is pulled in by `~/.ssh/config` via `Include ~/.ssh/config.local`.

Create `~/.ssh/extra-keys` for any additional SSH keys that should be loaded
into the agent at login but whose filenames contain sensitive information (never
committed):

```
~/.ssh/some-key
~/.ssh/another-key
```

Hyprland runs `ssh-add` at login for all standard keys plus any paths listed in
this file. You will get one pinentry dialog per key with a passphrase the first
time; subsequent uses are passphrase-free for 24 hours.

`AddKeysToAgent yes` (set in `modules/dev.nix`) also means any other key used
ad-hoc with `ssh -i ~/.ssh/some-key ...` gets registered with the running
agent (gpg-agent) automatically the first time it's used successfully — no
need to add it here or start a separate `ssh-agent` per session.

When cloning repos:

```bash
# Personal GitHub — copy-paste from GitHub UI works directly
git clone git@github.com:RIS3V3N/repo.git ~/code/personal/repo

# Work GitLab — copy-paste from GitLab UI works directly
git clone git@gitlab.com:org/repo.git ~/code/work/repo/repo

# Work Bitbucket — uses the bitbucket-work alias defined in ~/.ssh/config.local
git clone ssh://git@bitbucket-work/proj/repo.git ~/code/work/bitbucket/repo

# Work GitHub — CANNOT copy-paste (same hostname as personal).
# Use the wclone helper instead:
wclone org/repo
# expands to: git clone git@github-work:org/repo.git ~/code/work/repo
```

### 10. Set up commit signing (one-time per machine)

This config uses **SSH key signing** — no separate GPG key needed, your existing
SSH keys sign commits. Each identity uses its own SSH key.

#### Add signing key to each identity's git config

Edit each file created in step 8 to add the `user.signingKey` pointing to the
corresponding SSH public key:

`~/.config/git/local` (personal GitHub — default):

```ini
[user]
    email = your@personal.com
    name = RIS3V3N
    signingKey = ~/.ssh/id_personal.pub
```

`~/.config/git/work-gitlab`:

```ini
[user]
    email = dom@company.com
    name  = Dom Lastname
    signingKey = ~/.ssh/id_work_gitlab.pub
```

`~/.config/git/work-bitbucket`:

```ini
[user]
    email = dom@company.com
    name  = Dom Lastname
    signingKey = ~/.ssh/id_work_bitbucket.pub
```

`~/.config/git/work-github`:

```ini
[user]
    email = dom@company.com
    name  = Dom Lastname
    signingKey = ~/.ssh/id_work_github.pub
```

#### Create the allowed signers file

Git needs this to verify signatures locally:

```bash
cat > ~/.config/git/allowed_signers << 'EOF'
your@personal.com namespaces="git" $(cat ~/.ssh/id_personal.pub)
dom@company.com namespaces="git" $(cat ~/.ssh/id_work_gitlab.pub)
dom@company.com namespaces="git" $(cat ~/.ssh/id_work_bitbucket.pub)
dom@company.com namespaces="git" $(cat ~/.ssh/id_work_github.pub)
EOF
```

#### Register signing keys with GitHub/GitLab/Bitbucket

Each hosting platform needs the **same public key** added as a _signing key_
(separate from the authentication key entry):

- **GitHub**: Settings → SSH and GPG keys → New SSH key → type: **Signing Key**
- **GitLab**: Preferences → SSH Keys → add key → Usage type: **Signing**
- **Bitbucket**: does not support SSH commit signature verification (commits will
  still be signed locally, just not shown as Verified in the UI)

Add each public key to the corresponding account:

```bash
cat ~/.ssh/id_personal.pub          # → personal GitHub (signing key)
cat ~/.ssh/id_work_gitlab.pub       # → work GitLab (signing key)
cat ~/.ssh/id_work_github.pub       # → work GitHub (signing key)
```

#### Verify it works

```bash
cd ~/code/personal
git commit --allow-empty -m "test signing"
git log --show-signature -1
# should show: Good "git" signature for your@personal.com
```

### 11. Set up ZeroTier office network (one-time)

`modules/work-network.nix` gives you a `work-vpn` toggle that:

- Routes configured office subnets through your office gateway via ZeroTier
- Sets office DNS servers on the ZeroTier interface (split DNS — only
  `~company.local` and similar domains go through office DNS)
- Reverts everything cleanly when toggled off

#### Prerequisites

1. **Create a ZeroTier network** at <https://my.zerotier.com> (free tier is fine).

2. **ZeroTier on nixhorse is already handled** — `work-network.nix` declares
   `services.zerotierone` so ZeroTier is installed and auto-joined after `rebuild`.
   No manual install needed here.

3. **Install ZeroTier on the office gateway server** (runs Ubuntu/Debian, not NixOS)
   and join the same network:

```bash
# Run these on the office gateway server, not on nixhorse:
curl -s https://install.zerotier.com | sudo bash
sudo zerotier-cli join <ztNetworkId>
# Then authorise it in ZeroTier Central → Members
```

4. **Enable IP forwarding + NAT on the office server** so it can relay traffic
   to the rest of the office LAN (replace `eth0` with the server's LAN interface):

```bash
# Run these on the office gateway server, not on nixhorse:
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-zt-forward.conf
sudo sysctl -p /etc/sysctl.d/99-zt-forward.conf
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i zt+ -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o zt+ -m state --state RELATED,ESTABLISHED -j ACCEPT
# Persist with iptables-persistent:
sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

#### Configure and activate

After `rebuild` (enables the ZeroTier daemon and systemd-resolved), create
the env file and fill in your values:

```bash
work-setup
# Creates ~/.config/work-network/env — open it and fill in your values:
${EDITOR:-nano} ~/.config/work-network/env
```

The env file looks like this (never committed to the repo):

```bash
ZT_NETWORK_ID="abcd7a9e1c990947"          # 16-char ID from my.zerotier.com
OFFICE_GATEWAY_ZT_IP="10.147.x.x"         # ZeroTier IP of the office server
OFFICE_SUBNETS="10.0.0.0/8 192.168.0.0/16"
OFFICE_DNS_SERVERS="192.168.1.1 192.168.1.2"
OFFICE_DNS_DOMAINS="~company.local ~company.internal"
```

Join the ZeroTier network (once — state persists across reboots):

```bash
sudo zerotier-cli join <ZT_NETWORK_ID>    # use the ID from your env file
# Then authorise this machine at https://my.zerotier.com → Members
```

Check status and start routing:

```bash
work-status   # confirms ZeroTier is up and shows your node ID
work-up
```

Changing the env file later (new subnets, different DNS, etc.) does **not**
require a rebuild — just edit the file and run `work-down && work-up`.

#### Day-to-day usage

```bash
work-vpn      # toggle on/off (remembers state in /run/work-vpn-active)
work-up       # explicitly enable routing + DNS
work-down     # explicitly disable routing + DNS
work-status   # show ZeroTier status, active routes, and DNS config
```

#### Static hosts

If some internal names are flaky in DNS, add them to `networking.hosts` in
`hosts/nixhorse/configuration.nix` and rebuild:

```nix
networking.hosts = {
  "192.168.1.10" = [ "intranet.company.local" "intranet" ];
};
```

These are written to `/etc/hosts` permanently (names always resolve, but
only reachable while `work-up` routes are active).

---

### 12. Set up personal WireGuard VPN (one-time)

`modules/wireguard.nix` gives you `wg-up/down/toggle/status` commands that:

- Build a `wg-quick` config at runtime from `~/.config/wireguard/env` (never
  written to persistent storage — lives only in `/run/user/<uid>/` while up)
- Route traffic according to `WG_ALLOWED_IPS` (full tunnel or split-tunnel)
- Optionally push DNS while the tunnel is up

#### Client setup (nixhorse)

**1. Generate a key pair** (run once; keep the private key secret):

```bash
wg genkey | tee /tmp/wg-private.key | wg pubkey > /tmp/wg-public.key
cat /tmp/wg-public.key   # share this string with your server admin
```

**2. Create and fill the env file:**

```bash
wg-setup
${EDITOR:-nano} ~/.config/wireguard/env
```

Fill in:

```bash
WG_PRIVATE_KEY="<contents of /tmp/wg-private.key>"
WG_SERVER_PUBKEY="<public key provided by server admin>"
WG_ENDPOINT="vpn.yourserver.com:51820"
WG_CLIENT_IP="10.8.0.2/32"           # assign with server admin
WG_ALLOWED_IPS="0.0.0.0/0, ::/0"     # or narrow to specific subnets
WG_DNS="10.8.0.1"                     # optional
WG_PRESHARED_KEY=""                   # optional, leave empty if unused
```

**3. Clean up the temp key files:**

```bash
rm /tmp/wg-private.key /tmp/wg-public.key
```

**4. Bring the tunnel up:**

```bash
wg-up
wg-status
```

#### Server setup (Linux server — not NixOS)

Run these steps on the VPN server, **not** on nixhorse.

**1. Install WireGuard:**

```bash
# Debian / Ubuntu
sudo apt-get install -y wireguard
```

**2. Generate server keys:**

```bash
cd /etc/wireguard
wg genkey | sudo tee server_private.key | wg pubkey | sudo tee server_public.key
sudo chmod 600 server_private.key
```

**3. Enable IP forwarding:**

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-wg-forward.conf
sudo sysctl -p /etc/sysctl.d/99-wg-forward.conf
```

**4. Create `/etc/wireguard/wg0.conf`** (replace `eth0` with the server's
outbound interface, and `<server_private_key>` with the contents of
`server_private.key`):

```ini
[Interface]
PrivateKey = <server_private_key>
Address    = 10.8.0.1/24
ListenPort = 51820
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# nixhorse — add a [Peer] block for every client
[Peer]
PublicKey  = <nixhorse WG_PUBLIC_KEY from step 1>
AllowedIPs = 10.8.0.2/32
```

**5. Start and enable the service:**

```bash
sudo systemctl enable --now wg-quick@wg0
sudo wg show   # should list the peer
```

**6. Add further clients later (no restart needed):**

```bash
sudo wg set wg0 peer <new_client_pubkey> allowed-ips 10.8.0.x/32
sudo wg-quick save wg0   # persists to /etc/wireguard/wg0.conf
```

#### Day-to-day usage

```bash
wg-toggle   # flip tunnel on/off
wg-up       # explicitly enable
wg-down     # explicitly disable
wg-status   # show interface state, handshake time, and active routes
```

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

* `~/.config/restic/password`
* `~/.config/rclone/rclone.conf`
* `~/.config/work-network/env` (ZeroTier network ID, office IPs and DNS servers)
* `~/.config/wireguard/env` (WireGuard private key, server pubkey, endpoint)
* `~/.config/git/local` (contains your email)
* `~/.ssh/config.hosts` (individual host entries — servers, jump hosts, etc.)
* `~/.ssh/config.local` (machine-local SSH overrides — ProxyJump, port forwards, etc.)
* `~/gpg-private-key.asc`

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

# Monitor layouts (hyprmoncfg — see hypr/hyprmoncfg/README.md)
hyprmoncfg                 # TUI layout editor, `s` saves a profile
hyprmoncfg list            # list saved profiles
hyprmoncfg apply desk      # apply a profile manually
systemctl --user status hyprmoncfgd   # auto-switching daemon

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

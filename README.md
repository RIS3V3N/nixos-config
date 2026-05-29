# NixOS Config

Personal NixOS and Home Manager configuration.

This repository contains my declarative Linux workstation setup, including:

* NixOS system configuration
* Home Manager user configuration
* Hyprland desktop setup
* Alacritty terminal configuration
* Waybar, Fuzzel, Dunst and related desktop tools
* Brave browser configuration
* Fonts, cursor themes and common desktop packages

## Structure

```text
.
├── hosts/
│   └── nixhorse/
│       ├── configuration.nix
│       └── hardware-configuration.nix
├── home/
│   └── dom.nix
├── modules/
│   ├── desktop-hyprland.nix
│   ├── brave.nix
│   └── packages.nix
└── README.md
```

## Apply configuration

The active NixOS configuration is expected to be linked from `/etc/nixos`.

```bash
sudo nixos-rebuild switch
```

## Home Manager

Home Manager is used as a NixOS module.

User-level configuration lives in:

```text
home/dom.nix
```

This manages dotfiles and user applications declaratively.

## Machine-specific files

Hardware-specific configuration lives under:

```text
hosts/<hostname>/
```

For a new machine, generate a new hardware config:

```bash
sudo nixos-generate-config
```

Then create a new host directory and reuse the shared modules where possible.

## Secrets

This repository should not contain secrets.

Do not commit:

* SSH private keys
* API tokens
* VPN credentials
* WiFi connection profiles
* Browser profiles
* Cloud provider credentials
* Kubernetes configs with tokens
* `.env` files

Before pushing, check:

```bash
grep -RniE "password|token|secret|apikey|api_key|private|BEGIN .*PRIVATE KEY" .
```

NetworkManager WiFi profiles are usually stored in:

```text
/etc/NetworkManager/system-connections/
```

These should stay outside this repository.

## Useful commands

Rebuild system:

```bash
sudo nixos-rebuild switch
```

Update channels:

```bash
sudo nix-channel --update
```

Check Home Manager service:

```bash
systemctl status home-manager-$USER.service
```

Inspect Hyprland monitors:

```bash
hyprctl monitors
```

Inspect Hyprland keybinds:

```bash
hyprctl binds
```

## Notes

This setup is currently optimized for the `nixhorse` machine.
The goal is to keep hardware-specific configuration separate from reusable desktop and user configuration.


# hyprmoncfg profiles

`~/.config/hyprmoncfg` is an out-of-store symlink to this directory (see
`modules/monitors.nix`), so anything `hyprmoncfg` saves lands straight in this
git working tree.

- `profiles/*.json` — the source of truth. **Commit these.**
- `profiles/*.conf`, `profiles/*.lua` — generated sidecar exports of each
  profile, useful as plain Hyprland snippets if hyprmoncfg is ever dropped.
- `~/.config/hypr/monitors.conf` — generated at runtime from the active
  profile. **Not** managed by home-manager and **not** committed.

Monitors are matched by hardware identity (`make|model|serial`), not connector
name, so profiles survive `DP-1`/`DP-2` swapping between boots.

## Usage

```bash
hyprmoncfg              # TUI — drag monitors, press `s`, name the profile
hyprmoncfg list         # list saved profiles
hyprmoncfg apply desk   # apply a profile manually
systemctl --user status hyprmoncfgd   # auto-switching daemon
```

After saving or changing a profile:

```bash
git -C ~/code/nixos-config add hypr/hyprmoncfg
git -C ~/code/nixos-config commit -m "monitors: update desk profile"
```

No `nixos-rebuild` is needed to change a layout.

## Profiles to recreate (migrated from kanshi)

The old kanshi profiles were:

| Name        | Outputs                                                                  |
| ----------- | ------------------------------------------------------------------------ |
| `home`      | eDP-1 @ 0,0 scale 1.5 + 2× ASUS XG27UCS (…366 @ 1920,0, …367 @ 4480,0) 1.5 |
| `laptop`    | eDP-1 only, scale 1.5                                                    |
| `workDesk1` | DP-1 @ 0,0 scale 1.0 + eDP-1 @ 0,1440 scale 1.5                          |

Recreate each one with the TUI while physically at that desk — hyprmoncfg
captures the real hardware identity and modes from the live Hyprland state,
which is more reliable than hand-writing the JSON.

> Every `*.json` here is a match candidate for the daemon. Delete throwaway
> profiles instead of leaving them around.

{
  config,
  pkgs,
  lib,
  ...
}:

# ── Monitor layouts via hyprmoncfg ────────────────────────────────────────
#
# Replaces kanshi.  hyprmoncfg (https://github.com/crmne/hyprmoncfg) is a TUI +
# CLI + daemon that stores hardware-identity-matched profiles as JSON and
# generates ~/.config/hypr/monitors.conf from them.
#
# Split of responsibilities:
#
#   ~/.config/hyprmoncfg/profiles/*.json  → source of truth, lives in THIS repo
#                                            (out-of-store symlink, writable, so
#                                             the TUI can save into git directly)
#   ~/.config/hypr/monitors.conf          → generated output, NOT managed by
#                                            home-manager, NOT in git
#
# Workflow:
#   hyprmoncfg              # TUI: drag monitors, press `s`, name the profile
#   hyprmoncfg list         # show saved profiles
#   hyprmoncfg apply desk   # apply one manually
#   git -C ~/code/nixos-config add hypr/hyprmoncfg/profiles && git commit
#
# The hyprmoncfgd daemon auto-applies the best-matching profile on hotplug and
# lid events, so switching desks/docking should need no manual action.

let
  # Absolute path to this repo's working copy.  Must be a plain string (not a
  # path literal) or Nix would copy it into the store and it would be read-only.
  repoDir = "${config.home.homeDirectory}/code/nixos-config";
  profilesDir = "${repoDir}/hypr/hyprmoncfg";
in
{
  home.packages = [ pkgs.unstable.hyprmoncfg ];

  # ~/.config/hyprmoncfg → repo checkout.  Writable, so `hyprmoncfg` saves new
  # profiles straight into the git working tree; no `nixos-rebuild` needed to
  # tweak a layout, and `git status` shows what changed.
  xdg.configFile."hyprmoncfg".source = config.lib.file.mkOutOfStoreSymlink profilesDir;

  # monitors.conf is generated at runtime by hyprmoncfg, so home-manager must
  # not own it.  Hyprland fails to start cleanly if a sourced file is missing,
  # so make sure an (empty) one exists before the first apply.
  home.activation.hyprmoncfgPlaceholder = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run mkdir -p "${config.xdg.configHome}/hypr"
    run mkdir -p "${profilesDir}/profiles"
    if [ ! -e "${config.xdg.configHome}/hypr/monitors.conf" ]; then
      run touch "${config.xdg.configHome}/hypr/monitors.conf"
    fi
  '';

  # Hotplug / lid-aware profile switching.
  systemd.user.services.hyprmoncfgd = {
    Unit = {
      Description = "hyprmoncfg monitor profile daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      # Give Hyprland a moment to register all outputs before the first match.
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
      ExecStart = "${pkgs.unstable.hyprmoncfg}/bin/hyprmoncfgd";
      Restart = "on-failure";
      RestartSec = 3;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}

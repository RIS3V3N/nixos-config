{ config, pkgs, ... }:

let
  wallpaper = "${../assets/gothic-1-remake-fu-3840x2400.jpg}";
in
{
  imports = [
    ../modules/hyprland.nix
    ../modules/monitors.nix
    ../modules/waybar.nix
    ../modules/shell.nix
    ../modules/desktop.nix
    ../modules/dev.nix
  ];

  home.username = "dom";
  home.homeDirectory = "/home/dom";
  home.stateVersion = "25.11";

  home.packages = with pkgs; [
    alacritty
    onedrive
  ];

  # ── Wallpaper ────────────────────────────────────────────────────────────
  services.hyprpaper.settings = {
    preload = [ wallpaper ];
    wallpaper = [ ",${wallpaper}" ];
  };

  # ── Monitor layout ───────────────────────────────────────────────────────
  # Handled by hyprmoncfg, see ../modules/monitors.nix.

  # ── OneDrive sync (work-specific paths) ─────────────────────────────────
  xdg.configFile."onedrive/sync_list".text = ''
    Dokumente/15_Work/SV/Notes
    Dokumente/16_Notes
  '';

  systemd.user.services.onedrive = {
    Unit = {
      Description = "OneDrive sync daemon";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };

    Service = {
      ExecStart = "${pkgs.onedrive}/bin/onedrive --monitor";
      Restart = "on-failure";
      RestartSec = 3;
      RestartPreventExitStatus = 3;
      RestrictRealtime = true;
      ProtectControlGroups = true;
      ProtectKernelTunables = true;
      ProtectHostname = true;
      ProtectSystem = "full";
    };

    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  programs.home-manager.enable = true;
}

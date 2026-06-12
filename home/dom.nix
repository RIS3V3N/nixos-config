{ config, pkgs, ... }:

let
  wallpaper = "${../assets/gothic-1-remake-fu-3840x2400.jpg}";
in
{
  imports = [
    ../modules/hyprland.nix
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

  # ── Monitor layout (docked: 3 screens, laptop: eDP-1 only) ──────────────
  services.kanshi = {
    enable = true;

    settings = [
      {
        profile.name = "home";

        profile.exec = [
          "hyprctl dispatch moveworkspacetomonitor 2 DP-5"
          "hyprctl dispatch moveworkspacetomonitor 3 DP-4"
        ];

        profile.outputs = [
          {
            criteria = "eDP-1";
            position = "0,0";
            scale = 1.5;
          }
          {
            criteria = "DP-5";
            position = "1920,0";
            scale = 1.0;
          }
          {
            criteria = "DP-4";
            position = "3840,0";
            scale = 1.0;
          }
        ];
      }

      {
        profile.name = "laptop";

        profile.outputs = [
          {
            criteria = "eDP-1";
            scale = 1.5;
          }
        ];
      }

      {
        # ViewSonic QHD above the laptop screen (physical arrangement).
        # Logical dimensions:
        #   DP-1  : 2560×1440 at scale 1.0  → 2560×1440 logical px (top)
        #   eDP-1 : 2880×1800 at scale 1.5  → 1920×1200 logical px (bottom)
        profile.name = "workDesk1";

        profile.outputs = [
          {
            criteria = "DP-1";
            position = "0,0";
            scale = 1.0;
          }
          {
            criteria = "eDP-1";
            position = "0,1440";   # directly below DP-1's 1440 logical rows
            scale = 1.5;
          }
        ];
      }
    ];
  };

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

{ config, pkgs, ... }:

let
  wallpaper = "${../assets/gothic_ii_game_wp.jpg}";
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
  home.stateVersion = "26.05";

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

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
  # Delay kanshi startup so Hyprland has time to register all outputs before
  # kanshi tries to match profiles.
  systemd.user.services.kanshi.Service.ExecStartPre = "${pkgs.coreutils}/bin/sleep 2";
  services.kanshi = {
    enable = true;

    settings = [
      {
        profile.name = "home";

        profile.exec = [
          "hyprctl dispatch moveworkspacetomonitor 2 desc:AOC 24B2W1 0x00000D0F"
          "hyprctl dispatch moveworkspacetomonitor 3 desc:Dell Inc. DELL P2419H 7F99Y63"
        ];

        profile.outputs = [
          {
            criteria = "Samsung Display Corp. 0x41AA*";
            position = "0,0";
            scale = 1.5;
          }
          {
            criteria = "Dell Inc. DELL P2419H 7F99Y63*";
            position = "1920,0";
            scale = 1.0;
          }
          {
            criteria = "AOC 24B2W1 0x00000D0F*";
            position = "3840,0";
            scale = 1.0;
          }
        ];
      }

      {
        profile.name = "laptop";

        profile.exec = [
          "hyprctl dispatch moveworkspacetomonitor 2 desc:Samsung Display Corp. 0x41AA"
          "hyprctl dispatch moveworkspacetomonitor 3 desc:Samsung Display Corp. 0x41AA"
        ];

        profile.outputs = [
          {
            criteria = "Samsung Display Corp. 0x41AA*";
            scale = 1.5;
          }
        ];
      }

      {
        profile.name = "workDesk1";

        profile.exec = [
          "hyprctl dispatch moveworkspacetomonitor 2 desc:Samsung Display Corp. 0x41AA"
          "hyprctl dispatch moveworkspacetomonitor 3 desc:Samsung Display Corp. 0x41AA"
        ];

        profile.outputs = [
          {
            criteria = "DP-1";
            position = "0,0";
            scale = 1.0;
          }
          {
            criteria = "Samsung Display Corp. 0x41AA*";
            position = "0,1440";
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

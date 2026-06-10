{ config, pkgs, ... }:

{
  # networkmanager-dmenu needs to know to use fuzzel instead of dmenu/rofi
  home.packages = [ pkgs.networkmanager_dmenu ];

  home.file.".config/networkmanager-dmenu/config.ini".text = ''
    [dmenu]
    dmenu_command = fuzzel --dmenu
    compact = true
    wifi_chars = ▁▂▃▅

    [dmenu_passphrase]
    # Show dots instead of the typed passphrase
    obscure = true
  '';

  programs.waybar = {
    enable = true;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 34;
      margin-top = 8;
      margin-left = 12;
      margin-right = 12;

      modules-left = [
        "hyprland/workspaces"
      ];

      modules-center = [
        "clock"
      ];

      modules-right = [
        "cpu"
        "memory"
        "network"
        "custom/bluetooth"
        "pulseaudio"
        "battery"
        "custom/power"
      ];

      "hyprland/workspaces" = {
        disable-scroll = true;
        all-outputs = true;
      };

      clock = {
        format = "{:%H:%M:%S}";
        interval = 1;
        tooltip-format = "{:%A, %d %B %Y}";
        on-click = "gnome-calendar";
      };

      network = {
        format-wifi = "{icon} {essid}";
        format-ethernet = "󰈀 wired";
        format-disconnected = "󰖪 offline";
        format-icons = [ "󰤯" "󰤟" "󰤢" "󰤥" "󰤨" ];
        tooltip-format-wifi = "{essid}  {signalStrength}%  {frequency} MHz";
        tooltip-format-ethernet = "{ifname}  {ipaddr}";
        # fnmatch glob — matches wlp0s20f3 and any future wifi interface,
        # never matches zt*, docker*, lo, etc.
        interface = "wl*";
        on-click = "networkmanager_dmenu";
      };

      pulseaudio = {
        format = " {volume}%";
        format-muted = "󰝟 muted";
        on-click = "pavucontrol";
      };

      battery = {
        format = " {capacity}%";
        format-charging = "󰂄 {capacity}%";
        on-click = "alacritty -e btop";
      };

      cpu = {
        format = " {usage}%";
        on-click = "alacritty -e btop";
      };

      memory = {
        format = " {}%";
        on-click = "alacritty -e btop";
      };

      "custom/bluetooth" = {
        format = "󰂯";
        on-click = "blueman-manager";
      };

      "custom/power" = {
        format = "⏻";
        on-click = ''bash -c 'choice=$(printf " Logout\n Reboot\n Shutdown" | fuzzel --dmenu --prompt="Power: ") && case $choice in " Logout") hyprctl dispatch exit ;; " Reboot") systemctl reboot ;; " Shutdown") systemctl poweroff ;; esac' '';
        tooltip = false;
      };
    };

    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
        border: none;
        border-radius: 0;
        min-height: 0;
      }

      window#waybar {
        background: transparent;
        color: #cdd6f4;
      }

      #workspaces,
      #clock,
      #cpu,
      #memory,
      #network,
      #pulseaudio,
      #battery,
      #custom-power {
        background: rgba(30, 30, 46, 0.88);
        padding: 6px 12px;
        margin: 0 4px;
        border-radius: 12px;
      }

      #workspaces button {
        padding: 0 8px;
        color: #a6adc8;
        background: transparent;
      }

      #workspaces button.active {
        color: #ffffff;
        background: #89b4fa;
        border-radius: 10px;
      }

      #battery.warning {
        color: #f9e2af;
      }

      #battery.critical {
        color: #f38ba8;
      }

      #custom-power {
        color: #f38ba8;
        padding: 6px 14px;
      }

      #custom-power:hover {
        background: rgba(243, 139, 168, 0.2);
        border-radius: 12px;
      }
    '';
  };
}

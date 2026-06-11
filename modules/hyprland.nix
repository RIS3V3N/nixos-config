{ config, pkgs, ... }:

{
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "${pkgs.alacritty}/bin/alacritty";
      "$menu" = "${pkgs.fuzzel}/bin/fuzzel";

      monitor = [
        "eDP-1,preferred,auto,1.5"
        "DP-5,preferred,auto,1"
        "DP-4,preferred,auto,1"
        ",preferred,auto,1"
      ];

      workspace = [
        "1, monitor:eDP-1, default:true, name:notes"
        "2, name:web"
        "3, name:code"
        "4, name:remote"
        "5, name:api"
        "special:perf, on-created-empty:alacritty -e btop"
        "special:music, on-created-empty:spotify"
      ];

      env = [
        "XCURSOR_THEME,Bibata-Modern-Classic"
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_THEME,Bibata-Modern-Classic"
        "HYPRCURSOR_SIZE,24"
        "NIXOS_OZONE_WL,1"
      ];

      exec-once = [
        "${pkgs.hyprland}/bin/hyprctl setcursor Bibata-Modern-Classic 24"
        "${pkgs.waybar}/bin/waybar"
        "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator"  # NM secrets agent for VPN SSO
        "wl-paste --type text --watch cliphist store"
        "${pkgs.hyprland}/bin/hyprctl dispatch exec \"[workspace 2 silent] brave\""
        "${pkgs.hyprland}/bin/hyprctl dispatch exec \"[workspace 2 silent] alacritty\""
        "${pkgs.hyprland}/bin/hyprctl dispatch exec \"[workspace 3 silent] code\""
        "${pkgs.hyprland}/bin/hyprctl dispatch exec \"[workspace 1 silent] subl\""
        "${pkgs.hyprland}/bin/hyprctl dispatch exec \"[workspace 4 silent] remmina\""
        "${pkgs.hyprland}/bin/hyprctl dispatch exec \"[workspace 4 silent] dolphin\""
        "${pkgs.hyprland}/bin/hyprctl dispatch exec \"[workspace 5 silent] insomnia\""
      ];

      input = {
        kb_layout = "ch";
        kb_variant = "de";

        touchpad = {
          natural_scroll = true;
        };
      };

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
      };

      decoration = {
        rounding = 10;
      };

      bind = [
        "$mod, RETURN, exec, $terminal"
        "$mod, D, exec, $menu"
        "$mod, Q, killactive"
        "$mod SHIFT, E, exit"

        "$mod, E, exec, dolphin"

        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"

        "$mod SHIFT, left, swapwindow, l"
        "$mod SHIFT, right, swapwindow, r"
        "$mod SHIFT, up, swapwindow, u"
        "$mod SHIFT, down, swapwindow, d"

        "$mod, S, togglespecialworkspace, perf"
        "$mod SHIFT, S, movetoworkspace, special:perf"
        "$mod, M, togglespecialworkspace, music"
        "$mod SHIFT, M, movetoworkspace, special:music"
        "$mod, R, workspace, 4"
        "$mod, A, workspace, 5"
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"

        "$mod, V, exec, bash -c 'cliphist list | fuzzel --dmenu | cliphist decode | wl-copy'"
        "$mod, N, exec, dunstctl history-pop"

        # Window layout
        "$mod, F, fullscreen, 0"
        "$mod, Space, togglefloating"
        "$mod, P, pin"

        # Resize with keyboard
        "$mod CTRL, left, resizeactive, -40 0"
        "$mod CTRL, right, resizeactive, 40 0"
        "$mod CTRL, up, resizeactive, 0 -40"
        "$mod CTRL, down, resizeactive, 0 40"

        # Screenshots
        ", Print, exec, sh -c 'mkdir -p ~/Pictures/Screenshots && grim -g \"$(slurp)\" - | tee ~/Pictures/Screenshots/screenshot-$(date +%s).png | wl-copy --type image/png'"
        "$mod, Print, exec, sh -c 'grim -g \"$(slurp)\" - | tee /tmp/screenshot.png | wl-copy --type image/png; swappy -f /tmp/screenshot.png'"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };
  };

  programs.hyprlock.enable = true;

  services.hypridle = {
    enable = true;

    settings = {
      listener = [
        {
          timeout = 300;
          on-timeout = "hyprlock";
        }
        {
          timeout = 600;
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
        }
      ];
    };
  };
}

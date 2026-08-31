{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    brightnessctl # screen + keyboard backlight
    playerctl # media playback
    qalculate-gtk # calculator (F2)
    # Cycles kbd backlight: 0% → 25% → 50% → 75% → 100% → 0% → …
    (writeShellScriptBin "kbd-backlight-cycle" ''
      max=$(${brightnessctl}/bin/brightnessctl -d '*::kbd_backlight' max)
      cur=$(${brightnessctl}/bin/brightnessctl -d '*::kbd_backlight' get)
      step=$((max / 4))
      [ "$step" -eq 0 ] && step=1
      if [ "$cur" -ge "$max" ]; then
        ${brightnessctl}/bin/brightnessctl -d '*::kbd_backlight' set 0
      else
        next=$((cur + step))
        [ "$next" -gt "$max" ] && next="$max"
        ${brightnessctl}/bin/brightnessctl -d '*::kbd_backlight' set "$next"
      fi
    '')
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "${pkgs.alacritty}/bin/alacritty";
      "$menu" = "${pkgs.fuzzel}/bin/fuzzel";

      # Monitors are managed by hyprmoncfg (see ../modules/monitors.nix), which
      # generates ~/.config/hypr/monitors.conf.  This is only the fallback used
      # until a profile is applied; the sourced file below overrides it.
      monitor = [
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
        "${pkgs.networkmanagerapplet}/bin/nm-applet --indicator" # NM secrets agent for VPN SSO
        "wl-paste --type text --watch cliphist store"
        # Rebuild KDE's app/MIME database so Dolphin can resolve desktop entries.
        "${pkgs.kdePackages.kservice}/bin/kbuildsycoca6 --noincremental"
        # Load SSH keys into gpg-agent on login.  A graphical pinentry prompt
        # appears once per key that has a passphrase; after that the passphrase
        # is cached for 24 h (defaultCacheTtl) so you won't be asked again.
        "sh -c '${pkgs.openssh}/bin/ssh-add ~/.ssh/id_personal ~/.ssh/id_work_gitlab ~/.ssh/id_work_github ~/.ssh/id_work_bitbucket; [ -f ~/.ssh/extra-keys ] && xargs ${pkgs.openssh}/bin/ssh-add < ~/.ssh/extra-keys'"
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

      windowrule = [
        # Calendar popup — float and center it when opened from waybar
        "float, class:^(gnome-calendar)$"
        "size 420 540, class:^(gnome-calendar)$"
        "center, class:^(gnome-calendar)$"
        "animation slide top, class:^(gnome-calendar)$"

        # xdg-desktop-portal dialogs (screen-share picker, file choosers, save-as
        # dialogs from Brave/Chromium, etc.) — always float + center so they
        # never get stuck behind a fullscreened window.
        "float, class:^(xdg-desktop-portal.*)$"
        "center, class:^(xdg-desktop-portal.*)$"
        # Force focus immediately on open, so the first click of a double-click
        # isn't consumed just focusing the window (which broke double-click).
        "stayfocused, class:^(xdg-desktop-portal.*)$"
        "float, title:^(Save [Ff]ile|Open [Ff]ile|Save [Aa]s)$"
        "center, title:^(Save [Ff]ile|Open [Ff]ile|Save [Aa]s)$"
        "stayfocused, title:^(Save [Ff]ile|Open [Ff]ile|Save [Aa]s)$"
      ];

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
      };

      decoration = {
        rounding = 10;
      };

      misc = {
        # Grant focus immediately to windows that request it (activate), so
        # newly-opened dialogs (file pickers, screen-share prompts) don't
        # require an initial click just to gain focus first — that extra click
        # was breaking double-click gestures in GTK file choosers.
        focus_on_activate = true;
        # When a new window opens while the active one is fullscreen, un-
        # fullscreen the current window and focus the new one instead of
        # leaving it stuck behind (e.g. screen-share picker, file save dialog
        # popping up while a browser is fullscreened).
        new_window_takes_over_fullscreen = 2;
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
        "$mod, L, exec, hyprlock"
        "$mod, L, exec, hyprlock"

        # Resize with keyboard
        "$mod CTRL, left, resizeactive, -40 0"
        "$mod CTRL, right, resizeactive, 40 0"
        "$mod CTRL, up, resizeactive, 0 -40"
        "$mod CTRL, down, resizeactive, 0 40"

        # Screenshots
        ", Print, exec, sh -c 'mkdir -p ~/Pictures/Screenshots && grim -g \"$(slurp)\" - | tee ~/Pictures/Screenshots/screenshot-$(date +%s).png | wl-copy --type image/png'"
        "$mod, Print, exec, sh -c 'grim -g \"$(slurp)\" - | tee /tmp/screenshot.png | wl-copy --type image/png; swappy -f /tmp/screenshot.png'"

        # Screen recording
        "$mod SHIFT, Print, exec, sh -c 'mkdir -p ~/Videos/Recordings && wf-recorder -g \"$(slurp)\" -f ~/Videos/Recordings/recording-$(date +%F-%H%M%S).mp4'"
        "$mod CTRL, Print, exec, pkill -INT wf-recorder"
      ];

      # Repeatable binds — hold the key to keep changing
      bindel = [
        # XF86MonBrightnessDown → screen brightness down
        ", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
        # XF86MonBrightnessUp   → screen brightness up
        ", XF86MonBrightnessUp,   exec, brightnessctl set 5%+"
        # XF86AudioLowerVolume  → volume down
        ", XF86AudioLowerVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        # XF86AudioRaiseVolume  → volume up
        ", XF86AudioRaiseVolume,  exec, wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"
      ];

      # Non-repeatable binds — fire once per keypress
      bindl = [
        # XF86Calculator   → calculator
        ", XF86Calculator,     exec, qalculate-gtk"
        # XF86KbdBrightnessUp → keyboard backlight cycle (0→25→50→75→100→0%)
        ", XF86KbdBrightnessUp,   exec, kbd-backlight-cycle"
        ", XF86KbdBrightnessDown, exec, kbd-backlight-cycle"
        # XF86AudioMute    → speaker mute toggle
        ", XF86AudioMute,      exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        # XF86AudioMicMute → mic mute toggle
        ", XF86AudioMicMute,   exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        # XF86AudioPlay    → play / pause
        ", XF86AudioPlay,      exec, playerctl play-pause"
        ", XF86AudioStop,      exec, playerctl stop"
        ", XF86AudioNext,      exec, playerctl next"
        ", XF86AudioPrev,      exec, playerctl previous"
      ];

      bindm = [
        "$mod, mouse:272, movewindow"
        "$mod, mouse:273, resizewindow"
      ];
    };

    # Appended last so it wins over the `monitor`/`workspace` defaults above.
    # hyprmoncfg refuses to write monitors.conf unless hyprland.conf sources it.
    extraConfig = ''
      source = ~/.config/hypr/monitors.conf
    '';
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

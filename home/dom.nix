{ config, pkgs, ... }:

let
  wallpaper = "${../assets/gothic_ii_game_wp.jpg}";
in
{
  home.username = "dom";
  home.homeDirectory = "/home/dom";
  home.stateVersion = "25.11";
  home.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  home.packages = with pkgs; [
    alacritty
    waybar
    dunst
    fuzzel
    hyprpaper
    hyprlock
    grim
    slurp
    swappy
    wl-clipboard
    fastfetch
    cliphist
    libnotify
    # settings / desktop utilities
    pavucontrol
    alsa-utils
    pulseaudio
    networkmanagerapplet
    blueman
    nwg-look
    brightnessctl
    playerctl
    btop
    eza
    bat
    fd
    ripgrep
    jq
    kdePackages.dolphin
    kdePackages.ark
    kdePackages.kio-extras
    python3
    uv
    ruff
    pyright
    lazydocker
    wdisplays
    kanshi
    onedrive
    remmina
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "alacritty";
      "$menu" = "fuzzel";

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
      ];

      exec-once = [
        "hyprctl setcursor Bibata-Modern-Classic 24"
        "waybar"
        "wl-paste --type text --watch cliphist store"
        "hyprctl dispatch exec \"[workspace 2 silent] brave\""
        "hyprctl dispatch exec \"[workspace 2 silent] alacritty\""
        "hyprctl dispatch exec \"[workspace 3 silent] code\""
        "hyprctl dispatch exec \"[workspace 1 silent] subl\""
        "hyprctl dispatch exec \"[workspace 4 silent] remmina\""
        "hyprctl dispatch exec \"[workspace 4 silent] dolphin\""
        "hyprctl dispatch exec \"[workspace 5 silent] insomnia\""
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
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"

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

  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=12";
        width = 45;
        horizontal-pad = 20;
        vertical-pad = 12;
        inner-pad = 10;
        terminal = "alacritty";
      };

      colors = {
        background = "1e1e2eee";
        text = "cdd6f4ff";
        match = "f38ba8ff";
        selection = "313244ff";
        selection-text = "cdd6f4ff";
        border = "89b4faff";
      };
    };
  };

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
        format-wifi = " {essid}";
        format-ethernet = "󰈀 wired";
        format-disconnected = "󰖪 offline";
        on-click = "nm-connection-editor";
      };

      pulseaudio = {
        format = " {volume}%";
        format-muted = "󰝟 muted";
        on-click = "pavucontrol";
      };

      battery = {
        format = " {capacity}%";
        format-charging = "󰂄 {capacity}%";
        on-click = "alacritty -e btop";
      };

      cpu = {
        format = " {usage}%";
        on-click = "alacritty -e btop";
      };

      memory = {
        format = " {}%";
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

  services.dunst = {
    enable = true;

    settings = {
      global = {
        history_length = 50;
      };
    };
  };
  services.hypridle.enable = true;

  home.pointerCursor = {
    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    cursorTheme = {
      name = "Bibata-Modern-Classic";
      package = pkgs.bibata-cursors;
      size = 24;
    };

    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11;
    };
  };

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

  programs.brave = {
    enable = true;

    extensions = [
      # Bitwarden
      { id = "nngceckbapebfimnlniiiahkandclblb"; }

      # React DevTools
      { id = "fmkadmapgofadopljbjfkapdkoienihi"; }

      # SponsorBlock
      { id = "mnjggcdmjocbbbhaepdhchncahnbgone"; }

      # IP Address and Domain Information
      { id = "poeojclicodamonabcabmapamjkkmnnk"; }

      # AI Grammar Checker / LanguageTool
      { id = "oldceeleldhonbafppcapldpdifcinji"; }
    ];

    commandLineArgs = [
      "--ozone-platform=wayland"
      "--enable-wayland-ime"

      # Disable some Chromium annoyances
      "--disable-features=PasswordManagerOnboarding"
      "--disable-features=AutofillEnableAccountWalletStorage"

      # Disable Brave AI
      "--disable-brave-ai-chat"

      # Disable crypto wallet
      "--disable-brave-wallet"

      # Optional:
      "--disable-features=BraveRewards"
    ];
  };

  programs.hyprlock.enable = true;

  services.hypridle.settings = {
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

  services.hyprpaper = {
    enable = true;

    settings = {
      preload = [
        wallpaper
      ];

      wallpaper = [
        ",${wallpaper}"
      ];
    };
  };

  programs.fastfetch.enable = true;

  programs.bash = {
    enable = true;

    shellAliases = {
      gs = "git status";
      gl = "git log --oneline --graph --decorate";
      gp = "git push";
      k = "kubectl";
      d = "docker";
      tf = "terraform";
      ls = "eza";
      ll = "eza -lah";
      cat = "bat";
    };

    initExtra = ''
      if [[ $- == *i* ]]; then
        fastfetch
      fi
    '';
  };

  programs.alacritty = {
    enable = true;

    settings = {
      window = {
        opacity = 0.90;
        dynamic_padding = true;
      };

      font = {
        size = 11.5;

        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };

        bold = {
          family = "JetBrainsMono Nerd Font";
          style = "Bold";
        };

        italic = {
          family = "JetBrainsMono Nerd Font";
          style = "Italic";
        };
      };

      scrolling.history = 50000;

      selection.save_to_clipboard = true;

      cursor = {
        style = {
          shape = "Beam";
          blinking = "Off";
        };
      };

      mouse.hide_when_typing = true;

      env = {
        TERM = "xterm-256color";
      };
    };
  };

  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };

      python = {
        format = "via [🐍 $version ( venv: $virtualenv)]($style) ";
      };

      cmake = {
        disabled = true;
      };

      directory.truncation_length = 3;

      git_branch.symbol = " ";
    };
  };

  programs.fzf.enable = true;
  programs.zoxide.enable = true;

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "inode/directory" = [ "org.kde.dolphin.desktop" ];
    };
  };

  home.file.".vscode/argv.json".text = ''
    {
      // Fixes the "an OS keyring couldn't be identified for
      // storing the encryption..." error
      "password-store": "gnome-libsecret"
    }
  '';

  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhs;
    mutableExtensionsDir = true;

    profiles.default = {
      userSettings = {
        "editor.fontFamily" = "JetBrainsMono Nerd Font";
        "editor.fontLigatures" = true;
        "editor.formatOnSave" = true;
        "editor.minimap.enabled" = false;
        "terminal.integrated.defaultProfile.linux" = "bash";
        "files.trimTrailingWhitespace" = true;
      };
      extensions = with pkgs.vscode-extensions; [
        ms-python.python
        ms-python.vscode-pylance
        ms-python.debugpy
        redhat.vscode-yaml
        esbenp.prettier-vscode
        timonwong.shellcheck
        ms-azuretools.vscode-docker
        ms-vscode-remote.remote-containers
        ms-vscode-remote.remote-ssh
        ms-vscode-remote.remote-ssh-edit
        ms-vscode.remote-explorer
        ms-vscode.cmake-tools
        ms-vscode.cpptools
        ms-vscode.cpptools-extension-pack
        ms-vscode.makefile-tools
        eamodio.gitlens
        github.vscode-github-actions
        donjayamanne.githistory
        twxs.cmake
      ];
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

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
}

{ config, pkgs, ... }:

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
    wl-clipboard
    fastfetch
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
        "dunst"
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

        "$mod, left, movefocus, l"
        "$mod, right, movefocus, r"
        "$mod, up, movefocus, u"
        "$mod, down, movefocus, d"
      ];
    };
  };

  programs.alacritty = {
    enable = true;
    settings = {
      font = {
        size = 11;
        normal = {
          family = "JetBrainsMono Nerd Font";
          style = "Regular";
        };
      };
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
    style = ''
      * {
        font-family: "JetBrainsMono Nerd Font";
        font-size: 13px;
      }
    '';
  };

  services.dunst.enable = true;

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
}

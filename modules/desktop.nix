{ config, pkgs, ... }:

{
  home.packages = with pkgs; [
    # Wayland / display
    waybar
    dunst
    fuzzel
    hyprpaper
    hyprlock
    grim
    slurp
    swappy
    wl-clipboard
    cliphist
    libnotify
    wdisplays
    kanshi
    # Desktop utilities
    pavucontrol
    alsa-utils
    pulseaudio
    networkmanagerapplet
    blueman
    nwg-look
    brightnessctl
    playerctl
    # File management
    kdePackages.dolphin
    kdePackages.ark
    kdePackages.kio-extras
    remmina
  ];

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

  programs.brave = {
    enable = true;

    extensions = [
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden
      { id = "fmkadmapgofadopljbjfkapdkoienihi"; } # React DevTools
      { id = "mnjggcdmjocbbbhaepdhchncahnbgone"; } # SponsorBlock
      { id = "poeojclicodamonabcabmapamjkkmnnk"; } # IP Address and Domain Information
      { id = "oldceeleldhonbafppcapldpdifcinji"; } # AI Grammar Checker / LanguageTool
    ];

    commandLineArgs = [
      "--ozone-platform=wayland"
      "--enable-wayland-ime"
      "--disable-features=PasswordManagerOnboarding"
      "--disable-features=AutofillEnableAccountWalletStorage"
      "--disable-brave-ai-chat"
      "--disable-brave-wallet"
      "--disable-features=BraveRewards"
    ];
  };

  services.dunst = {
    enable = true;
    settings = {
      global = {
        history_length = 50;
      };
    };
  };

  services.hyprpaper = {
    enable = true;
    # Wallpaper preload/wallpaper entries are set per-host in home/<user>.nix
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "org.kde.dolphin.desktop" ];
    };
  };

  # ── Yazi (TUI file manager) ───────────────────────────────────────────────
  programs.yazi = {
    enable = true;
    enableBashIntegration = true; # adds `y` shell wrapper that cds on exit
  };
}

{
  config,
  pkgs,
  lib,
  ...
}:

{
  # Tell Qt multimedia to use the ffmpeg backend directly, skipping the
  # pipewire dynamic-load attempt that always fails on NixOS.
  home.sessionVariables = {
    QT_MEDIA_BACKEND = "ffmpeg";
    # Suppress Qt multimedia plugin-probe noise (pipewire-0.3 not on LD path on NixOS)
    QT_LOGGING_RULES = "qt.multimedia.symbolsresolver.warning=false";
  };

  # Pre-create Dolphin's global viewproperties directory so it stops
  # spamming "Could not load default global viewproperties" on every open.
  home.activation.dolphinViewproperties = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.local/share/dolphin/viewproperties/global"
  '';

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
    wf-recorder
    ffmpeg
    wl-clipboard
    cliphist
    libnotify
    wdisplays
    # Desktop utilities
    pavucontrol
    alsa-utils
    pulseaudio
    networkmanagerapplet
    blueman
    nwg-look
    brightnessctl
    playerctl
    # Camera
    cheese
    # Media playback
    vlc
    # File management
    kdePackages.dolphin
    kdePackages.ark
    kdePackages.kio-extras
    kdePackages.gwenview # image viewer
    networkmanagerapplet # nm-applet: NM secrets agent + SSO auth dialog
    remmina
    deluge-gtk
    gnome-calendar # proper calendar window (click the clock in waybar)
    ventoy-full-qt # multi-ISO bootable USB (insecure: ships binary blobs, allowed explicitly)
    xorg.xhost # needed to grant root XWayland access for ventoy-gui: xhost +si:localuser:root
    # SquashFS
    squashfsTools # unsquashfs / mksquashfs CLI tools
    squashfuse # CLI fallback: squashfuse <img> <dir>
    (writeShellScriptBin "squashfs-mount" ''
      set -euo pipefail
      img="''${1:-}"
      if [ -z "$img" ] || [ ! -f "$img" ]; then
        notify-send "SquashFS" "No file given" --icon=dialog-error 2>/dev/null || true
        exit 1
      fi
      img=$(realpath "$img")
      name=$(basename "$img")

      # Attach as a read-only loop device via UDisks2.
      # Output: "Mapped file /path as /dev/loopN."
      loop_out=$(${pkgs.udisks2}/bin/udisksctl loop-setup \
        --file "$img" --read-only --no-user-interaction 2>&1) || {
        notify-send "SquashFS Error" "Could not attach loop device" --icon=dialog-error 2>/dev/null || true
        echo "loop-setup failed: $loop_out" >&2
        exit 1
      }
      # Strip trailing dot, grab last word → /dev/loopN
      loop=$(printf '%s' "$loop_out" | sed 's/[.]$//' | awk 'NR==1{print $NF}')
      [ -b "$loop" ] || {
        notify-send "SquashFS Error" "Bad loop device: $loop" --icon=dialog-error 2>/dev/null || true
        echo "Expected block device, got: $loop (output: $loop_out)" >&2
        exit 1
      }

      # Mount via UDisks2 — appears in Dolphin sidebar with eject button.
      mount_out=$(${pkgs.udisks2}/bin/udisksctl mount \
        --block-device "$loop" --no-user-interaction 2>&1) || {
        ${pkgs.udisks2}/bin/udisksctl loop-delete \
          --block-device "$loop" --no-user-interaction 2>/dev/null || true
        notify-send "SquashFS Error" "Mount failed" --icon=dialog-error 2>/dev/null || true
        echo "mount failed: $mount_out" >&2
        exit 1
      }
      # Output: "Mounted /dev/loopN at /run/media/dom/name."
      mnt=$(printf '%s' "$mount_out" | sed 's/[.]$//' | awk 'NR==1{print $NF}')

      notify-send "SquashFS" "Mounted $name — click eject in sidebar to unmount" \
        --icon=drive-harddisk 2>/dev/null || true

      # Background watcher: Dolphin eject unmounts but leaves the loop device
      # attached. Wait for the mount point to disappear, then delete the loop.
      (
        while ${pkgs.util-linux}/bin/mountpoint -q "$mnt" 2>/dev/null; do
          sleep 3
        done
        ${pkgs.udisks2}/bin/udisksctl loop-delete \
          --block-device "$loop" --no-user-interaction 2>/dev/null || true
        notify-send "SquashFS" "Unmounted $name" --icon=drive-harddisk 2>/dev/null || true
      ) &
      disown $!
    '')
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

  xdg.desktopEntries."squashfs-mount" = {
    name = "Mount SquashFS";
    exec = "squashfs-mount %f";
    mimeType = [
      "application/vnd.squashfs"
      "application/x-squashfs"
    ];
    noDisplay = true;
    terminal = false;
  };

  # Dolphin service menu: right-click a squashfs file → Mount SquashFS
  # Also shown on loop-device mount points via the sidebar eject button.
  # Unmounting is done via the eject icon in Dolphin's sidebar —
  # UDisks2 handles both unmount and loop-delete automatically.
  home.file.".local/share/kio/servicemenus/squashfs-unmount.desktop".text = ''
    [Desktop Entry]
    Type=Service
    X-KDE-ServiceTypes=KonqPopupMenu/Plugin
    MimeType=application/vnd.squashfs;application/x-squashfs;
    Actions=MountSquashFS

    [Desktop Action MountSquashFS]
    Name=Mount SquashFS
    Icon=media-mount
    Exec=squashfs-mount %f
  '';

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = [ "org.kde.dolphin.desktop" ];
      "application/vnd.squashfs" = [ "squashfs-mount.desktop" ];
      "application/x-squashfs" = [ "squashfs-mount.desktop" ];
      "image/jpeg" = [ "org.kde.gwenview.desktop" ];
      "image/png" = [ "org.kde.gwenview.desktop" ];
      "image/gif" = [ "org.kde.gwenview.desktop" ];
      "image/webp" = [ "org.kde.gwenview.desktop" ];
      "image/bmp" = [ "org.kde.gwenview.desktop" ];
      "image/tiff" = [ "org.kde.gwenview.desktop" ];
      "image/svg+xml" = [ "org.kde.gwenview.desktop" ];
      # Archives → Ark
      "application/zip" = [ "org.kde.ark.desktop" ];
      "application/x-zip-compressed" = [ "org.kde.ark.desktop" ];
      "application/x-tar" = [ "org.kde.ark.desktop" ];
      "application/x-compressed-tar" = [ "org.kde.ark.desktop" ]; # .tar.gz
      "application/x-bzip-compressed-tar" = [ "org.kde.ark.desktop" ]; # .tar.bz2
      "application/x-xz-compressed-tar" = [ "org.kde.ark.desktop" ]; # .tar.xz
      "application/x-zstd-compressed-tar" = [ "org.kde.ark.desktop" ]; # .tar.zst
      "application/x-7z-compressed" = [ "org.kde.ark.desktop" ];
      "application/x-rar" = [ "org.kde.ark.desktop" ];
      "application/x-rar-compressed" = [ "org.kde.ark.desktop" ];
      "application/gzip" = [ "org.kde.ark.desktop" ];
      "application/x-bzip2" = [ "org.kde.ark.desktop" ];
      "application/x-xz" = [ "org.kde.ark.desktop" ];
      "application/zstd" = [ "org.kde.ark.desktop" ];
    };
  };

  # ── Yazi (TUI file manager) ───────────────────────────────────────────────
  programs.yazi = {
    enable = true;
    enableBashIntegration = true; # adds `y` shell wrapper that cds on exit
  };
}

{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/backup.nix
    ../../modules/work-network.nix
    ../../modules/wireguard.nix
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ── Nix GC ───────────────────────────────────────────────────────────────
  # No count-based boot entry limit — a count would silently evict the last
  # known-good config if you rebuild many times in a session.  Instead, keep
  # everything for 30 days so you can always roll back, then let the weekly GC
  # remove anything older.  The safety cap of 50 only guards against an
  # accidentally full EFI partition in extreme cases.
  boot.loader.systemd-boot.configurationLimit = 50;
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.settings.auto-optimise-store = true;

  # ── Boot ─────────────────────────────────────────────────────────────────
  # Use latest kernel for Lunar Lake hardware support (audio, NPU, etc.)
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.luks.devices."luks-2f671c9e-a03d-4b16-888b-f35282a59dd3".device =
    "/dev/disk/by-uuid/2f671c9e-a03d-4b16-888b-f35282a59dd3";

  # ── Networking ───────────────────────────────────────────────────────────
  networking.hostName = "nixhorse";

  networking.networkmanager = {
    enable = true;
    plugins = with pkgs; [
      networkmanager-openconnect
    ];
  };

  # ── Locale / time ────────────────────────────────────────────────────────
  time.timeZone = "Europe/Zurich";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "sg";

  # ── Display ──────────────────────────────────────────────────────────────
  services.xserver.enable = true;
  services.xserver.xkb = {
    layout = "ch";
    variant = "";
  };

  # GDM only — no GNOME desktop
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.wayland = true;

  # Hyprland (system-level enabling required for portals/polkit)
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # ── Audio ────────────────────────────────────────────────────────────────
  # Lunar Lake-m requires SOF (Sound Open Firmware) for internal speakers.
  # sof-firmware is pulled in via linux-firmware (enableRedistributableFirmware).
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.sof-firmware ];

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber = {
      enable = true;
      extraConfig."51-sof-hda-hifi-profile" = {
        # WirePlumber defaults the Lunar Lake SOF card to the raw "pro-audio"
        # profile which bypasses UCM and never activates the speaker amplifier.
        # Force the HiFi profile that includes the Speaker UCM verb instead.
        "monitor.alsa.rules" = [
          {
            matches = [ { "device.name" = "~alsa_card.*skl_hda_dsp.*"; } ];
            actions.update-props = {
              "device.profile" = "HiFi (HDMI1, HDMI2, HDMI3, Mic1, Mic2, Speaker)";
            };
          }
        ];
      };
    };
  };

  # ── Printing ─────────────────────────────────────────────────────────────
  services.printing.enable = true;

  # ── Users ────────────────────────────────────────────────────────────────
  users.users.dom = {
    isNormalUser = true;
    description = "dom";
    extraGroups = [ "networkmanager" "wheel" "docker" ];
  };

  # ── Nixpkgs ──────────────────────────────────────────────────────────────
  nixpkgs.config.allowUnfree = true;
  # sublime4 depends on openssl-1.1.1w (EOL but required by the package)
  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1w"
    "ventoy-qt5-1.1.10"
  ];

  # ── System packages ──────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    pciutils
    openssl
    openconnect
    networkmanager-openconnect
    bibata-cursors
    adwaita-icon-theme
    spotify
    sublime4
    insomnia
    alacritty  # emergency fallback if home-manager hasn't activated yet
    pwgen
  ];

  # ── Brave managed policy (disables telemetry / AI / wallet) ──────────────
  environment.etc."brave/policies/managed/brave.json".text = ''
    {
      "BraveRewardsDisabled": true,
      "BraveWalletDisabled": true,
      "BraveAIChatEnabled": false,
      "BraveVPNDisabled": true,
      "DefaultSearchProviderEnabled": true,
      "DefaultSearchProviderName": "DuckDuckGo",
      "DefaultSearchProviderSearchURL": "https://duckduckgo.com/?q={searchTerms}"
    }
  '';

  # ── Fonts ─────────────────────────────────────────────────────────────────
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
  ];

  # ── Virtualisation ───────────────────────────────────────────────────────
  virtualisation.docker.enable = true;

  # Some work scripts (e.g. launch.py) call subprocess with env=env_vars where
  # env_vars is built from a .env file and never includes PATH.  When no PATH
  # is present, Linux execvpe falls back to the POSIX default: /bin:/usr/bin.
  # Symlinking docker there makes it visible to any subprocess regardless of how
  # its environment was constructed.
  systemd.tmpfiles.rules = [
    "L+ /usr/bin/docker         - - - - /run/current-system/sw/bin/docker"
  ];

  # ── Bluetooth ─────────────────────────────────────────────────────────────
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings = {
      General = {
        # Required for BLE HID devices (e.g. MX Master 3S via HID-over-GATT)
        Experimental = true;
        # Reduces reconnection latency
        FastConnectable = true;
      };
      Policy = {
        AutoEnable = true;
        # Allow BLE mice (MX Master 3S) to complete "just works" pairing
        # without a confirmation dialog — the default ("confirm") silently
        # blocks pairing because no agent is present to answer the prompt.
        JustWorksRepairing = "always";
      };
    };
  };
  services.blueman.enable = true;

  # Prevent the Bluetooth USB adapter from being suspended by the kernel,
  # which causes constant disconnect/reconnect loops with BLE mice.
  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=0
  '';

  # ── Removable device management ──────────────────────────────────────────
  # Required for Dolphin (and any KDE Solid app) to enumerate and mount
  # USB drives, SD cards, etc. via the org.freedesktop.UDisks2 D-Bus service.
  services.udisks2.enable = true;

  # ── Keyring ──────────────────────────────────────────────────────────────
  services.gnome.gnome-keyring.enable = true;

  # ── Polkit ───────────────────────────────────────────────────────────────
  # Allow dom to mount squashfs images as loop devices via UDisks2 without
  # authentication prompts.  Covers nested mounts (a squashfs inside another
  # already-mounted squashfs) because polkit by default is conservative about
  # files not in the user's home directory.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      var ok = [
        "org.freedesktop.udisks2.loop-setup",
        "org.freedesktop.udisks2.filesystem-mount",
        "org.freedesktop.udisks2.filesystem-mount-system",
        "org.freedesktop.udisks2.loop-delete",
        "org.freedesktop.udisks2.filesystem-unmount-others",
      ];
      if (ok.indexOf(action.id) >= 0 &&
          subject.user === "dom" &&
          subject.local && subject.active) {
        return polkit.Result.YES;
      }
    });
  '';

  # ── Portals ──────────────────────────────────────────────────────────────
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-gtk
    pkgs.xdg-desktop-portal-hyprland
  ];

  # ── Firefox ──────────────────────────────────────────────────────────────
  programs.firefox.enable = true;

  # ── nix-ld ───────────────────────────────────────────────────────────────
  # Makes pre-built Linux binaries (e.g. GitHub Copilot CLI, vendor tools)
  # work on NixOS by providing a dynamic linker shim at the path they expect.
  programs.nix-ld.enable = true;

  system.stateVersion = "25.11";
}

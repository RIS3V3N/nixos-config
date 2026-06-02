{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # ── Boot ─────────────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.luks.devices."luks-2f671c9e-a03d-4b16-888b-f35282a59dd3".device =
    "/dev/disk/by-uuid/2f671c9e-a03d-4b16-888b-f35282a59dd3";

  # ── Networking ───────────────────────────────────────────────────────────
  networking.hostName = "nixhorse";
  networking.networkmanager.enable = true;

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
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
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
  nixpkgs.config.permittedInsecurePackages = [ "openssl-1.1.1w" ];

  # ── System packages ──────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    pciutils
    openconnect
    bibata-cursors
    adwaita-icon-theme
    spotify
    sublime4
    insomnia
    alacritty  # emergency fallback if home-manager hasn't activated yet
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

  # ── Bluetooth ─────────────────────────────────────────────────────────────
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # ── Portals ──────────────────────────────────────────────────────────────
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

  # ── Firefox ──────────────────────────────────────────────────────────────
  programs.firefox.enable = true;

  system.stateVersion = "25.11";
}

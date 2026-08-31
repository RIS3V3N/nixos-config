{
  config,
  pkgs,
  lib,
  ...
}:

let
  # ── Runtime env file ──────────────────────────────────────────────────────
  # All sensitive values (private key, server pubkey, endpoint) live in
  # ~/.config/wireguard/env so they never end up in the repo.
  # Run 'wg-setup' to create a commented template, then fill it in.

  envTemplate = pkgs.writeText "wireguard-env-template" ''
    # WireGuard VPN configuration — NOT committed to git.
    # Fill in your values, then run: wg-up
    #
    # Generate a client key pair (run once on this machine):
    #   wg genkey | tee /tmp/wg-private.key | wg pubkey > /tmp/wg-public.key
    #   cat /tmp/wg-private.key   → paste as WG_PRIVATE_KEY
    #   cat /tmp/wg-public.key    → send to server admin to add as a peer
    #   rm /tmp/wg-private.key /tmp/wg-public.key

    # Your client private key (output of `wg genkey`)
    WG_PRIVATE_KEY=""

    # Server public key (provided by server admin)
    WG_SERVER_PUBKEY=""

    # Server endpoint: hostname or IP and UDP port
    WG_ENDPOINT="vpn.example.com:51820"

    # IP address assigned to this client on the WireGuard network.
    # Must match the AllowedIPs /32 entry for this peer on the server.
    WG_CLIENT_IP="10.8.0.2/32"

    # Comma-separated CIDRs to route through the tunnel.
    # "0.0.0.0/0, ::/0" = route all traffic (full VPN).
    # Narrow to specific subnets for split-tunnel.
    WG_ALLOWED_IPS="0.0.0.0/0, ::/0"

    # DNS server to use while the tunnel is up (IP address).
    # Leave empty to keep your existing DNS unchanged.
    WG_DNS=""

    # Optional pre-shared key for extra security (output of `wg genpsk`).
    # Leave empty if the server peer entry has no PresharedKey.
    WG_PRESHARED_KEY=""
  '';

  # Sourced at the top of every wg-* script.
  loadEnv = ''
    _wgenv="$HOME/.config/wireguard/env"
    if [ ! -f "$_wgenv" ]; then
      echo "✗  WireGuard config not found: $_wgenv" >&2
      echo "   Run 'wg-setup' to create a template." >&2
      exit 1
    fi
    # shellcheck source=/dev/null
    . "$_wgenv"
    : "''${WG_PRIVATE_KEY:?WG_PRIVATE_KEY not set in wireguard env file}"
    : "''${WG_SERVER_PUBKEY:?WG_SERVER_PUBKEY not set in wireguard env file}"
    : "''${WG_ENDPOINT:?WG_ENDPOINT not set in wireguard env file}"
    : "''${WG_CLIENT_IP:?WG_CLIENT_IP not set in wireguard env file}"
    : "''${WG_ALLOWED_IPS:?WG_ALLOWED_IPS not set in wireguard env file}"
    unset _wgenv
  '';

in
{
  # WireGuard is in the mainline kernel since 5.6; this ensures the module
  # is loaded at boot rather than on first use.
  boot.kernelModules = [ "wireguard" ];

  environment.systemPackages = with pkgs; [
    wireguard-tools # puts `wg` and `wg-quick` on $PATH directly

    # ── wg-setup — create template env file on a new machine ─────────────────
    (writeShellScriptBin "wg-setup" ''
      set -euo pipefail
      dest="$HOME/.config/wireguard/env"
      if [ -f "$dest" ]; then
        echo "ℹ  $dest already exists — not overwriting."
        echo "   Remove it first if you want a fresh template."
        exit 0
      fi
      mkdir -p "$(dirname "$dest")"
      chmod 700 "$(dirname "$dest")"
      cp ${envTemplate} "$dest"
      chmod 600 "$dest"
      echo "✓  Created $dest"
      echo "   Fill in your values, then run: wg-up"
    '')

    # ── wg-up — bring the WireGuard tunnel up ────────────────────────────────
    # Builds a wg-quick config at $XDG_RUNTIME_DIR/wg0.conf (tmpfs — gone on
    # reboot, readable only by dom) and calls wg-quick with it.  The interface
    # is named 'wg0' because wg-quick derives the name from the filename stem.
    (writeShellScriptBin "wg-up" ''
      set -euo pipefail
      ${loadEnv}

      if ${pkgs.iproute2}/bin/ip link show wg0 >/dev/null 2>&1; then
        echo "ℹ  wg0 is already up."
        exit 0
      fi

      # Write config to user-owned tmpfs — private key never touches persistent disk.
      _cfgfile="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wg0.conf"
      chmod 600 "$_cfgfile" 2>/dev/null || true

      {
        printf '[Interface]\n'
        printf 'PrivateKey = %s\n' "$WG_PRIVATE_KEY"
        printf 'Address = %s\n'    "$WG_CLIENT_IP"
        if [ -n "''${WG_DNS:-}" ]; then
          printf 'DNS = %s\n' "$WG_DNS"
        fi
        printf '\n'
        printf '[Peer]\n'
        printf 'PublicKey = %s\n'          "$WG_SERVER_PUBKEY"
        printf 'Endpoint = %s\n'           "$WG_ENDPOINT"
        printf 'AllowedIPs = %s\n'         "$WG_ALLOWED_IPS"
        printf 'PersistentKeepalive = 25\n'
        if [ -n "''${WG_PRESHARED_KEY:-}" ]; then
          printf 'PresharedKey = %s\n' "$WG_PRESHARED_KEY"
        fi
      } > "$_cfgfile"
      chmod 600 "$_cfgfile"

      echo "↑  Bringing up WireGuard (wg0)..."
      sudo ${pkgs.wireguard-tools}/bin/wg-quick up "$_cfgfile"
      echo "✓  wg0 up — $(${pkgs.iproute2}/bin/ip -4 addr show wg0 | awk '/inet /{print $2}')"
    '')

    # ── wg-down — tear the tunnel down ───────────────────────────────────────
    (writeShellScriptBin "wg-down" ''
      set -euo pipefail

      if ! ${pkgs.iproute2}/bin/ip link show wg0 >/dev/null 2>&1; then
        echo "ℹ  wg0 is not up."
        exit 0
      fi

      _cfgfile="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wg0.conf"
      if [ -f "$_cfgfile" ]; then
        echo "↓  Bringing down WireGuard (wg0)..."
        sudo ${pkgs.wireguard-tools}/bin/wg-quick down "$_cfgfile"
      else
        # Config file gone (e.g. after reboot with interface still listed) —
        # fall back to removing the link directly.
        echo "↓  Config file not found, removing wg0 interface directly..."
        sudo ${pkgs.iproute2}/bin/ip link delete wg0
      fi
      echo "✓  wg0 down"
    '')

    # ── wg-toggle — flip the tunnel on/off ───────────────────────────────────
    (writeShellScriptBin "wg-toggle" ''
      set -euo pipefail
      if ${pkgs.iproute2}/bin/ip link show wg0 >/dev/null 2>&1; then
        wg-down
      else
        wg-up
      fi
    '')

    # ── wg-status — show tunnel state at a glance ────────────────────────────
    (writeShellScriptBin "wg-status" ''
      set -euo pipefail

      echo "=== WireGuard interface ==="
      if ${pkgs.iproute2}/bin/ip link show wg0 >/dev/null 2>&1; then
        sudo ${pkgs.wireguard-tools}/bin/wg show wg0
        echo ""
        echo "=== Routes via wg0 ==="
        ${pkgs.iproute2}/bin/ip route show dev wg0 2>/dev/null || echo "  (none)"
        echo ""
        echo "● wg0: UP"
      else
        echo "  (wg0 interface not present)"
        echo ""
        echo "○ wg0: down"
      fi
    '')
  ];

  # ── Auto-start at boot ────────────────────────────────────────────────────
  # Reads the same env file as wg-up so no extra config is needed.
  # The service is silently skipped when the env file doesn't exist yet
  # (i.e. on a fresh machine before `wg-setup` has been run).
  systemd.services.wireguard-wg0 = {
    description = "WireGuard VPN (wg0)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    unitConfig.ConditionPathExists = "/home/dom/.config/wireguard/env";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;

      ExecStart = pkgs.writeShellScript "wg0-start" ''
        set -euo pipefail
        . /home/dom/.config/wireguard/env
        : "''${WG_PRIVATE_KEY:?WG_PRIVATE_KEY not set}"
        : "''${WG_SERVER_PUBKEY:?WG_SERVER_PUBKEY not set}"
        : "''${WG_ENDPOINT:?WG_ENDPOINT not set}"
        : "''${WG_CLIENT_IP:?WG_CLIENT_IP not set}"
        : "''${WG_ALLOWED_IPS:?WG_ALLOWED_IPS not set}"

        mkdir -p /run/wireguard
        chmod 700 /run/wireguard
        cfgfile=/run/wireguard/wg0.conf

        {
          printf '[Interface]\n'
          printf 'PrivateKey = %s\n' "$WG_PRIVATE_KEY"
          printf 'Address = %s\n'   "$WG_CLIENT_IP"
          if [ -n "''${WG_DNS:-}" ]; then
            printf 'DNS = %s\n' "$WG_DNS"
          fi
          printf '\n'
          printf '[Peer]\n'
          printf 'PublicKey = %s\n'          "$WG_SERVER_PUBKEY"
          printf 'Endpoint = %s\n'           "$WG_ENDPOINT"
          printf 'AllowedIPs = %s\n'         "$WG_ALLOWED_IPS"
          printf 'PersistentKeepalive = 25\n'
          if [ -n "''${WG_PRESHARED_KEY:-}" ]; then
            printf 'PresharedKey = %s\n' "$WG_PRESHARED_KEY"
          fi
        } > "$cfgfile"
        chmod 600 "$cfgfile"

        ${pkgs.wireguard-tools}/bin/wg-quick up "$cfgfile"
      '';

      ExecStop = pkgs.writeShellScript "wg0-stop" ''
        cfgfile=/run/wireguard/wg0.conf
        if [ -f "$cfgfile" ]; then
          ${pkgs.wireguard-tools}/bin/wg-quick down "$cfgfile"
        else
          ${pkgs.iproute2}/bin/ip link delete wg0 2>/dev/null || true
        fi
      '';
    };
  };

  # Allow dom to run wg-quick and wg (for wg show) without a password prompt.
  security.sudo.extraRules = [
    {
      users = [ "dom" ];
      commands = [
        {
          command = "${pkgs.wireguard-tools}/bin/wg-quick";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.wireguard-tools}/bin/wg";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.iproute2}/bin/ip";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}

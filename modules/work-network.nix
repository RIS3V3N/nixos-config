{
  config,
  pkgs,
  lib,
  ...
}:

let
  # ── Runtime env file ──────────────────────────────────────────────────────
  # All site-specific values (network ID, gateway IP, subnets, DNS servers)
  # live in ~/.config/work-network/env so they never end up in the repo.
  # Run 'work-setup' to create a commented template, then fill it in.

  # Template stored in the Nix store; work-setup copies it into place.
  envTemplate = pkgs.writeText "work-network-env-template" ''
    # Work network configuration — NOT committed to git.
    # Fill in your values, then run: work-up
    #
    # 16-char ZeroTier network ID (top of your network page at my.zerotier.com)
    ZT_NETWORK_ID=""

    # ZeroTier-assigned IP of the office gateway server (its zt* address,
    # NOT the physical LAN IP — e.g. 10.147.x.x or 172.28.x.x)
    OFFICE_GATEWAY_ZT_IP=""

    # Space-separated office LAN subnets to route through the gateway.
    # Narrow to what you actually use.
    OFFICE_SUBNETS="10.0.0.0/8 192.168.0.0/16"

    # Space-separated internal DNS server IPs
    OFFICE_DNS_SERVERS=""

    # Space-separated DNS routing domains.
    # ~ prefix = routing-only (these use office DNS; all other queries use public DNS).
    # Use "~." to send ALL DNS through office.
    OFFICE_DNS_DOMAINS="~company.local"
  '';

  # Preamble sourced at the top of every work-* script.
  # Loads the env file and validates all required variables are set.
  loadEnv = ''
    _wnenv="$HOME/.config/work-network/env"
    if [ ! -f "$_wnenv" ]; then
      echo "✗  Work network config not found: $_wnenv" >&2
      echo "   Run 'work-setup' to create a template." >&2
      exit 1
    fi
    # shellcheck source=/dev/null
    . "$_wnenv"
    : "''${ZT_NETWORK_ID:?ZT_NETWORK_ID not set in work-network env file}"
    : "''${OFFICE_GATEWAY_ZT_IP:?OFFICE_GATEWAY_ZT_IP not set in work-network env file}"
    : "''${OFFICE_SUBNETS:?OFFICE_SUBNETS not set in work-network env file}"
    : "''${OFFICE_DNS_SERVERS:?OFFICE_DNS_SERVERS not set in work-network env file}"
    : "''${OFFICE_DNS_DOMAINS:?OFFICE_DNS_DOMAINS not set in work-network env file}"
    unset _wnenv
  '';

in
{
  # ── ZeroTier daemon ────────────────────────────────────────────────────────
  # Starts at boot.  The network ID is NOT declared here to keep it out of the
  # repo.  After the first rebuild, join once manually:
  #   sudo zerotier-cli join <ZT_NETWORK_ID>   ← use the ID from your env file
  # ZeroTier persists joined networks in /var/lib/zerotier-one/ and re-joins
  # them automatically on every restart — no rebuild needed.
  services.zerotierone.enable = true;

  # ── systemd-resolved ───────────────────────────────────────────────────────
  # Required for per-interface DNS routing (what work-up/down use via resolvectl).
  # NM still discovers DNS servers from DHCP as usual; resolved routes them.
  services.resolved = {
    enable = true;
    dnssec = "false"; # most corporate DNS doesn't sign zones
    llmnr = "false";
  };

  # Hand DNS management from NetworkManager to systemd-resolved.
  # Existing DHCP-assigned DNS continues to work as before.
  networking.networkmanager.dns = "systemd-resolved";

  # ── Toggle commands ────────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [

    # ── work-setup — create template env file on a new machine ────────────────
    (writeShellScriptBin "work-setup" ''
      ENV_FILE="$HOME/.config/work-network/env"
      if [ -f "$ENV_FILE" ]; then
        echo "Already exists: $ENV_FILE"
        echo "Edit it directly, or delete it and rerun work-setup to start fresh."
        exit 0
      fi
      mkdir -p "$(dirname "$ENV_FILE")"
      cp ${envTemplate} "$ENV_FILE"
      chmod 600 "$ENV_FILE"
      echo "Created: $ENV_FILE"
      echo ""
      echo "Next steps:"
      echo "  1. Edit $ENV_FILE with your values"
      echo "  2. sudo zerotier-cli join <ZT_NETWORK_ID>"
      echo "  3. Authorise this machine at https://my.zerotier.com"
      echo "  4. work-up"
    '')

    # ── work-up ───────────────────────────────────────────────────────────────
    (writeShellScriptBin "work-up" ''
      set -euo pipefail
      ${loadEnv}

      # ── 1. Find the ZeroTier interface ─────────────────────────────────────
      ZT_IFACE=$(${pkgs.iproute2}/bin/ip -o link show \
                   | awk -F': ' '{print $2}' | grep '^zt' | head -1 || true)
      if [ -z "$ZT_IFACE" ]; then
        echo "✗  ZeroTier interface not found." >&2
        echo "   Check:  systemctl status zerotierone" >&2
        echo "   First time?  sudo zerotier-cli join $ZT_NETWORK_ID" >&2
        echo "   Then authorise at https://my.zerotier.com" >&2
        exit 1
      fi
      echo "ZeroTier interface : $ZT_IFACE"

      # ── 2. Verify the network is joined and authorised ─────────────────────
      ZT_STATUS=$(sudo ${pkgs.zerotierone}/bin/zerotier-cli listnetworks 2>/dev/null \
                    | awk -v net="$ZT_NETWORK_ID" '$3==net {print $6}' || true)
      if [ "$ZT_STATUS" != "OK" ]; then
        echo "✗  ZeroTier network status: ''${ZT_STATUS:-not found}" >&2
        echo "   Network ID: $ZT_NETWORK_ID" >&2
        echo "   Has this device been authorised at https://my.zerotier.com ?" >&2
        exit 1
      fi
      echo "ZeroTier network   : OK"

      # ── 3. Wait for the office gateway to be reachable ─────────────────────
      echo -n "Office gateway     : "
      for i in $(seq 1 20); do
        if ${pkgs.iputils}/bin/ping -c1 -W1 "$OFFICE_GATEWAY_ZT_IP" &>/dev/null; then
          echo "reachable ($OFFICE_GATEWAY_ZT_IP)"
          break
        fi
        echo -n "."
        sleep 1
        if [ "$i" -eq 20 ]; then
          echo " ✗  unreachable after 20 s" >&2
          echo "   Is the office server online and in the same ZeroTier network?" >&2
          exit 1
        fi
      done

      # ── 4. Add routes for each office subnet ───────────────────────────────
      echo "Routes:"
      for subnet in $OFFICE_SUBNETS; do
        if sudo ${pkgs.iproute2}/bin/ip route replace \
             "$subnet" via "$OFFICE_GATEWAY_ZT_IP" dev "$ZT_IFACE"; then
          echo "  + $subnet  →  $OFFICE_GATEWAY_ZT_IP  ($ZT_IFACE)"
        else
          echo "  ! $subnet  (failed — gateway may not be reachable via $ZT_IFACE)"
        fi
      done

      # ── 5. Configure per-interface DNS on the ZeroTier interface ───────────
      # shellcheck disable=SC2086
      sudo ${pkgs.systemd}/bin/resolvectl dns           "$ZT_IFACE" $OFFICE_DNS_SERVERS
      # shellcheck disable=SC2086
      sudo ${pkgs.systemd}/bin/resolvectl domain        "$ZT_IFACE" $OFFICE_DNS_DOMAINS
      sudo ${pkgs.systemd}/bin/resolvectl default-route "$ZT_IFACE" no
      echo "DNS servers        : $OFFICE_DNS_SERVERS"
      echo "DNS domains        : $OFFICE_DNS_DOMAINS"

      touch "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/work-vpn-active"
      echo ""
      echo "✓  Work network active.  Toggle off with:  work-vpn  (or work-down)"
    '')

    # ── work-down ─────────────────────────────────────────────────────────────
    (writeShellScriptBin "work-down" ''
      set -euo pipefail
      ${loadEnv}

      ZT_IFACE=$(${pkgs.iproute2}/bin/ip -o link show \
                   | awk -F': ' '{print $2}' | grep '^zt' | head -1 || true)

      echo "Removing routes:"
      for subnet in $OFFICE_SUBNETS; do
        if sudo ${pkgs.iproute2}/bin/ip route del "$subnet" 2>/dev/null; then
          echo "  - $subnet"
        else
          echo "  ~ $subnet (not present, skipping)"
        fi
      done

      if [ -n "$ZT_IFACE" ]; then
        sudo ${pkgs.systemd}/bin/resolvectl revert "$ZT_IFACE" 2>/dev/null || true
        echo "DNS                : reverted on $ZT_IFACE"
      fi

      rm -f "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/work-vpn-active"
      echo "✓  Work network disabled."
    '')

    # ── work-vpn — single toggle ──────────────────────────────────────────────
    (writeShellScriptBin "work-vpn" ''
      if [ -f "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/work-vpn-active" ]; then
        exec work-down
      else
        exec work-up
      fi
    '')

    # ── work-status — show everything at a glance ─────────────────────────────
    (writeShellScriptBin "work-status" ''
      ${loadEnv}

      ZT_IFACE=$(${pkgs.iproute2}/bin/ip -o link show \
                   | awk -F': ' '{print $2}' | grep '^zt' | head -1 || true)

      echo "=== ZeroTier ==="
      sudo ${pkgs.zerotierone}/bin/zerotier-cli info 2>/dev/null || echo "(daemon not running)"
      echo ""
      sudo ${pkgs.zerotierone}/bin/zerotier-cli listnetworks 2>/dev/null || true

      echo ""
      echo "=== Active work routes ==="
      found=0
      for subnet in $OFFICE_SUBNETS; do
        route=$(${pkgs.iproute2}/bin/ip route show "$subnet" 2>/dev/null || true)
        if [ -n "$route" ]; then
          echo "  $route"
          found=1
        fi
      done
      [ "$found" -eq 0 ] && echo "  (none)"

      echo ""
      echo "=== DNS on ''${ZT_IFACE:-<no zt iface>} ==="
      if [ -n "$ZT_IFACE" ]; then
        ${pkgs.systemd}/bin/resolvectl status "$ZT_IFACE" 2>/dev/null || true
      else
        echo "  (ZeroTier interface not up)"
      fi

      echo ""
      if [ -f "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/work-vpn-active" ]; then
        echo "● Work VPN: ACTIVE"
      else
        echo "○ Work VPN: inactive"
      fi
    '')
  ];

  # ── Auto-start at boot ────────────────────────────────────────────────────
  # Brings up office routing + DNS after ZeroTier has connected.
  # Silently skipped when the env file doesn't exist yet (fresh machine).
  # On first boot after setup, ZeroTier may need a few seconds to reconnect;
  # Restart=on-failure with a 15 s delay handles transient gateway timeouts.
  systemd.services.work-network = {
    description = "Work office routing and split DNS";
    after = [
      "zerotierone.service"
      "network-online.target"
    ];
    requires = [ "zerotierone.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    unitConfig = {
      ConditionPathExists = "/home/dom/.config/work-network/env";
      # Restart limits must live in [Unit], not [Service].
      # Give up after 5 attempts so we don't loop forever when the
      # office server is unreachable (e.g. working from a plane).
      StartLimitBurst = 5;
      StartLimitIntervalSec = "10min";
    };

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Note: Restart= is not supported for Type=oneshot.
      # If the service fails at boot (e.g. ZeroTier not yet connected),
      # re-run manually with: systemctl start work-network

      ExecStart = pkgs.writeShellScript "work-network-start" ''
        set -euo pipefail
        . /home/dom/.config/work-network/env
        : "''${ZT_NETWORK_ID:?ZT_NETWORK_ID not set}"
        : "''${OFFICE_GATEWAY_ZT_IP:?OFFICE_GATEWAY_ZT_IP not set}"
        : "''${OFFICE_SUBNETS:?OFFICE_SUBNETS not set}"
        : "''${OFFICE_DNS_SERVERS:?OFFICE_DNS_SERVERS not set}"
        : "''${OFFICE_DNS_DOMAINS:?OFFICE_DNS_DOMAINS not set}"

        # ── 1. Wait for the ZeroTier interface to appear ────────────────────
        # zerotierone.service being active doesn't mean the zt* interface
        # exists yet — the daemon needs a moment to create it after start.
        echo -n "ZeroTier interface : "
        ZT_IFACE=""
        for i in $(${pkgs.coreutils}/bin/seq 1 30); do
          ZT_IFACE=$(${pkgs.iproute2}/bin/ip -o link show \
                       | ${pkgs.gawk}/bin/awk -F': ' '{print $2}' | ${pkgs.gnugrep}/bin/grep '^zt' | ${pkgs.coreutils}/bin/head -1 || true)
          if [ -n "$ZT_IFACE" ]; then
            echo "$ZT_IFACE"
            break
          fi
          echo -n "."
          ${pkgs.coreutils}/bin/sleep 1
          if [ "$i" -eq 30 ]; then
            echo " not found after 30 s" >&2
            exit 1
          fi
        done

        # ── 2. Verify the network is joined and authorised ──────────────────
        ZT_STATUS=$(${pkgs.zerotierone}/bin/zerotier-cli listnetworks 2>/dev/null \
                      | ${pkgs.gawk}/bin/awk -v net="$ZT_NETWORK_ID" '$3==net {print $6}' || true)
        if [ "$ZT_STATUS" != "OK" ]; then
          echo "ZeroTier network status: ''${ZT_STATUS:-not found}" >&2
          echo "Has this device been authorised at https://my.zerotier.com ?" >&2
          exit 1
        fi
        echo "ZeroTier network   : OK"

        # ── 3. Wait for the office gateway to be reachable ──────────────────
        echo -n "Office gateway     : "
        for i in $(${pkgs.coreutils}/bin/seq 1 30); do
          if ${pkgs.iputils}/bin/ping -c1 -W1 "$OFFICE_GATEWAY_ZT_IP" &>/dev/null; then
            echo "reachable ($OFFICE_GATEWAY_ZT_IP)"
            break
          fi
          echo -n "."
          ${pkgs.coreutils}/bin/sleep 1
          if [ "$i" -eq 30 ]; then
            echo " unreachable after 30 s" >&2
            exit 1
          fi
        done

        # ── 4. Add routes for each office subnet ────────────────────────────
        echo "Routes:"
        for subnet in $OFFICE_SUBNETS; do
          if ${pkgs.iproute2}/bin/ip route replace \
               "$subnet" via "$OFFICE_GATEWAY_ZT_IP" dev "$ZT_IFACE"; then
            echo "  + $subnet  →  $OFFICE_GATEWAY_ZT_IP  ($ZT_IFACE)"
          else
            echo "  ! $subnet  (failed)" >&2
          fi
        done

        # ── 5. Configure per-interface DNS ──────────────────────────────────
        # shellcheck disable=SC2086
        ${pkgs.systemd}/bin/resolvectl dns           "$ZT_IFACE" $OFFICE_DNS_SERVERS
        # shellcheck disable=SC2086
        ${pkgs.systemd}/bin/resolvectl domain        "$ZT_IFACE" $OFFICE_DNS_DOMAINS
        ${pkgs.systemd}/bin/resolvectl default-route "$ZT_IFACE" no
        echo "DNS servers        : $OFFICE_DNS_SERVERS"
        echo "DNS domains        : $OFFICE_DNS_DOMAINS"
        echo "✓  Work network active"
      '';

      ExecStop = pkgs.writeShellScript "work-network-stop" ''
        . /home/dom/.config/work-network/env 2>/dev/null || true
        ZT_IFACE=$(${pkgs.iproute2}/bin/ip -o link show \
                     | ${pkgs.gawk}/bin/awk -F': ' '{print $2}' | ${pkgs.gnugrep}/bin/grep '^zt' | ${pkgs.coreutils}/bin/head -1 || true)
        for subnet in ''${OFFICE_SUBNETS:-}; do
          ${pkgs.iproute2}/bin/ip route del "$subnet" 2>/dev/null || true
        done
        if [ -n "$ZT_IFACE" ]; then
          ${pkgs.systemd}/bin/resolvectl revert "$ZT_IFACE" 2>/dev/null || true
        fi
        echo "✓  Work network disabled"
      '';
    };
  };

  # Allow dom to run the specific binaries needed by work-up/down/status
  # without a password prompt.  Scoped to exact Nix store paths.
  security.sudo.extraRules = [
    {
      users = [ "dom" ];
      commands = [
        {
          command = "${pkgs.iproute2}/bin/ip";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.systemd}/bin/resolvectl";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.zerotierone}/bin/zerotier-cli";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}

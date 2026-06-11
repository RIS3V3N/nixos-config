#!/usr/bin/env bash
# work-network.sh — portable ZeroTier office routing + split DNS
#
# Works on:
#   Linux  with systemd-resolved (Ubuntu 20.04+, Fedora 33+, Arch, …)
#   macOS  12+ (Monterey and later)
#
# Reads the same env file as the NixOS module: ~/.config/work-network/env
# Share this script with co-workers who don't run NixOS.
#
# USAGE
#   work-network.sh setup    # create env file template (once per machine)
#   work-network.sh up       # enable routing + split DNS
#   work-network.sh down     # disable routing + split DNS
#   work-network.sh status   # show current state
#   work-network.sh toggle   # flip between up and down
#
# OPTIONAL: symlink so the commands match the NixOS versions:
#   chmod +x work-network.sh
#   ln -s "$PWD/work-network.sh" ~/.local/bin/work-up
#   ln -s "$PWD/work-network.sh" ~/.local/bin/work-down
#   ln -s "$PWD/work-network.sh" ~/.local/bin/work-status
#   ln -s "$PWD/work-network.sh" ~/.local/bin/work-vpn

set -euo pipefail

ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/work-network/env"
# User-writable temp dir — no sudo needed for the state flag
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/work-vpn-active-$(id -u)"
OS="$(uname -s)"   # Linux | Darwin

# ── helpers ───────────────────────────────────────────────────────────────

die() { printf '\n✗  %s\n' "$*" >&2; exit 1; }

load_env() {
  [ -f "$ENV_FILE" ] \
    || die "Config not found: $ENV_FILE\n   Run:  $(basename "$0") setup"
  # shellcheck source=/dev/null
  . "$ENV_FILE"
  : "${ZT_NETWORK_ID:?ZT_NETWORK_ID not set in $ENV_FILE}"
  : "${OFFICE_GATEWAY_ZT_IP:?OFFICE_GATEWAY_ZT_IP not set in $ENV_FILE}"
  : "${OFFICE_SUBNETS:?OFFICE_SUBNETS not set in $ENV_FILE}"
  : "${OFFICE_DNS_SERVERS:?OFFICE_DNS_SERVERS not set in $ENV_FILE}"
  : "${OFFICE_DNS_DOMAINS:?OFFICE_DNS_DOMAINS not set in $ENV_FILE}"
}

zt_iface() {
  if [ "$OS" = "Darwin" ]; then
    # macOS ZeroTier uses feth* interfaces (fake ethernet), not zt*
    ifconfig 2>/dev/null | awk -F: '/^(zt|feth)[^ ]/{print $1; exit}'
  else
    ip -o link show 2>/dev/null \
      | awk -F': ' '{print $2}' | grep '^zt' | head -1 || true
  fi
}

# Adds a /32 host route for the ZT gateway so it isn't swallowed by the
# broad subnet route we add next.  Called once in cmd_up on macOS.
_protect_gateway_macos() {   # gw iface
  local gw="$1" iface="$2"
  sudo route -q -n add -host "$gw" -interface "$iface" 2>/dev/null || true
}

add_route() {   # subnet gateway iface
  local subnet="$1" gw="$2" iface="$3"
  if [ "$OS" = "Darwin" ]; then
    sudo route -q -n add -net "$subnet" "$gw" 2>/dev/null \
      && echo "  + $subnet  →  $gw" \
      || echo "  ~ $subnet  (already present)"
  else
    sudo ip route replace "$subnet" via "$gw" dev "$iface" \
      && echo "  + $subnet  →  $gw  ($iface)" \
      || echo "  ! $subnet  (failed)"
  fi
}

del_route() {   # subnet
  local subnet="$1"
  if [ "$OS" = "Darwin" ]; then
    sudo route -q delete -net "$subnet" 2>/dev/null \
      && echo "  - $subnet" \
      || echo "  ~ $subnet  (not present, skipping)"
    # Also remove the gateway host route if this was the last subnet
    # (harmless if already gone)
    sudo route -q delete -host "$OFFICE_GATEWAY_ZT_IP" 2>/dev/null || true
  else
    sudo ip route del "$subnet" 2>/dev/null \
      && echo "  - $subnet" \
      || echo "  ~ $subnet  (not present, skipping)"
  fi
}

set_dns() {     # iface servers domains
  local iface="$1" servers="$2" domains="$3"
  if [ "$OS" = "Darwin" ]; then
    # macOS split DNS: one /etc/resolver/<domain> file per search domain.
    # Strip the leading ~ that resolvectl uses as a "routing-only" marker.
    sudo mkdir -p /etc/resolver
    for domain in $domains; do
      local d="${domain#\~}"
      [ "$d" = "." ] && d="__catch-all__"
      {
        for s in $servers; do printf 'nameserver %s\n' "$s"; done
        echo "search_order 1"
      } | sudo tee "/etc/resolver/$d" > /dev/null
      echo "  DNS: $d  →  $servers"
    done
  else
    # Linux: systemd-resolved via resolvectl
    if command -v resolvectl &>/dev/null \
        && systemctl is-active systemd-resolved &>/dev/null; then
      # Word-splitting is intentional: space-separated lists
      # shellcheck disable=SC2086
      sudo resolvectl dns           "$iface" $servers
      # shellcheck disable=SC2086
      sudo resolvectl domain        "$iface" $domains
      sudo resolvectl default-route "$iface" no
      echo "  DNS servers : $servers"
      echo "  DNS domains : $domains"
    else
      printf '  ⚠  systemd-resolved not active — routes added but DNS skipped.\n' >&2
      printf '     Set nameservers manually: %s\n' "$servers" >&2
    fi
  fi
}

revert_dns() {  # iface domains
  local iface="$1" domains="$2"
  if [ "$OS" = "Darwin" ]; then
    for domain in $domains; do
      local d="${domain#\~}"
      [ "$d" = "." ] && d="__catch-all__"
      sudo rm -f "/etc/resolver/$d"
    done
    echo "DNS  : resolver files removed"
  else
    if command -v resolvectl &>/dev/null; then
      sudo resolvectl revert "$iface" 2>/dev/null || true
      echo "DNS  : reverted on $iface"
    fi
  fi
}

# ── commands ──────────────────────────────────────────────────────────────

cmd_setup() {
  if [ -f "$ENV_FILE" ]; then
    echo "Already exists: $ENV_FILE"
    echo "Edit it directly, or delete it and rerun to reset."
    exit 0
  fi
  mkdir -p "$(dirname "$ENV_FILE")"
  cat > "$ENV_FILE" << 'TEMPLATE'
# Work network configuration — NOT committed to git.
# Fill in your values, then run:  work-network.sh up

# 16-char ZeroTier network ID (top of your network page at my.zerotier.com)
ZT_NETWORK_ID=""

# ZeroTier-assigned IP of the office gateway server (its zt* address,
# NOT the physical LAN IP — e.g. 10.147.x.x or 172.28.x.x)
OFFICE_GATEWAY_ZT_IP=""

# Space-separated office LAN subnets to route through the gateway.
# Narrow to only what you actually need.
OFFICE_SUBNETS="10.0.0.0/8 192.168.0.0/16"

# Space-separated internal DNS server IPs
OFFICE_DNS_SERVERS=""

# Space-separated DNS routing domains.
# ~ prefix = routing-only (only these go to office DNS; public DNS handles the rest).
# Use "~." to send ALL DNS through office.
OFFICE_DNS_DOMAINS="~company.local"
TEMPLATE
  chmod 600 "$ENV_FILE"
  echo "Created: $ENV_FILE"
  echo ""
  echo "Next steps:"
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "  1. Fill in $ENV_FILE"
    echo "  2. Install ZeroTier: https://www.zerotier.com/download/"
  else
    echo "  1. Fill in $ENV_FILE"
    echo "  2. Install ZeroTier: curl -s https://install.zerotier.com | sudo bash"
  fi
  echo "  3. sudo zerotier-cli join <ZT_NETWORK_ID>"
  echo "  4. Authorise this machine at https://my.zerotier.com → Members"
  echo "  5. $(basename "$0") up"
}

cmd_up() {
  load_env

  # 1. Find ZeroTier interface
  ZT_IFACE="$(zt_iface)"
  if [ -z "$ZT_IFACE" ]; then
    die "ZeroTier interface not found.\n   Is zerotierone running?\n   First time? sudo zerotier-cli join $ZT_NETWORK_ID\n   Then authorise at https://my.zerotier.com"
  fi
  echo "ZeroTier interface : $ZT_IFACE"

  # 2. Verify network is joined and authorised
  ZT_STATUS="$(zerotier-cli listnetworks 2>/dev/null \
    | awk -v net="$ZT_NETWORK_ID" '$3==net {print $6}' || true)"
  [ "$ZT_STATUS" = "OK" ] \
    || die "ZeroTier network status: ${ZT_STATUS:-not found}\n   Authorise this machine at https://my.zerotier.com"
  echo "ZeroTier network   : OK"

  # 3. Wait for the gateway to be reachable
  echo -n "Office gateway     : "
  for i in $(seq 1 20); do
    if ping -c1 -W1 "$OFFICE_GATEWAY_ZT_IP" &>/dev/null 2>&1; then
      echo "reachable ($OFFICE_GATEWAY_ZT_IP)"; break
    fi
    echo -n "."; sleep 1
    [ "$i" -lt 20 ] || die "unreachable after 20 s\n   Is the office gateway online?"
  done

  # 4. Add routes
  # On macOS, pin a /32 host route for the gateway first so the broad subnet
  # routes we're about to add don't swallow the gateway itself (routing loop).
  [ "$OS" = "Darwin" ] && _protect_gateway_macos "$OFFICE_GATEWAY_ZT_IP" "$ZT_IFACE"
  echo "Routes:"
  for subnet in $OFFICE_SUBNETS; do
    add_route "$subnet" "$OFFICE_GATEWAY_ZT_IP" "$ZT_IFACE"
  done

  # 5. Configure DNS
  set_dns "$ZT_IFACE" "$OFFICE_DNS_SERVERS" "$OFFICE_DNS_DOMAINS"

  touch "$STATE_FILE"
  echo ""
  echo "✓  Work network active.  Disable with:  $(basename "$0") down"
}

cmd_down() {
  load_env

  ZT_IFACE="$(zt_iface)"

  echo "Removing routes:"
  for subnet in $OFFICE_SUBNETS; do
    del_route "$subnet"
  done

  [ -n "$ZT_IFACE" ] && revert_dns "$ZT_IFACE" "$OFFICE_DNS_DOMAINS"

  rm -f "$STATE_FILE"
  echo "✓  Work network disabled."
}

cmd_status() {
  load_env

  ZT_IFACE="$(zt_iface)"

  echo "=== ZeroTier ==="
  zerotier-cli info 2>/dev/null || echo "(daemon not running)"
  echo ""
  zerotier-cli listnetworks 2>/dev/null || true

  echo ""
  echo "=== Active work routes ==="
  found=0
  for subnet in $OFFICE_SUBNETS; do
    if [ "$OS" = "Darwin" ]; then
      route="$(netstat -rn 2>/dev/null | awk -v s="${subnet%%/*}" '$1==s{print; exit}' || true)"
    else
      route="$(ip route show "$subnet" 2>/dev/null || true)"
    fi
    if [ -n "$route" ]; then echo "  $route"; found=1; fi
  done
  [ "$found" -eq 1 ] || echo "  (none)"

  echo ""
  echo "=== DNS ==="
  if [ "$OS" = "Darwin" ]; then
    found_resolver=0
    for f in /etc/resolver/*; do
      [ -f "$f" ] && { echo "  $(basename "$f")"; found_resolver=1; }
    done
    [ "$found_resolver" -eq 1 ] || echo "  (no resolver files)"
  elif [ -n "$ZT_IFACE" ] && command -v resolvectl &>/dev/null; then
    resolvectl status "$ZT_IFACE" 2>/dev/null || true
  else
    echo "  (resolvectl not available)"
  fi

  echo ""
  if [ -f "$STATE_FILE" ]; then
    echo "● Work VPN: ACTIVE"
  else
    echo "○ Work VPN: inactive"
  fi
}

# ── dispatch ──────────────────────────────────────────────────────────────
# Accept command as first argument, or infer from symlink name.

CMD="${1:-}"
[ -z "$CMD" ] && CMD="$(basename "$0")"

case "$CMD" in
  setup)                          cmd_setup  ;;
  up    | work-up)                cmd_up     ;;
  down  | work-down)              cmd_down   ;;
  status| work-status)            cmd_status ;;
  toggle| work-vpn)
    [ -f "$STATE_FILE" ] && cmd_down || cmd_up ;;
  *)
    cat >&2 << EOF
Usage: $(basename "$0") {setup|up|down|status|toggle}

  setup    Create ~/.config/work-network/env template (run once)
  up       Add office routes + configure split DNS
  down     Remove office routes + revert DNS
  status   Show ZeroTier status, active routes, and DNS state
  toggle   Switch between up and down

Symlink for work-* style invocation:
  ln -s \$PWD/work-network.sh ~/.local/bin/work-up
  ln -s \$PWD/work-network.sh ~/.local/bin/work-down
  ln -s \$PWD/work-network.sh ~/.local/bin/work-status
  ln -s \$PWD/work-network.sh ~/.local/bin/work-vpn
EOF
    exit 1 ;;
esac

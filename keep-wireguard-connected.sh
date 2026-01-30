#!/usr/bin/env bash
set -euo pipefail

# ---- config (defaults; overridable via /etc/keep-wireguard-connected.conf) ----
CONF_FILE="/etc/keep-wireguard-connected.conf"

# Set defaults FIRST (so set -u won't explode if config omits a var)
WG_IFACE_DEFAULT="va3"
EXPECTED_EGRESS_IP_DEFAULT="51.81.16.137"
VPN_PING_TARGET_DEFAULT="10.0.0.1"

TOTAL_WAIT_SEC_DEFAULT=90
SLEEP_STEP_SEC_DEFAULT=5

# Default IP echo endpoints
IP_ECHO_URLS_DEFAULT=(
  "https://canhazip.com"
  "https://api.ipify.org"
  "https://ifconfig.me/ip"
  "https://icanhazip.com"
)

# Default reboot cmd
REBOOT_CMD_DEFAULT=(/sbin/reboot -f)

# Load config overrides (optional)
if [[ -f "$CONF_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONF_FILE"
fi

# Apply defaults if variables were not set by config/env
WG_IFACE="${WG_IFACE:-$WG_IFACE_DEFAULT}"
WG_SERVICE="wg-quick@${WG_IFACE}.service"

EXPECTED_EGRESS_IP="${EXPECTED_EGRESS_IP:-$EXPECTED_EGRESS_IP_DEFAULT}"
VPN_PING_TARGET="${VPN_PING_TARGET:-$VPN_PING_TARGET_DEFAULT}"

TOTAL_WAIT_SEC="${TOTAL_WAIT_SEC:-$TOTAL_WAIT_SEC_DEFAULT}"
SLEEP_STEP_SEC="${SLEEP_STEP_SEC:-$SLEEP_STEP_SEC_DEFAULT}"

# Allow config to override endpoints by defining IP_ECHO_URLS as an array
# If not defined, use defaults.
if ! declare -p IP_ECHO_URLS >/dev/null 2>&1; then
  IP_ECHO_URLS=("${IP_ECHO_URLS_DEFAULT[@]}")
fi

# Allow config to override reboot command by defining REBOOT_CMD as an array
if ! declare -p REBOOT_CMD >/dev/null 2>&1; then
  REBOOT_CMD=("${REBOOT_CMD_DEFAULT[@]}")
fi


# ---- helpers ----
log() { echo "[$(date -Is)] $*"; }

get_external_ip() {
  local url ip
  for url in "${IP_ECHO_URLS[@]}"; do
    ip="$(curl -fsS --max-time 6 "$url" | tr -d '[:space:]' || true)"
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

vpn_ping_ok() {
  [[ -z "${VPN_PING_TARGET}" ]] && return 0
  ping -c 1 -W 2 "${VPN_PING_TARGET}" >/dev/null 2>&1
}

wg_handshake_ok() {
  # Checks if there's at least one peer with a recent handshake
  # (wg show gives unix timestamps; 0 means never)
  local ts now
  now="$(date +%s)"
  while read -r ts; do
    [[ "$ts" == "0" ]] && continue
    # consider handshake "fresh" if within last 120s
    if (( now - ts <= 120 )); then
      return 0
    fi
  done < <(wg show "${WG_IFACE}" latest-handshakes 2>/dev/null | awk '{print $2}' || true)

  return 1
}

egress_ok() {
  # Primary: expected public egress IP
  if [[ -n "${EXPECTED_EGRESS_IP}" ]]; then
    local ip
    ip="$(get_external_ip || true)"
    [[ -z "$ip" ]] && return 2
    [[ "$ip" == "${EXPECTED_EGRESS_IP}" ]]
    return $?
  fi

  # Secondary: VPN-only ping + handshake
  vpn_ping_ok && wg_handshake_ok
}

restart_wg() {
  log "Restarting ${WG_SERVICE} ..."
  systemctl restart "${WG_SERVICE}"
}

main() {
  # Quick sanity: is wg binary present?
  command -v wg >/dev/null 2>&1 || { log "ERROR: wg not found"; exit 2; }

  if egress_ok; then
    log "OK: WireGuard egress appears correct."
    exit 0
  fi

  log "WARN: WireGuard egress NOT correct. Attempting restart."
  restart_wg || log "WARN: systemctl restart returned non-zero"

  local waited=0
  while (( waited < TOTAL_WAIT_SEC )); do
    sleep "${SLEEP_STEP_SEC}"
    waited=$(( waited + SLEEP_STEP_SEC ))

    if egress_ok; then
      log "RECOVERED: WireGuard egress correct after ${waited}s."
      exit 0
    fi

    log "Still not correct after ${waited}s..."
  done

  log "FAIL: WireGuard did not recover within ${TOTAL_WAIT_SEC}s. Forcing reboot."
  "${REBOOT_CMD[@]}"
}

main "$@"

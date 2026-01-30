#!/usr/bin/env bash
set -euo pipefail

# ---- config ----
WG_IFACE="va3"                          # wg interface name (wg0, va3, etc)
WG_SERVICE="wg-quick@${WG_IFACE}.service"

# The "good" external IP *when tunneled* (recommended)
# Put the public IP you see when traffic egresses via your IPFire/WG exit.
EXPECTED_EGRESS_IP="51.81.16.137"

# If you can't rely on a single fixed egress IP, set EXPECTED_EGRESS_IP=""
# and instead set a VPN-only reachable check target below.
# EXPECTED_EGRESS_IP=""

# Optional: a known internal/VPN-only IP to ping (e.g. IPFire WG peer address)
VPN_PING_TARGET="10.0.0.1"              # set "" to disable

# External IP check endpoints (multiple for resilience)
IP_ECHO_URLS=(
  "https://canhazip.com"
  "https://api.ipify.org"
  "https://ifconfig.me/ip"
  "https://icanhazip.com"
)

# How long to wait after restart for WG to become "correct"
TOTAL_WAIT_SEC=90
SLEEP_STEP_SEC=5

# Reboot behavior
REBOOT_CMD=(/sbin/reboot -f)            # forceful reboot
# Alternative escalation (comment in if you want)
# REBOOT_CMD=(/bin/bash -lc 'echo b > /proc/sysrq-trigger')

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

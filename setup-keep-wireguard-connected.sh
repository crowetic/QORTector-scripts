#!/usr/bin/env bash
set -euo pipefail

REPO_RAW_URL_DEFAULT="https://gitea.qortal.link/crowetic/QORTector-scripts/raw/branch/main/keep-wireguard-connected.sh"

INSTALL_PATH="/usr/local/sbin/keep-wireguard-connected.sh"
CONF_PATH="/etc/keep-wireguard-connected.conf"

SERVICE_NAME="keep-wireguard-connected"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
TIMER_PATH="/etc/systemd/system/${SERVICE_NAME}.timer"

# Timer cadence defaults
ONBOOT_SEC="45s"
INTERVAL_SEC="30s"
ACCURACY_SEC="5s"

log()  { echo -e "\033[1;32m[+]\033[0m $*"; }
warn() { echo -e "\033[1;33m[!]\033[0m $*" >&2; }
die()  { echo -e "\033[1;31m[x]\033[0m $*" >&2; exit 1; }

need_root() { [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root: sudo $0"; }
have_cmd()  { command -v "$1" >/dev/null 2>&1; }

need_root

REPO_RAW_URL="${REPO_RAW_URL:-$REPO_RAW_URL_DEFAULT}"

log "Installing keep-wireguard-connected..."

# 1) Install script (prefer local file in current directory)
if [[ -f "./keep-wireguard-connected.sh" ]]; then
  log "Using local ./keep-wireguard-connected.sh"
  install -m 0750 -o root -g root "./keep-wireguard-connected.sh" "$INSTALL_PATH"
else
  have_cmd curl || die "curl missing (or run installer from same dir as keep-wireguard-connected.sh)"
  log "Downloading: $REPO_RAW_URL"
  tmp="$(mktemp)"
  curl -fsSL --max-time 25 "$REPO_RAW_URL" -o "$tmp" || die "Download failed"
  install -m 0750 -o root -g root "$tmp" "$INSTALL_PATH"
  rm -f "$tmp"
fi

bash -n "$INSTALL_PATH" || die "Installed script has syntax errors: $INSTALL_PATH"

# 2) Create config file if missing
if [[ ! -f "$CONF_PATH" ]]; then
  log "Creating config: $CONF_PATH"
  cat > "$CONF_PATH" <<'EOF'
# /etc/keep-wireguard-connected.conf
# Optional overrides for keep-wireguard-connected.sh
#
# NOTE: Your script must source this file (recommended patch).
# If you haven't patched the script yet, do that first.

WG_IFACE="va3"
EXPECTED_EGRESS_IP="51.81.16.137"
VPN_PING_TARGET="10.0.0.1"

TOTAL_WAIT_SEC=90
SLEEP_STEP_SEC=5

IP_ECHO_URLS=(
  "https://canhazip.com"
  "https://api.ipify.org"
  "https://ifconfig.me/ip"
  "https://icanhazip.com"
)

REBOOT_CMD=(/sbin/reboot -f)
EOF
  chmod 0640 "$CONF_PATH"
  chown root:root "$CONF_PATH"
else
  warn "Config already exists, leaving unchanged: $CONF_PATH"
fi

# 3) systemd service
log "Writing systemd service: $SERVICE_PATH"
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Keep WireGuard connected (egress watchdog)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=-$CONF_PATH
ExecStart=$INSTALL_PATH
EOF

# 4) systemd timer
log "Writing systemd timer: $TIMER_PATH"
cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Run keep-wireguard-connected periodically

[Timer]
OnBootSec=$ONBOOT_SEC
OnUnitActiveSec=$INTERVAL_SEC
AccuracySec=$ACCURACY_SEC
Persistent=true

[Install]
WantedBy=timers.target
EOF

log "Reloading systemd"
systemctl daemon-reload

log "Enabling + starting timer"
systemctl enable --now "${SERVICE_NAME}.timer"

log "Installed."
echo
log "Commands:"
echo "  Edit config:   sudo nano $CONF_PATH"
echo "  Test run:      sudo $INSTALL_PATH"
echo "  Timer status:  systemctl status ${SERVICE_NAME}.timer --no-pager"
echo "  Logs:          journalctl -u ${SERVICE_NAME}.service -n 200 --no-pager"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="setup-vm-data-maintenance"

# -------- defaults --------
REPO_BASE="${REPO_BASE:-https://gitea.qortal.link/crowetic/QORTector-scripts}"
BRANCH="${BRANCH:-main}"
RAW_BASE="${RAW_BASE:-$REPO_BASE/raw/branch/$BRANCH}"

REMOTE_SCRIPT="vm-data-maintenance.sh"
REMOTE_CONF="vm-data-maintenance.conf"

BIN_PATH="/usr/local/sbin/vm-data-maintenance"
CONF_PATH="/etc/vm-data-maintenance.conf"
SERVICE_PATH="/etc/systemd/system/vm-data-maintenance.service"
TIMER_PATH="/etc/systemd/system/vm-data-maintenance.timer"

FORCE=0
UNINSTALL=0

log() { echo "[$(date -Is)] $SCRIPT_NAME: $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run as root (sudo)."
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

fetch() {
  local url="$1" out="$2"
  if have_cmd curl; then
    curl -fsSL "$url" -o "$out"
  elif have_cmd wget; then
    wget -qO "$out" "$url"
  else
    die "Need curl or wget"
  fi
}

usage() {
cat <<EOF
$SCRIPT_NAME [options]

Options:
  --force        Overwrite existing config and script
  --uninstall    Remove service, timer, and script
  -h, --help     Show help

Env overrides:
  REPO_BASE, BRANCH
EOF
}

# -------- parse args --------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

need_root

# -------- UNINSTALL --------
if [[ "$UNINSTALL" == "1" ]]; then
  log "Uninstalling VM Data Maintenance..."

  systemctl disable --now vm-data-maintenance.timer 2>/dev/null || true
  rm -f "$SERVICE_PATH" "$TIMER_PATH"
  rm -f "$BIN_PATH"

  log "Removed service, timer, and binary."

  if [[ -f "$CONF_PATH" ]]; then
    read -rp "Remove config $CONF_PATH? [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]] && rm -f "$CONF_PATH" && log "Config removed."
  fi

  systemctl daemon-reload
  log "Uninstall complete."
  exit 0
fi

# -------- INSTALL --------
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

SCRIPT_URL="$RAW_BASE/$REMOTE_SCRIPT"
CONF_URL="$RAW_BASE/$REMOTE_CONF"

log "Installing from $SCRIPT_URL"

fetch "$SCRIPT_URL" "$TMPDIR/$REMOTE_SCRIPT" || die "Failed to download script"

# Config
if [[ -f "$CONF_PATH" && "$FORCE" -ne 1 ]]; then
  log "Config exists, skipping (use --force to overwrite)"
else
  fetch "$CONF_URL" "$TMPDIR/$REMOTE_CONF" || die "Failed to download config"
  install -m 0644 "$TMPDIR/$REMOTE_CONF" "$CONF_PATH"
  log "Installed config -> $CONF_PATH"
fi

# Script
if [[ -f "$BIN_PATH" && "$FORCE" -ne 1 ]]; then
  log "Binary exists, skipping (use --force to overwrite)"
else
  install -m 0755 "$TMPDIR/$REMOTE_SCRIPT" "$BIN_PATH"
  log "Installed script -> $BIN_PATH"
fi

# -------- systemd units --------
cat >"$SERVICE_PATH" <<EOF
[Unit]
Description=VM Data Maintenance (logs/tmp/caches + fstrim)
After=network-online.target

[Service]
Type=oneshot
Environment=CONFIG_FILE=$CONF_PATH
ExecStart=$BIN_PATH
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF

cat >"$TIMER_PATH" <<'EOF'
[Unit]
Description=Run VM Data Maintenance daily

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now vm-data-maintenance.timer

log "Install complete."
log "Test with dry run:"
log "  sudo env DRY_RUN=1 $BIN_PATH"

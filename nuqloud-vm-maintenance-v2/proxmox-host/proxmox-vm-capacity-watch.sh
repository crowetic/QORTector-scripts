#!/usr/bin/env bash
# Install on Proxmox HOST, NOT inside the guest. Log-only by default.
set -Eeuo pipefail
MOUNT=${MOUNT:-/var/lib/vz}
VMID=${VMID:-108}
WARN_PERCENT=${WARN_PERCENT:-75}
CRIT_PERCENT=${CRIT_PERCENT:-85}
[[ "$WARN_PERCENT" =~ ^[0-9]+$ && "$CRIT_PERCENT" =~ ^[0-9]+$ ]] || { echo 'Bad thresholds' >&2; exit 2; }
((WARN_PERCENT < CRIT_PERCENT && CRIT_PERCENT <= 100)) || { echo 'Bad threshold order' >&2; exit 2; }
[[ "$VMID" =~ ^[0-9]+$ ]] || { echo 'Bad VMID' >&2; exit 2; }
mountpoint -q -- "$MOUNT" || { echo "Not a mountpoint: $MOUNT" >&2; exit 2; }
PCT=$(df -P -- "$MOUNT" | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
[[ "$PCT" =~ ^[0-9]+$ ]] || { echo 'Cannot read storage usage' >&2; exit 2; }
IMAGE_DIR="$MOUNT/images/$VMID"
ALLOC='unavailable'
if [[ -d "$IMAGE_DIR" ]]; then
  ALLOC=$(du -sB1 -- "$IMAGE_DIR" | awk '{printf "%.1f GiB", $1/1073741824}')
fi
MSG="Proxmox storage $MOUNT ${PCT}% used; VM $VMID allocated=$ALLOC"
if ((PCT >= CRIT_PERCENT)); then
  logger -p daemon.crit -t proxmox-vm-capacity-watch "CRITICAL: $MSG"
  printf 'CRITICAL: %s\n' "$MSG" >&2; exit 2
elif ((PCT >= WARN_PERCENT)); then
  logger -p daemon.warning -t proxmox-vm-capacity-watch "WARNING: $MSG"
  printf 'WARNING: %s\n' "$MSG" >&2; exit 1
fi
printf 'OK: %s\n' "$MSG"

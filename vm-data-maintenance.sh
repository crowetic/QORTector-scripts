#!/usr/bin/env bash
set -euo pipefail

# vm-data-maintenance.sh
# Keep VM disk usage low: vacuum logs/temp/caches (opt-in extras), then fstrim.
# Intended to run inside Linux guests (systemd preferred).

SCRIPT_NAME="vm-data-maintenance"
CONFIG_FILE="${CONFIG_FILE:-/etc/vm-data-maintenance.conf}"

log() { echo "[$(date -Is)] $SCRIPT_NAME: $*"; }

# -------- defaults (can be overridden by config) --------
DRY_RUN="${DRY_RUN:-0}"                      # 1 = show actions, don't delete
ENABLE_TRIM="${ENABLE_TRIM:-1}"              # 1 = run fstrim -av
ENABLE_PACKAGE_CLEAN="${ENABLE_PACKAGE_CLEAN:-1}"
ENABLE_LOG_CLEAN="${ENABLE_LOG_CLEAN:-1}"
ENABLE_TMP_CLEAN="${ENABLE_TMP_CLEAN:-1}"
ENABLE_USER_CACHE_CLEAN="${ENABLE_USER_CACHE_CLEAN:-0}"   # off by default (can surprise users)
ENABLE_DOCKER_PRUNE="${ENABLE_DOCKER_PRUNE:-0}"            # off by default (can be destructive)

# log/journal retention
JOURNAL_MAX_SIZE="${JOURNAL_MAX_SIZE:-200M}" # journald vacuum target size
JOURNAL_MAX_AGE_DAYS="${JOURNAL_MAX_AGE_DAYS:-14}" # vacuum older than N days too (best effort)

# temp retention
TMP_MAX_AGE_DAYS="${TMP_MAX_AGE_DAYS:-10}"
VAR_TMP_MAX_AGE_DAYS="${VAR_TMP_MAX_AGE_DAYS:-10}"

# log retention for plain files
LOG_MAX_AGE_DAYS="${LOG_MAX_AGE_DAYS:-30}"

# Explicit extra cleanup targets (opt-in)
# Arrays require bash; define in config like:
# EXTRA_DELETE_DIRS=( "/var/log/myapp" "/opt/something/tmp" )
# EXTRA_DELETE_GLOBS=( "/var/lib/foo/*.old" )
EXTRA_DELETE_DIRS=()
EXTRA_DELETE_GLOBS=()

# Safety: never delete these paths even if configured badly
DENYLIST_PREFIXES=(
  "/"
  "/bin" "/boot" "/dev" "/etc" "/home" "/lib" "/lib64"
  "/proc" "/root" "/run" "/sbin" "/sys" "/usr" "/var"
)

is_denylisted() {
  local p="$1"
  for d in "${DENYLIST_PREFIXES[@]}"; do
    if [[ "$p" == "$d" ]]; then return 0; fi
  done
  return 1
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: $*"
  else
    eval "$@"
  fi
}

delete_find_older_than_days() {
  local base="$1"
  local days="$2"

  [[ -e "$base" ]] || { log "skip (missing): $base"; return 0; }

  # basic sanity: do not allow obviously dangerous bases
  if is_denylisted "$base"; then
    log "REFUSING to operate on denylisted base: $base"
    return 1
  fi

  # Use -xdev so we don't cross filesystem boundaries (good for mounts)
  # Delete files first, then empty dirs (older than days).
  log "clean: $base (files/dirs older than ${days}d)"
  run_cmd "find \"$base\" -xdev -type f -mtime +\"$days\" -print -delete 2>/dev/null || true"
  run_cmd "find \"$base\" -xdev -type d -empty -mtime +\"$days\" -print -delete 2>/dev/null || true"
}

delete_glob_targets() {
  local g="$1"
  # shellcheck disable=SC2086
  local matches=( $g )
  if (( ${#matches[@]} == 0 )); then
    log "skip (no matches): $g"
    return 0
  fi
  for m in "${matches[@]}"; do
    # sanity: don't allow deleting denylisted exact prefixes
    if is_denylisted "$m"; then
      log "REFUSING to delete denylisted path: $m"
      continue
    fi
    log "delete: $m"
    run_cmd "rm -rf --one-file-system \"$m\" 2>/dev/null || true"
  done
}

maybe_vacuum_journal() {
  command -v journalctl >/dev/null 2>&1 || { log "journalctl not found; skipping journald vacuum"; return 0; }

  log "journald: vacuum by size -> ${JOURNAL_MAX_SIZE}"
  run_cmd "journalctl --vacuum-size=\"$JOURNAL_MAX_SIZE\" >/dev/null 2>&1 || true"

  if [[ "${JOURNAL_MAX_AGE_DAYS}" =~ ^[0-9]+$ ]]; then
    log "journald: vacuum by age -> ${JOURNAL_MAX_AGE_DAYS}d"
    run_cmd "journalctl --vacuum-time=\"${JOURNAL_MAX_AGE_DAYS}days\" >/dev/null 2>&1 || true"
  fi
}

maybe_logrotate_force() {
  if [[ -x /usr/sbin/logrotate ]] && [[ -f /etc/logrotate.conf ]]; then
    log "logrotate: force run"
    run_cmd "/usr/sbin/logrotate -f /etc/logrotate.conf >/dev/null 2>&1 || true"
  else
    log "logrotate not available; skipping"
  fi
}

maybe_clean_packages() {
  [[ "$ENABLE_PACKAGE_CLEAN" == "1" ]] || { log "package cache clean disabled"; return 0; }

  if command -v apt-get >/dev/null 2>&1; then
    log "apt: clean + autoremove"
    run_cmd "apt-get -y autoclean >/dev/null 2>&1 || true"
    run_cmd "apt-get -y clean >/dev/null 2>&1 || true"
    run_cmd "apt-get -y autoremove --purge >/dev/null 2>&1 || true"
  elif command -v dnf >/dev/null 2>&1; then
    log "dnf: clean all"
    run_cmd "dnf -y clean all >/dev/null 2>&1 || true"
  elif command -v yum >/dev/null 2>&1; then
    log "yum: clean all"
    run_cmd "yum -y clean all >/dev/null 2>&1 || true"
  elif command -v pacman >/dev/null 2>&1; then
    log "pacman: clean cache (keep 1 version)"
    run_cmd "paccache -rk1 >/dev/null 2>&1 || true"
  elif command -v zypper >/dev/null 2>&1; then
    log "zypper: clean --all"
    run_cmd "zypper clean -a >/dev/null 2>&1 || true"
  else
    log "no known package manager found; skipping package cache clean"
  fi
}

maybe_clean_tmp() {
  [[ "$ENABLE_TMP_CLEAN" == "1" ]] || { log "tmp clean disabled"; return 0; }

  delete_find_older_than_days "/tmp" "$TMP_MAX_AGE_DAYS"
  delete_find_older_than_days "/var/tmp" "$VAR_TMP_MAX_AGE_DAYS"
}

maybe_clean_plain_logs() {
  [[ "$ENABLE_LOG_CLEAN" == "1" ]] || { log "log clean disabled"; return 0; }

  # journald handles /var/log/journal; we still trim old rotated logs.
  # This is conservative: only files older than N days under /var/log.
  log "plain logs: delete /var/log/* files older than ${LOG_MAX_AGE_DAYS}d (conservative)"
  run_cmd "find /var/log -xdev -type f -mtime +\"$LOG_MAX_AGE_DAYS\" -print -delete 2>/dev/null || true"
  run_cmd "find /var/log -xdev -type d -empty -mtime +\"$LOG_MAX_AGE_DAYS\" -print -delete 2>/dev/null || true"
}

maybe_clean_user_caches() {
  [[ "$ENABLE_USER_CACHE_CLEAN" == "1" ]] || { log "user cache clean disabled"; return 0; }

  # This can annoy users if you nuke browser caches etc. Off by default.
  log "user caches: delete ~/.cache files older than ${TMP_MAX_AGE_DAYS}d for all users (conservative)"
  while IFS=: read -r user _ uid _ _ home _; do
    [[ "$uid" -ge 1000 ]] || continue
    [[ -d "$home/.cache" ]] || continue
    delete_find_older_than_days "$home/.cache" "$TMP_MAX_AGE_DAYS"
  done </etc/passwd
}

maybe_docker_prune() {
  [[ "$ENABLE_DOCKER_PRUNE" == "1" ]] || { log "docker prune disabled"; return 0; }
  command -v docker >/dev/null 2>&1 || { log "docker not found; skipping"; return 0; }

  log "docker: system prune (including unused images/containers/networks)"
  log "WARNING: This may remove stopped containers and unused images. Volumes remain unless you change the command."
  run_cmd "docker system prune -af >/dev/null 2>&1 || true"
}

run_extra_cleanups() {
  if (( ${#EXTRA_DELETE_DIRS[@]} > 0 )); then
    for d in "${EXTRA_DELETE_DIRS[@]}"; do
      # Extra dirs: delete *contents older than TMP_MAX_AGE_DAYS* (override by per-dir patterns if you want)
      delete_find_older_than_days "$d" "$TMP_MAX_AGE_DAYS"
    done
  fi

  if (( ${#EXTRA_DELETE_GLOBS[@]} > 0 )); then
    for g in "${EXTRA_DELETE_GLOBS[@]}"; do
      delete_glob_targets "$g"
    done
  fi
}

maybe_trim() {
  [[ "$ENABLE_TRIM" == "1" ]] || { log "fstrim disabled"; return 0; }
  command -v fstrim >/dev/null 2>&1 || { log "fstrim not found; skipping"; return 0; }

  # If running in containers, fstrim can fail; tolerate it.
  log "fstrim: running fstrim -av"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN: fstrim -av"
  else
    fstrim -av || true
  fi
}

# -------- load config (if present) --------
if [[ -f "$CONFIG_FILE" ]]; then
  log "loading config: $CONFIG_FILE"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
else
  log "no config found at $CONFIG_FILE (using defaults)"
fi

log "starting (dry_run=$DRY_RUN)"
maybe_vacuum_journal
maybe_logrotate_force
maybe_clean_plain_logs
maybe_clean_tmp
maybe_clean_packages
maybe_clean_user_caches
run_extra_cleanups
maybe_docker_prune
maybe_trim
log "done"

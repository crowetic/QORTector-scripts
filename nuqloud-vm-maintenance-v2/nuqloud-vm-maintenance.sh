#!/usr/bin/env bash
# NuQloud VM-level storage maintenance; completely independent of NuQloud instance lifecycle.
set -Eeuo pipefail

MODE=report
DRY_RUN=0
CONFIG_FILE=${CONFIG_FILE:-/etc/nuqloud-vm-maintenance.conf}
APP=nuqloud-vm-maintenance

usage() {
  cat <<'HELP'
Usage: nuqloud-vm-maintenance.sh [--mode trim|daily|weekly|report] [--dry-run] [--config FILE]

  trim    : discard unused blocks on configured guest mountpoints
  daily   : archived journal retention and read-only VM/Docker disk reports
  weekly  : optional APT cache maintenance, tmpfiles cleanup and Docker build-cache pruning
  report  : read-only VM/Docker disk reports

No per-instance commands, Nextcloud occ, database cleanup, Docker volume/image/containers
prune, or changes to application configuration are performed.
HELP
}

while (($#)); do
  case "$1" in
    --mode) [[ $# -gt 1 ]] || { usage >&2; exit 2; }; MODE=$2; shift 2 ;;
    --config) [[ $# -gt 1 ]] || { usage >&2; exit 2; }; CONFIG_FILE=$2; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$MODE" =~ ^(trim|daily|weekly|report)$ ]] || { usage >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

# Deliberately no application/container identifiers in the configuration.
ENABLE_TRIM=1
TRIM_MOUNTS=( / )
ENABLE_JOURNAL_VACUUM=1
JOURNAL_MAX_AGE=10d
JOURNAL_MAX_SIZE=200M
ENABLE_APT_AUTOCLEAN=1
ENABLE_TMPFILES_CLEAN=0
ENABLE_DOCKER_BUILD_CACHE_PRUNE=0
DOCKER_BUILD_CACHE_MIN_AGE=336h
REPORT_DOCKER=1
WARN_GUEST_PERCENT=80
CRIT_GUEST_PERCENT=90

log() { printf '[%s] %s: %s\n' "$(date -Is)" "$APP" "$*"; }
warn() { log "WARNING: $*" >&2; }
run() {
  if ((DRY_RUN)); then
    printf '[DRY RUN]'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

# This is trusted root-run Bash configuration. Never load editable files.
if [[ -e "$CONFIG_FILE" || -L "$CONFIG_FILE" ]]; then
  [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || { warn 'Config is not a regular file'; exit 1; }
  [[ $(stat -c '%u' -- "$CONFIG_FILE") == 0 ]] || { warn 'Config must be root-owned'; exit 1; }
  [[ -z $(find "$CONFIG_FILE" -maxdepth 0 -perm /022 -print) ]] || { warn 'Config must not be writable by group/others'; exit 1; }
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

for var in ENABLE_TRIM ENABLE_JOURNAL_VACUUM ENABLE_APT_AUTOCLEAN ENABLE_TMPFILES_CLEAN ENABLE_DOCKER_BUILD_CACHE_PRUNE REPORT_DOCKER; do
  [[ "${!var}" == 0 || "${!var}" == 1 ]] || { warn "Invalid boolean: $var"; exit 1; }
done
[[ "$WARN_GUEST_PERCENT" =~ ^[0-9]+$ && "$CRIT_GUEST_PERCENT" =~ ^[0-9]+$ ]] || { warn 'Invalid guest thresholds'; exit 1; }
(( WARN_GUEST_PERCENT < CRIT_GUEST_PERCENT && CRIT_GUEST_PERCENT <= 100 )) || { warn 'Invalid threshold ordering'; exit 1; }
for m in "${TRIM_MOUNTS[@]}"; do
  [[ "$m" == /* ]] || { warn "TRIM mount must be absolute: $m"; exit 1; }
done

command -v flock >/dev/null || { warn 'flock missing'; exit 1; }
mkdir -p /run/lock
exec 9>/run/lock/nuqloud-vm-maintenance.lock
if ! flock -n 9; then log 'Already running; skipping overlapping invocation'; exit 0; fi

report_fs() {
  log 'Guest filesystem usage:'
  df -hPT -- / || warn 'df failed'
  local percent
  percent=$(df -P -- / | awk 'NR==2 {gsub(/%/, "", $5); print $5}')
  if [[ $percent =~ ^[0-9]+$ ]]; then
    if ((percent >= CRIT_GUEST_PERCENT)); then warn "CRITICAL guest filesystem at ${percent}%";
    elif ((percent >= WARN_GUEST_PERCENT)); then warn "Guest filesystem at ${percent}%"; fi
  fi
}
report_docker() {
  ((REPORT_DOCKER)) || return 0
  command -v docker >/dev/null || { log 'Docker unavailable; skipping Docker metrics'; return 0; }
  log 'Docker space usage (does not include all bind-mounted data):'
  docker system df || warn 'docker system df failed'
  log 'Docker container block I/O (cumulative counters; compare samples to find rates):'
  docker stats --no-stream --format 'table {{.Name}}\t{{.BlockIO}}' || warn 'docker stats failed'
}

trim_guest() {
  ((ENABLE_TRIM)) || { log 'TRIM disabled'; return 0; }
  command -v fstrim >/dev/null || { warn 'fstrim missing'; return 1; }
  for m in "${TRIM_MOUNTS[@]}"; do
    mountpoint -q -- "$m" || { warn "Not a mountpoint: $m"; return 1; }
    log "TRIM $m (reported TRIM bytes are NOT host space reclaimed)"
    run fstrim -v -- "$m"
  done
}

journal_cleanup() {
  ((ENABLE_JOURNAL_VACUUM)) || return 0
  command -v journalctl >/dev/null || { warn 'journalctl unavailable'; return 0; }
  log 'Vacuuming archived journald logs (active journal files are unaffected)'
  run journalctl --vacuum-time="$JOURNAL_MAX_AGE" --vacuum-size="$JOURNAL_MAX_SIZE"
}

weekly_host_cleanup() {
  if ((ENABLE_APT_AUTOCLEAN)); then
    if command -v apt-get >/dev/null; then
      log 'APT autoclean (no autoremove or upgrades)'
      run apt-get -y autoclean
    fi
  fi
  if ((ENABLE_TMPFILES_CLEAN)); then
    if command -v systemd-tmpfiles >/dev/null; then
      log 'Cleaning temporary paths via existing systemd-tmpfiles policy'
      run systemd-tmpfiles --clean
    fi
  fi
  if ((ENABLE_DOCKER_BUILD_CACHE_PRUNE)); then
    if command -v docker >/dev/null; then
      log "Docker build-cache prune (unused cache older than $DOCKER_BUILD_CACHE_MIN_AGE; no image/container/volume prune)"
      run docker builder prune --all --force --filter "until=$DOCKER_BUILD_CACHE_MIN_AGE"
    fi
  fi
}

log "START mode=$MODE dry_run=$DRY_RUN"
case "$MODE" in
  trim) trim_guest ;;
  daily) report_fs; journal_cleanup; report_docker ;;
  weekly) report_fs; weekly_host_cleanup; report_docker ;;
  report) report_fs; report_docker ;;
esac
log "COMPLETE mode=$MODE"

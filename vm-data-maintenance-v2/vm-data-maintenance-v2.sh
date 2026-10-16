#!/usr/bin/env bash
# VM-level storage maintenance; independent of application instance lifecycle.
set -Eeuo pipefail

MODE=report
DRY_RUN=0
CONFIG_FILE=${CONFIG_FILE:-/etc/vm-data-maintenance-v2.conf}
APP=vm-data-maintenance-v2
RUNTIME_DIR=/run/vm-data-maintenance-v2

usage() {
  cat <<'HELP'
Usage: vm-data-maintenance-v2.sh [--mode trim|daily|weekly|report] [--dry-run] [--config FILE]

  trim    : discard unused blocks on configured guest mountpoints
  daily   : archived journal retention and read-only VM/Docker disk reports
  weekly  : optional APT cache maintenance, tmpfiles cleanup and Docker build-cache pruning
  report  : read-only VM/Docker disk reports

No per-instance commands, Nextcloud occ, database cleanup, Docker volume/image/containers
prune, or changes to application configuration are performed.
HELP
}

# Deliberately no application/container identifiers in the configuration.
ENABLE_TRIM=1
TRIM_MOUNTS=( / )
REPORT_PATHS=( / )
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

require_root() {
  [[ $EUID -eq 0 ]] || { warn 'Run as root'; return 1; }
}

trusted_root_path() {
  # Checking the file alone is insufficient: a writable parent allows replacement
  # between the ownership check and source/open. Reject symlinks in the whole path.
  local path="$1" owner permissions metadata
  [[ "$path" == /* ]] || { warn "Path must be absolute: $path"; return 1; }
  while :; do
    [[ ! -L "$path" ]] || { warn "Symlink in trusted path: $path"; return 1; }
    metadata=$(stat -c '%u %a' -- "$path") || return 1
    read -r owner permissions <<< "$metadata"
    [[ "$owner" == 0 && "$permissions" =~ ^[0-7]{3,4}$ ]] || { warn "Path must be root-owned: $path"; return 1; }
    (( (8#$permissions & 0022) == 0 )) || { warn "Path is writable by group/others: $path"; return 1; }
    [[ "$path" != / ]] || break
    path=$(dirname -- "$path")
  done
}

load_config() {
  # Config is required, including for dry runs; a typo must not enable defaults.
  [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || { warn "Config missing or not a regular file: $CONFIG_FILE"; return 1; }
  trusted_root_path "$CONFIG_FILE" || return 1
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
}

validate_paths() {
  local variable="$1" allow_empty="$2" declaration path
  declaration=$(declare -p "$variable" 2>/dev/null) || { warn "$variable must be a Bash array"; return 1; }
  [[ "$declaration" == 'declare -a '* ]] || { warn "$variable must be a Bash array"; return 1; }
  local -n paths="$variable"
  (( allow_empty || ${#paths[@]} > 0 )) || { warn "$variable must not be empty"; return 1; }
  for path in "${paths[@]}"; do
    [[ "$path" == /* && "$path" != *$'\n'* ]] || { warn "$variable needs absolute paths: $path"; return 1; }
  done
}

validate_config() {
  local var
  for var in ENABLE_TRIM ENABLE_JOURNAL_VACUUM ENABLE_APT_AUTOCLEAN ENABLE_TMPFILES_CLEAN ENABLE_DOCKER_BUILD_CACHE_PRUNE REPORT_DOCKER; do
    [[ "${!var:-}" == 0 || "${!var:-}" == 1 ]] || { warn "Invalid boolean: $var"; return 1; }
  done
  [[ "$WARN_GUEST_PERCENT" =~ ^([1-9][0-9]?|100)$ && "$CRIT_GUEST_PERCENT" =~ ^([1-9][0-9]?|100)$ ]] || { warn 'Guest thresholds must be integers from 1 to 100, without leading zeros'; return 1; }
  (( WARN_GUEST_PERCENT < CRIT_GUEST_PERCENT )) || { warn 'Invalid threshold ordering'; return 1; }
  [[ "$JOURNAL_MAX_AGE" =~ ^[1-9][0-9]{0,8}[smhdw]$ ]] || { warn 'JOURNAL_MAX_AGE needs a positive duration, e.g. 10d'; return 1; }
  [[ "$JOURNAL_MAX_SIZE" =~ ^[1-9][0-9]{0,8}[KMGT]?$ ]] || { warn 'JOURNAL_MAX_SIZE needs a positive size, e.g. 200M'; return 1; }
  [[ "$DOCKER_BUILD_CACHE_MIN_AGE" =~ ^[1-9][0-9]{0,8}[smh]$ ]] || { warn 'DOCKER_BUILD_CACHE_MIN_AGE needs a positive duration, e.g. 336h'; return 1; }
  validate_paths TRIM_MOUNTS "$((1 - ENABLE_TRIM))" || return 1
  validate_paths REPORT_PATHS 0
}

acquire_lock() {
  command -v flock >/dev/null || { warn 'flock missing'; return 1; }
  trusted_root_path "$(dirname -- "$RUNTIME_DIR")" || return 1
  if [[ ! -e "$RUNTIME_DIR" && ! -L "$RUNTIME_DIR" ]]; then
    mkdir -m 0700 -- "$RUNTIME_DIR" || return 1
  fi
  [[ -d "$RUNTIME_DIR" && ! -L "$RUNTIME_DIR" ]] || { warn 'Unsafe runtime directory'; return 1; }
  trusted_root_path "$RUNTIME_DIR" || return 1
  chmod 0700 -- "$RUNTIME_DIR" || return 1
  local lock="$RUNTIME_DIR/maintenance.lock"
  [[ ! -L "$lock" && ( ! -e "$lock" || -f "$lock" ) ]] || { warn 'Unsafe lock file'; return 1; }
  if [[ -e "$lock" ]]; then trusted_root_path "$lock" || return 1; fi
  (umask 077; : >> "$lock") || return 1
  exec 9>>"$lock" || return 1
  if ! flock -n 9; then log 'Already running; skipping overlapping invocation'; exit 0; fi
}

report_fs() {
  log 'Guest filesystem usage:'
  local path percent status=0
  df -hPT -- "${REPORT_PATHS[@]}" || { warn 'Filesystem summary failed'; status=1; }
  for path in "${REPORT_PATHS[@]}"; do
    if percent=$(df -P -- "$path" | awk 'NR==2 {gsub(/%/, "", $5); print $5}') && [[ "$percent" =~ ^(0|[1-9][0-9]*)$ ]]; then
      if ((percent >= CRIT_GUEST_PERCENT)); then warn "CRITICAL guest filesystem for $path at ${percent}%";
      elif ((percent >= WARN_GUEST_PERCENT)); then warn "Guest filesystem for $path at ${percent}%"; fi
    else
      warn "Could not read filesystem usage for $path"; status=1
    fi
  done
  return "$status"
}
report_docker() {
  ((REPORT_DOCKER)) || return 0
  command -v docker >/dev/null || { log 'Docker unavailable; skipping Docker metrics'; return 0; }
  local status=0
  log 'Docker space usage (does not include all bind-mounted data):'
  docker system df || { warn 'docker system df failed'; status=1; }
  log 'Docker container block I/O (cumulative counters; compare samples to find rates):'
  docker stats --no-stream --format 'table {{.Name}}\t{{.BlockIO}}' || { warn 'docker stats failed'; status=1; }
  return "$status"
}

trim_guest() {
  ((ENABLE_TRIM)) || { log 'TRIM disabled'; return 0; }
  command -v fstrim >/dev/null || { warn 'fstrim missing'; return 1; }
  local m status=0
  # Check every configured mount before issuing any discard operations.
  for m in "${TRIM_MOUNTS[@]}"; do
    mountpoint -q -- "$m" || { warn "Not a mountpoint: $m"; return 1; }
  done
  for m in "${TRIM_MOUNTS[@]}"; do
    log "TRIM $m (reported TRIM bytes are NOT host space reclaimed)"
    run fstrim -v -- "$m" || { warn "TRIM failed for $m"; status=1; }
  done
  return "$status"
}

journal_cleanup() {
  ((ENABLE_JOURNAL_VACUUM)) || return 0
  command -v journalctl >/dev/null || { warn 'journalctl unavailable'; return 1; }
  log 'Vacuuming archived journald logs (active journal files are unaffected)'
  run journalctl --vacuum-time="$JOURNAL_MAX_AGE" --vacuum-size="$JOURNAL_MAX_SIZE"
}

weekly_guest_cleanup() {
  local status=0
  if ((ENABLE_APT_AUTOCLEAN)); then
    if command -v apt-get >/dev/null; then
      log 'APT autoclean (no autoremove or upgrades)'
      run apt-get -y autoclean || { warn 'APT autoclean failed'; status=1; }
    fi
  fi
  if ((ENABLE_TMPFILES_CLEAN)); then
    if command -v systemd-tmpfiles >/dev/null; then
      log 'Cleaning temporary paths via existing systemd-tmpfiles policy'
      run systemd-tmpfiles --clean || { warn 'tmpfiles cleanup failed'; status=1; }
    else
      warn 'tmpfiles cleanup enabled but systemd-tmpfiles unavailable'; status=1
    fi
  fi
  if ((ENABLE_DOCKER_BUILD_CACHE_PRUNE)); then
    if command -v docker >/dev/null; then
      log "Docker build-cache prune (unused cache older than $DOCKER_BUILD_CACHE_MIN_AGE; no image/container/volume prune)"
      run docker builder prune --all --force --filter "until=$DOCKER_BUILD_CACHE_MIN_AGE" || { warn 'Docker build-cache pruning failed'; status=1; }
    else
      warn 'Build-cache pruning enabled but Docker unavailable'; status=1
    fi
  fi
  return "$status"
}

main() {
  while (($#)); do
    case "$1" in
      --mode) [[ $# -gt 1 ]] || { usage >&2; return 2; }; MODE=$2; shift 2 ;;
      --config) [[ $# -gt 1 ]] || { usage >&2; return 2; }; CONFIG_FILE=$2; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; return 0 ;;
      *) echo "Unknown argument: $1" >&2; usage >&2; return 2 ;;
    esac
  done
  [[ "$MODE" =~ ^(trim|daily|weekly|report)$ ]] || { usage >&2; return 2; }
  require_root || return 1
  # Configuration may adjust documented settings, never the selected mode,
  # dry-run flag or the private lock location.
  readonly MODE DRY_RUN CONFIG_FILE APP RUNTIME_DIR
  load_config || return 1
  validate_config || return 1
  acquire_lock || return 1

  local status=0
  log "START mode=$MODE dry_run=$DRY_RUN"
  case "$MODE" in
    trim) trim_guest || status=1 ;;
    daily) report_fs || status=1; journal_cleanup || status=1; report_docker || status=1 ;;
    weekly) report_fs || status=1; weekly_guest_cleanup || status=1; report_docker || status=1 ;;
    report) report_fs || status=1; report_docker || status=1 ;;
  esac
  if ((status)); then warn "FAILED mode=$MODE"; return "$status"; fi
  log "COMPLETE mode=$MODE"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi

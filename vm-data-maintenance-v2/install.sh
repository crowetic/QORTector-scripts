#!/usr/bin/env bash
# Install the guest utility and migrate the legacy NuQloud-named guest units.
set -Eeuo pipefail

INSTALL_SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# Reuse config/path validation. Sourcing the library does not run maintenance.
# shellcheck source=vm-data-maintenance-v2.sh
source "$INSTALL_SOURCE_DIR/vm-data-maintenance-v2.sh"
BIN_DIR=/usr/local/sbin
CONFIG_DIR=/etc
UNIT_DIR=/etc/systemd/system
INSTALL_RUNTIME_DIR=/run/vm-data-maintenance-v2-install
LEGACY_APP=nuqloud-vm-maintenance
ENABLE_TIMERS=1

install_usage() {
  printf 'Usage: install.sh [--no-enable]\n'
  printf 'Run inside the VM as root. --no-enable leaves new timers unenabled for testing.\n'
}

prepare_directory() {
  local path="$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    prepare_directory "$(dirname -- "$path")" || return 1
    mkdir -m 0755 -- "$path" || return 1
  fi
  [[ -d "$path" && ! -L "$path" ]] || { warn "Unsafe install directory: $path"; return 1; }
  trusted_root_path "$path"
}

check_existing_file() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    [[ -f "$path" && ! -L "$path" ]] || { warn "Unsafe install file: $path"; return 1; }
    trusted_root_path "$path" || return 1
  fi
}

install_file() {
  local source="$1" destination="$2" mode="$3" temporary
  check_existing_file "$destination" || return 1
  temporary=$(mktemp "${destination}.XXXXXX") || return 1
  if ! install -o root -g root -m "$mode" -- "$source" "$temporary"; then
    rm -f -- "$temporary"; return 1
  fi
  if ! mv -T -- "$temporary" "$destination"; then
    rm -f -- "$temporary"; return 1
  fi
}

verify_installation() {
  local binary="$BIN_DIR/$APP.sh" config="$CONFIG_DIR/$APP.conf" mode
  for mode in report trim daily weekly; do
    "$binary" --config "$config" --mode "$mode" --dry-run || return 1
  done
}

unit_present() { systemctl cat -- "$1" >/dev/null 2>&1; }

install_main() {
  while (($#)); do
    case "$1" in
      --no-enable) ENABLE_TIMERS=0; shift ;;
      -h|--help) install_usage; return 0 ;;
      *) install_usage >&2; return 2 ;;
    esac
  done
  require_root || return 1
  command -v systemctl >/dev/null || { warn 'systemctl is required'; return 1; }
  systemctl show --property=Version --value >/dev/null || { warn 'A running systemd manager is required'; return 1; }
  local source="$INSTALL_SOURCE_DIR/$APP.sh" example="$INSTALL_SOURCE_DIR/$APP.conf.example"
  local config="$CONFIG_DIR/$APP.conf" legacy_config="$CONFIG_DIR/$LEGACY_APP.conf"
  local unit mode backup
  bash -n "$source" "$example" || return 1
  for unit in "$APP@.service" "$APP-trim.timer" "$APP-daily.timer" "$APP-weekly.timer"; do
    [[ -f "$INSTALL_SOURCE_DIR/systemd/$unit" ]] || { warn "Missing payload: $unit"; return 1; }
  done
  for mode in "$BIN_DIR" "$CONFIG_DIR" "$UNIT_DIR"; do prepare_directory "$mode" || return 1; done
  RUNTIME_DIR="$INSTALL_RUNTIME_DIR"
  acquire_lock || return 1
  check_existing_file "$config" || return 1
  check_existing_file "$legacy_config" || return 1

  if [[ -e "$config" ]]; then
    log "Keeping existing config: $config"
    if [[ -e "$legacy_config" ]]; then
      backup=$(mktemp "$CONFIG_DIR/$APP.conf.pre-migration.XXXXXX") || return 1
      install_file "$legacy_config" "$backup" 0600 || return 1
      log "Preserved legacy config separately: $backup"
    fi
  elif [[ -e "$legacy_config" ]]; then
    install_file "$legacy_config" "$config" 0600 || return 1
    log "Migrated legacy config to $config"
  else
    install_file "$example" "$config" 0600 || return 1
  fi
  install_file "$source" "$BIN_DIR/$APP.sh" 0755 || return 1
  for unit in "$APP@.service" "$APP-trim.timer" "$APP-daily.timer" "$APP-weekly.timer"; do
    install_file "$INSTALL_SOURCE_DIR/systemd/$unit" "$UNIT_DIR/$unit" 0644 || return 1
  done

  # Verify the new config/commands before stopping or deleting the old install.
  verify_installation || { warn 'Verification failed; legacy files and schedules were kept'; return 1; }
  for mode in trim daily weekly; do
    if unit_present "$LEGACY_APP-$mode.timer"; then
      systemctl disable --now "$LEGACY_APP-$mode.timer" || return 1
    fi
  done
  if unit_present "$LEGACY_APP@.service"; then
    systemctl stop "$LEGACY_APP@trim.service" "$LEGACY_APP@daily.service" \
      "$LEGACY_APP@weekly.service" "$LEGACY_APP@report.service" || return 1
  fi
  rm -f -- "$BIN_DIR/$LEGACY_APP.sh" "$legacy_config" || return 1
  for unit in "$LEGACY_APP@.service" "$LEGACY_APP-trim.timer" "$LEGACY_APP-daily.timer" "$LEGACY_APP-weekly.timer"; do
    rm -f -- "$UNIT_DIR/$unit" || return 1
  done
  systemctl daemon-reload || return 1
  if ((ENABLE_TIMERS)); then
    systemctl enable --now "$APP-trim.timer" "$APP-daily.timer" "$APP-weekly.timer" || return 1
  fi
  log 'Guest installation complete; stock fstrim.timer has not been changed'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then install_main "$@"; fi

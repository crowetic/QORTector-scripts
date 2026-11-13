#!/bin/bash
# Apply the installed Cinnamon schema, rather than an obsolete exported schema.

SETTINGS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

apply_menu_settings() {
  local enabled schema="${CINNAMON_MENU_SCHEMA:-/usr/share/cinnamon/applets/menu@cinnamon.org/settings-schema.json}"
  enabled=$(gsettings get org.cinnamon enabled-applets) || return 1
  python3 - "$SETTINGS_SCRIPT_DIR/cinnamon-settings.json" "$schema" "$enabled" <<'PYMENU'
import ast
import copy
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

preferences_path, schema_path, enabled = sys.argv[1:]
schema_file = Path(schema_path)
raw = schema_file.read_bytes()
schema = json.loads(raw)
checksum = hashlib.md5(raw).hexdigest()
override_file = schema_file.with_name('settings-override.json')
if override_file.exists():
    override_raw = override_file.read_bytes()
    checksum += hashlib.md5(override_raw).hexdigest()
    for key, value in json.loads(override_raw).items():
        if 'override-props' in value:
            schema[key].update({k: v for k, v in value.items() if k != 'override-props'})
        else:
            schema[key] = value
preferences = json.loads(Path(preferences_path).read_text())
# Use the actual PNG when available so menu branding does not depend on the
# active icon theme or a stale icon cache. Keep the theme name as a fallback.
for icon in (Path.home() / 'Pictures/icons/icons_theme/qortal-menu-button-2.png',
             Path.home() / '.icons/Yaru-blue-qortal/48x48/apps/qortal-menu-button-2.png'):
    if icon.is_file() and icon.stat().st_size:
        preferences['menu-icon']['value'] = str(icon)
        break
instances = set()
for entry in ast.literal_eval(re.sub(r'^\s*@as\s+', '', enabled)):
    fields = entry.split(':')
    if len(fields) >= 5 and fields[-2] == 'menu@cinnamon.org' and fields[-1].isdigit():
        instances.add(fields[-1])
if not instances:
    print('No enabled standard Cinnamon menu applet; leaving menu instances unchanged.')
config_home = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
backup_dir = Path(os.environ.get('REBUILT_MACHINE_BACKUP_DIR') or Path.home() / 'backups/cinnamon-menu')
for instance in sorted(instances):
    target = config_home / f'cinnamon/spices/menu@cinnamon.org/{instance}.json'
    # Read legacy values once when migrating an existing desktop.
    legacy = Path.home() / f'.cinnamon/configs/menu@cinnamon.org/{instance}.json'
    previous_path = target if target.exists() else legacy
    previous = json.loads(previous_path.read_text()) if previous_path.exists() else {}
    merged = copy.deepcopy(schema)
    for key, item in merged.items():
        if not isinstance(item, dict) or 'default' not in item:
            continue
        item['value'] = previous.get(key, {}).get('value', item['default'])
        desired = preferences.get(key, {})
        if isinstance(desired, dict) and 'value' in desired:
            item['value'] = desired['value']
    # Use the tested size even if an older exported preference file is supplied.
    if 'menu-icon-size' in merged:
        merged['menu-icon-size']['value'] = 40
    merged['__md5__'] = checksum
    output = json.dumps(merged, indent=4, ensure_ascii=False) + '\n'
    if target.exists() and target.read_text() == output:
        print(f'Cinnamon menu {instance} already configured (40px).')
        continue
    if previous_path.exists():
        backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(previous_path, backup_dir / f'menu-{instance}-{time.time_ns()}.json')
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=target.name + '.', dir=target.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            out.write(output)
        os.replace(tmp, target)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    print(f'Configured Cinnamon menu {instance}: {target} (40px).')
PYMENU
}

set_desktop_setting() {
  local actual
  gsettings set "$1" "$2" "$3" || return 1
  # dconf can report a commit failure on stderr while gsettings exits zero.
  # Read back in a separate process before considering the preference applied.
  actual=$(gsettings get "$1" "$2") || return 1
  if ! python3 - "$3" "$actual" <<'PYCHECK'
import ast
import sys
sys.exit(0 if ast.literal_eval(sys.argv[2]) == sys.argv[1] else 1)
PYCHECK
  then
    echo "Could not persist $1 $2; desktop branding must be retried." >&2
    return 1
  fi
}

apply_desktop_branding() {
  local wallpaper="$HOME/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png" value keys schemas schema applied=0
  if [ ! -s "$wallpaper" ]; then
    echo 'Qortal The Future wallpaper is missing; rerun rebuilt-machine.sh to repair artwork.' >&2
    return 1
  fi
  value=$(python3 - "$wallpaper" <<'PYURI'
from pathlib import Path
import sys
print(Path(sys.argv[1]).as_uri())
PYURI
) || return 1
  # Ubuntu/GNOME and Cinnamon use separate background schemas. Configure both
  # when installed, including dark mode, without assuming every version has it.
  schemas=$(gsettings list-schemas) || return 1
  for schema in org.cinnamon.desktop.background org.gnome.desktop.background; do
    grep -Fxq "$schema" <<< "$schemas" || continue
    keys=$(gsettings list-keys "$schema") || return 1
    grep -Fxq picture-uri <<< "$keys" || continue
    set_desktop_setting "$schema" picture-uri "$value" || return 1
    applied=1
    if grep -Fxq picture-uri-dark <<< "$keys"; then
      set_desktop_setting "$schema" picture-uri-dark "$value" || return 1
    else
      echo "$schema has no picture-uri-dark key; picture-uri is used for both appearances."
    fi
    # A previous 'none' value would hide the wallpaper even with a correct URI.
    if grep -Fxq picture-options <<< "$keys"; then
      set_desktop_setting "$schema" picture-options zoom || return 1
    fi
  done
  [ "$applied" = 1 ] || { echo 'No supported desktop background schema found.' >&2; return 1; }
  if [ ! -f "$HOME/.icons/Yaru-blue-qortal/index.theme" ] || \
      [ ! -s "$HOME/.icons/Yaru-blue-qortal/48x48/apps/qortal-menu-button-2.png" ]; then
    echo 'Qortal icon theme is missing; rerun rebuilt-machine.sh to repair artwork.' >&2
    return 1
  fi
  set_desktop_setting org.cinnamon.desktop.interface icon-theme Yaru-blue-qortal
}

apply_desktop_themes() {
  # Do not select themes that failed to download or do not support this widget set.
  local theme_root part schema key value
  for part in 'gtk-3.0:org.cinnamon.desktop.interface:gtk-theme:Windows-10-Dark' \
      'metacity-1:org.cinnamon.desktop.wm.preferences:theme:Windows-10-Dark' \
      'cinnamon:org.cinnamon.theme:name:Windows-10'; do
    IFS=: read -r theme_root schema key value <<< "$part"
    if [ -d "$HOME/.themes/$value/$theme_root" ] || [ -d "/usr/share/themes/$value/$theme_root" ]; then
      set_desktop_setting "$schema" "$key" "$value" || return 1
    fi
  done
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark || echo 'Could not request dark mode.' >&2
}

main() {
  set -euo pipefail
  local mode="${1:-all}" first_login=0
  if [ "$mode" = --first-login ]; then
    first_login=1
    mode="${2:---settings-only}"
    case "$mode" in --branding-only|--settings-only) ;; *) echo 'Invalid first-login mode.' >&2; return 1 ;; esac
  fi
  case "$mode" in all|--menu-only|--settings-only|--branding-only) ;; *) echo 'Usage: apply-cinnamon-settings.sh [--menu-only|--branding-only|--settings-only|--first-login [--branding-only|--settings-only]]' >&2; return 1 ;; esac
  if [ "$mode" != --menu-only ] && { [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; }; then
    echo 'No desktop D-Bus session; leaving first-login branding queued.' >&2
    return 1
  fi
  if [ "$first_login" = 1 ]; then
    sleep 5
    # The first login can occur long after setup. Save the current state again
    # before any gsettings changes, rather than relying on the setup-time copy.
    local backup="${REBUILT_MACHINE_BACKUP_DIR:-$HOME/backups/cinnamon-menu}"
    command -v dconf >/dev/null || { echo 'dconf is required before applying first-login defaults.' >&2; return 1; }
    mkdir -p "$backup"
    dconf dump / > "$backup/first-login-$(date +%s%N).dconf"
  fi
  if [ "$mode" = all ]; then
    if ! QORTAL_ICONS_SELECT_THEME=0 bash "$SETTINGS_SCRIPT_DIR/create-icon-theme-uni.sh"; then
      echo 'Qortal icon installation failed. Run create-icon-theme-uni.sh to retry.' >&2
      return 1
    fi
  fi
  if [ "$mode" != --menu-only ]; then
    if [ "$mode" != --branding-only ]; then apply_desktop_themes; fi
    apply_desktop_branding
  fi
  apply_menu_settings
  if [ "$first_login" = 1 ]; then
    if [ "$mode" = --settings-only ]; then
      REBUILT_MACHINE_BACKUP_DIR="$backup" bash "$SETTINGS_SCRIPT_DIR/configure-terminal-and-more.sh" || echo 'Some optional desktop preferences could not be applied.' >&2
    fi
    rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/apply-cinnamon-settings.desktop"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

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
import subprocess
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
live = False
status = 0
if instances and os.environ.get('DBUS_SESSION_BUS_ADDRESS') and shutil.which('gdbus'):
    try:
        owner = subprocess.run(
            ['gdbus', 'call', '--session', '--timeout', '5', '--dest', 'org.freedesktop.DBus',
             '--object-path', '/org/freedesktop/DBus', '--method', 'org.freedesktop.DBus.NameHasOwner',
             'org.Cinnamon'], capture_output=True, text=True, timeout=7)
        live = owner.returncode == 0 and owner.stdout.strip() == '(true,)'
    except subprocess.TimeoutExpired:
        pass

def refresh_menu(instance):
    # Use the same notification as Cinnamon Settings. File writes alone can
    # leave the running applet's in-memory values stale, even on a repeat run.
    global status
    if not live:
        return
    try:
        result = subprocess.run(
            ['gdbus', 'call', '--session', '--timeout', '5', '--dest', 'org.Cinnamon',
             '--object-path', '/org/Cinnamon', '--method', 'org.Cinnamon.updateSetting',
             'menu@cinnamon.org', instance, '', ''],
            capture_output=True, text=True, timeout=7)
        if result.returncode == 0:
            return
        detail = result.stderr.strip()
    except subprocess.TimeoutExpired:
        detail = 'request timed out'
    print(f'Could not refresh Cinnamon menu {instance}: {detail}; retry at Cinnamon login.', file=sys.stderr)
    status = 1

for instance in sorted(instances):
    target = config_home / f'cinnamon/spices/menu@cinnamon.org/{instance}.json'
    # Cinnamon keeps watching the legacy file if it was the only file at login.
    # Update that same file so a running applet sees the change immediately.
    legacy = Path.home() / f'.cinnamon/configs/menu@cinnamon.org/{instance}.json'
    if legacy.exists() and not target.exists():
        target = legacy
    previous_path = target
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
        refresh_menu(instance)
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
    refresh_menu(instance)
sys.exit(status)
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
expected = {'true': True, 'false': False}.get(sys.argv[1], sys.argv[1])
actual = sys.argv[2].strip()
actual = {'true': True, 'false': False}[actual] if actual in ('true', 'false') else ast.literal_eval(actual)
sys.exit(0 if actual == expected else 1)
PYCHECK
  then
    echo "Could not persist $1 $2; desktop branding must be retried." >&2
    return 1
  fi
}

apply_desktop_wallpaper() {
  local wallpaper="$HOME/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png" value keys schemas schema applied=0 status=0
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
    keys=$(gsettings list-keys "$schema") || { status=1; continue; }
    grep -Fxq picture-uri <<< "$keys" || continue
    set_desktop_setting "$schema" picture-uri "$value" || status=1
    applied=1
    if grep -Fxq picture-uri-dark <<< "$keys"; then
      set_desktop_setting "$schema" picture-uri-dark "$value" || status=1
    else
      echo "$schema has no picture-uri-dark key; picture-uri is used for both appearances."
    fi
    # A previous 'none' value would hide the wallpaper even with a correct URI.
    if grep -Fxq picture-options <<< "$keys"; then
      set_desktop_setting "$schema" picture-options zoom || status=1
    fi
  done
  [ "$applied" = 1 ] || { echo 'No supported desktop background schema found.' >&2; status=1; }
  return "$status"
}

apply_desktop_branding() {
  local schemas schema status=0
  apply_desktop_wallpaper || status=1
  if [ ! -f "$HOME/.icons/Yaru-blue-qortal/index.theme" ] || \
      [ ! -s "$HOME/.icons/Yaru-blue-qortal/48x48/apps/qortal-menu-button-2.png" ]; then
    echo 'Qortal icon theme is missing; rerun rebuilt-machine.sh to repair artwork.' >&2
    return 1
  fi
  schemas=$(gsettings list-schemas) || return 1
  for schema in org.cinnamon.desktop.interface org.gnome.desktop.interface; do
    grep -Fxq "$schema" <<< "$schemas" || continue
    set_desktop_setting "$schema" icon-theme Yaru-blue-qortal || status=1
  done
  return "$status"
}

# Return a directory containing the requested component, in GTK search order.
find_desktop_theme() {
  local name="$1" component="$2" root
  local -a roots
  IFS=: read -r -a roots <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  roots=("$HOME/.themes" "${XDG_DATA_HOME:-$HOME/.local/share}/themes" "${roots[@]/%//themes}")
  for root in "${roots[@]}"; do
    if [ -s "$root/$name/$component" ]; then
      printf '%s\n' "$root/$name"
      return 0
    fi
  done
  return 1
}

apply_desktop_themes() {
  local schema keys name selected='' status=0
  # Yaru-blue-qortal is our ICON theme. Only select a custom GTK theme when
  # its actual stylesheet exists; otherwise use an installed dark GTK theme.
  for name in yaru-blue-qortal Yaru-blue-dark Yaru-dark Windows-10-Dark Adwaita-dark; do
    if find_desktop_theme "$name" gtk-3.0/gtk.css >/dev/null; then selected=$name; break; fi
  done
  if [ -n "$selected" ]; then
    set_desktop_setting org.cinnamon.desktop.interface gtk-theme "$selected" || status=1
  else
    echo 'No supported dark GTK theme installed; install Yaru-dark, Windows-10-Dark or Adwaita-dark and retry.' >&2
    status=1
  fi
  selected=''
  for name in windows-10-dark Windows-10-Dark Yaru-blue-dark Yaru-dark Adwaita; do
    if find_desktop_theme "$name" metacity-1/metacity-theme-3.xml >/dev/null || \
        find_desktop_theme "$name" metacity-1/metacity-theme-2.xml >/dev/null || \
        find_desktop_theme "$name" metacity-1/metacity-theme-1.xml >/dev/null; then selected=$name; break; fi
  done
  if [ -n "$selected" ]; then
    set_desktop_setting org.cinnamon.desktop.wm.preferences theme "$selected" || status=1
  else
    echo 'Keeping installed window borders; no optional dark border theme found.'
  fi
  # The Desktop row in Cinnamon Themes is the shell/panel theme. Use the
  # requested Windows-10 shell independently of dark applications and borders.
  if find_desktop_theme Windows-10 cinnamon/cinnamon.css >/dev/null; then
    set_desktop_setting org.cinnamon.theme name Windows-10 || status=1
  else
    echo 'Windows-10 Cinnamon desktop theme is missing; rerun rebuilt-machine.sh to install it.' >&2
    status=1
  fi
  local schemas
  schemas=$(gsettings list-schemas) || return 1
  # Cinnamon's Themes > Settings > Dark mode uses the XApp portal key.
  for schema in org.x.apps.portal org.cinnamon.desktop.interface org.gnome.desktop.interface; do
    grep -Fxq "$schema" <<< "$schemas" || continue
    keys=$(gsettings list-keys "$schema") || { status=1; continue; }
    if grep -Fxq color-scheme <<< "$keys"; then
      set_desktop_setting "$schema" color-scheme prefer-dark || status=1
    fi
  done
  return "$status"
}

apply_desktop_icons() {
  local key status=0
  for key in show-desktop-icons home-icon-visible trash-icon-visible; do
    set_desktop_setting org.nemo.desktop "$key" true || status=1
  done
  set_desktop_setting org.nemo.desktop desktop-layout 'true::false' || status=1
  return "$status"
}

apply_desktop_icon_layout() (
  # Nemo caches desktop-metadata for the life of nemo-desktop. Stop only the
  # current user's desktop process while editing it, leaving file windows alone.
  local visible status=0 attempt monitors=1
  command -v pgrep >/dev/null || { echo 'pgrep is required to safely update Nemo desktop metadata.' >&2; return 1; }
  if pgrep -u "$(id -u)" -x nemo-desktop >/dev/null; then
    visible=$(gsettings get org.nemo.desktop show-desktop-icons) || return 1
    # Restore visibility and the desktop process on errors or interruption too.
    trap 'status=$?; set_desktop_setting org.nemo.desktop show-desktop-icons "$visible" || status=1; nohup nemo-desktop >/dev/null 2>&1 & exit "$status"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    # Avoid Cinnamon's conditional autostart racing the metadata replacement.
    set_desktop_setting org.nemo.desktop show-desktop-icons false || return 1
    nemo-desktop --quit || status=1
    for ((attempt=0; attempt<50; attempt++)); do
      pgrep -u "$(id -u)" -x nemo-desktop >/dev/null || break
      sleep 0.1
    done
    if pgrep -u "$(id -u)" -x nemo-desktop >/dev/null; then
      echo 'Nemo desktop did not stop; retaining first-login retry.' >&2
      status=1
    fi
  fi
  if [ "$status" = 0 ]; then
    if command -v xrandr >/dev/null; then
      monitors=$(xrandr --listactivemonitors 2>/dev/null | sed -n 's/^Monitors: //p') || monitors=1
    fi
    python3 - "${monitors:-1}" <<'PYLAYOUT' || status=1
import configparser
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

target = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'nemo/desktop-metadata'
previous = target.read_text() if target.exists() else ''
parser = configparser.RawConfigParser()
parser.read_string(previous)  # Fail safely on malformed metadata.
count = int(sys.argv[1]) if sys.argv[1].isdigit() else 1
sections = {f'desktop-monitor-{i}' for i in range(max(1, count))}
sections.update(s for s in parser.sections() if re.fullmatch(r'desktop-monitor-\d+|directory', s))
output = previous + ('\n' if previous and not previous.endswith('\n') else '')
for section in sorted(sections):
    pattern = r'(?ms)(^\[' + re.escape(section) + r'\][^\n]*\n)(.*?)(?=^\[|\Z)'
    match = re.search(pattern, output)
    setting = 'nemo-icon-view-auto-layout=false\n'
    if match:
        body = match[2]
        key = r'(?m)^[ \t]*nemo-icon-view-auto-layout\s*=.*(?:\n|$)'
        body = re.sub(key, setting, body) if re.search(key, body) else body.rstrip('\n') + '\n' + setting
        output = output[:match.start(2)] + body + output[match.end(2):]
    else:
        output = (output.rstrip('\n') + '\n\n' if output else '') + f'[{section}]\n' + setting
if output != previous:
    if target.exists():
        backup = Path(os.environ.get('REBUILT_MACHINE_BACKUP_DIR') or Path.home() / 'backups/cinnamon-menu')
        backup.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, backup / f'nemo-desktop-metadata-{time.time_ns()}')
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix='desktop-metadata.', dir=target.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            out.write(output)
        os.replace(tmp, target)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
print('Nemo desktop auto-arrange disabled; existing icon positions and grid spacing preserved.')
PYLAYOUT
  fi
  return "$status"
)

main() {
  set -euo pipefail
  local mode="${1:-all}" first_login=0
  if [ "$mode" = --first-login ]; then
    first_login=1
    mode="${2:---settings-only}"
    case "$mode" in --branding-only|--desktop-only|--settings-only) ;; *) echo 'Invalid first-login mode.' >&2; return 1 ;; esac
  fi
  case "$mode" in all|--menu-only|--settings-only|--desktop-only|--branding-only) ;; *) echo 'Usage: apply-cinnamon-settings.sh [--menu-only|--branding-only|--desktop-only|--settings-only|--first-login [--branding-only|--desktop-only|--settings-only]]' >&2; return 1 ;; esac
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
  local status=0
  if [ "$mode" = all ]; then
    if ! QORTAL_ICONS_SELECT_THEME=0 bash "$SETTINGS_SCRIPT_DIR/create-icon-theme-uni.sh"; then
      echo 'Qortal icon installation failed. Run create-icon-theme-uni.sh to retry.' >&2
      status=1
    fi
  fi
  if [ "$mode" != --menu-only ]; then
    # Each group must run even if a missing asset or failed write affects another.
    if [ "$mode" != --branding-only ]; then
      apply_desktop_themes || status=1
      apply_desktop_icon_layout || status=1
      apply_desktop_icons || status=1
    fi
    apply_desktop_branding || status=1
  fi
  apply_menu_settings || status=1
  [ "$status" = 0 ] || return "$status"
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

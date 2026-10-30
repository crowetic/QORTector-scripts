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

apply_desktop_themes() {
  # Do not select themes that failed to download or do not support this widget set.
  local theme_root part schema key value wallpaper
  for part in 'gtk-3.0:org.cinnamon.desktop.interface:gtk-theme:Windows-10-Dark' \
      'metacity-1:org.cinnamon.desktop.wm.preferences:theme:Windows-10-Dark' \
      'cinnamon:org.cinnamon.theme:name:Windows-10'; do
    IFS=: read -r theme_root schema key value <<< "$part"
    if [ -d "$HOME/.themes/$value/$theme_root" ] || [ -d "/usr/share/themes/$value/$theme_root" ]; then
      gsettings set "$schema" "$key" "$value" || echo "Could not select $value for $schema." >&2
    fi
  done
  wallpaper="$HOME/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png"
  if [ -f "$wallpaper" ]; then
    value=$(python3 - "$wallpaper" <<'PYURI'
from pathlib import Path
import sys
print(Path(sys.argv[1]).as_uri())
PYURI
)
    gsettings set org.cinnamon.desktop.background picture-uri "$value" || true
  fi
  gsettings set org.gnome.desktop.interface color-scheme prefer-dark || true
}

main() {
  set -euo pipefail
  local mode="${1:-all}"
  case "$mode" in all|--menu-only|--settings-only|--first-login) ;; *) echo 'Usage: apply-cinnamon-settings.sh [--menu-only|--settings-only|--first-login]' >&2; return 1 ;; esac
  if [ "$mode" = --first-login ]; then sleep 5; fi
  if [ "$mode" = all ] || [ "$mode" = --first-login ]; then
    if ! bash "$SETTINGS_SCRIPT_DIR/create-icon-theme-uni.sh"; then
      echo 'Qortal icon installation failed. Run create-icon-theme-uni.sh to retry.' >&2
      return 1
    fi
    gsettings set org.cinnamon.desktop.interface icon-theme Yaru-blue-qortal || true
  fi
  if [ "$mode" != --menu-only ]; then apply_desktop_themes; fi
  apply_menu_settings
  if [ "$mode" = --first-login ]; then
    rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/apply-cinnamon-settings.desktop"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

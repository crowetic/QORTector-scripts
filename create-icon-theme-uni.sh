#!/bin/bash

set -euo pipefail

for cmd in rsync curl unzip python3; do
  if ! command -v "$cmd" >/dev/null; then
    echo "[!] Required command '$cmd' is not installed. Please install it and re-run." >&2
    exit 1
  fi
done

# ImageMagick 7 uses magick; older distributions provide convert.
if command -v magick >/dev/null 2>&1; then
  IMAGE_CONVERTER=magick
elif command -v convert >/dev/null 2>&1; then
  IMAGE_CONVERTER=convert
else
  echo "[!] ImageMagick is required (magick or convert). Please install it and re-run." >&2
  exit 1
fi

ICON_SOURCE_DIR="${HOME}/Pictures/icons/icons_theme"
ICON_THEME_NAME="Yaru-blue-qortal"
ICON_CACHE_DIR="${HOME}/.icons/${ICON_THEME_NAME}"
TARGET_THEME_DIR="${ICON_CACHE_DIR}/48x48/apps"
HICOLOR_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/icons/hicolor"
ICON_NAMES=(qortal qortal-hub qortal-ui qortal-menu-button qortal-menu-button-2 qortal-menu-button-3 qortal-menu-button-4)
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/qortal-icons.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

have_icon_sources() {
  local source_dir="$1" name
  for name in "${ICON_NAMES[@]}"; do
    [ -s "${source_dir}/${name}.png" ] || return 1
  done
}

# A previous interrupted install may have created an empty or partial directory.
if ! have_icon_sources "$ICON_SOURCE_DIR"; then
  echo "🔽 Downloading the complete Qortal icon set..."
  sources=(
    "https://cloud.qortal.org/s/machinePicturesFolder/download"
    "https://cloud.crowetic.com/s/m9GZyy8k6n7NYJZ/download"
  )
  downloaded=false
  for url in "${sources[@]}"; do
    echo "🌐 Trying icon source: $url"
    # A successful HTTP response may still be an HTML error page or a bad ZIP.
    if curl --fail --location --show-error --connect-timeout 15 --max-time 180 --retry 2 \
        -o "$WORK_DIR/Pictures.zip" "$url" && \
        unzip -tq "$WORK_DIR/Pictures.zip" >/dev/null 2>&1; then
      mkdir -p "$WORK_DIR/extracted"
      if unzip -oq "$WORK_DIR/Pictures.zip" -d "$WORK_DIR/extracted" && \
          have_icon_sources "$WORK_DIR/extracted/Pictures/icons/icons_theme"; then
        mkdir -p "${HOME}/Pictures"
        # Merge directories, including into an existing Pictures/icons directory.
        if [ "${QORTAL_ICONS_PRESERVE_EXISTING:-0}" = 1 ]; then
          rsync -a --ignore-existing "$WORK_DIR/extracted/Pictures/" "${HOME}/Pictures/"
          for name in "${ICON_NAMES[@]}"; do
            if [ -f "$ICON_SOURCE_DIR/$name.png" ] && [ ! -L "$ICON_SOURCE_DIR/$name.png" ] && [ ! -s "$ICON_SOURCE_DIR/$name.png" ]; then
              cp -p "$WORK_DIR/extracted/Pictures/icons/icons_theme/$name.png" "$ICON_SOURCE_DIR/$name.png"
            fi
          done
        else
          rsync -a "$WORK_DIR/extracted/Pictures/" "${HOME}/Pictures/"
        fi
        downloaded=true
        break
      fi
      rm -rf "$WORK_DIR/extracted"
    fi
    echo "[!] Icon source did not provide a complete archive. Trying the next source." >&2
  done
  if [ "$downloaded" != true ] || ! have_icon_sources "$ICON_SOURCE_DIR"; then
    echo "[!] Could not obtain all seven Qortal icons. Re-run create-icon-theme-uni.sh to retry." >&2
    exit 1
  fi
fi

# Convert everything before changing the installed theme or selecting it.
mkdir -p "$WORK_DIR/rendered"
for name in "${ICON_NAMES[@]}"; do
  echo "[*] Preparing icon: $name"
  "$IMAGE_CONVERTER" "${ICON_SOURCE_DIR}/${name}.png" -resize 48x48 "$WORK_DIR/rendered/${name}.png"
  [ -s "$WORK_DIR/rendered/${name}.png" ]
done

# Inherit system artwork instead of copying an entire theme and its index.
# Dark Yaru variants have no app directory of their own; their inheritance
# supplies normal icons. Our own index must explicitly declare Qortal apps.
BASE_THEME=""
for candidate in Yaru-blue-dark Yaru-blue Yaru-dark Yaru breeze Adwaita; do
  if [ -f "/usr/share/icons/${candidate}/index.theme" ]; then
    BASE_THEME="$candidate"
    break
  fi
done
INHERITED_THEMES="${BASE_THEME:+${BASE_THEME},}hicolor"

mkdir -p "$TARGET_THEME_DIR" "$HICOLOR_DIR/48x48/apps"
python3 - "$ICON_CACHE_DIR/index.theme" "$ICON_THEME_NAME" "$INHERITED_THEMES" <<'PYINDEX'
import configparser
import io
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path

target, name, inherited = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
previous = target.read_text() if target.exists() else ''
parser = configparser.ConfigParser(interpolation=None, strict=False)
parser.optionxform = str
try:
    parser.read_string(previous)
except configparser.Error:
    parser.clear()
if os.environ.get('QORTAL_ICONS_PRESERVE_EXISTING') != '1':
    parser.clear()
if not parser.has_section('Icon Theme'):
    parser.add_section('Icon Theme')
theme = parser['Icon Theme']
theme.setdefault('Name', name)
theme.setdefault('Comment', 'Qortal application icons with system theme artwork')
directory_values = [theme.get('Directories', '')]
if os.environ.get('QORTAL_ICONS_PRESERVE_EXISTING') == '1':
    # Earlier helpers appended a second Directories key after a copied index.
    # Recover both lists so private icon directories remain reachable too.
    section = re.search(r'(?ms)^\[Icon Theme\]\s*\n(.*?)(?=^\[|\Z)', previous)
    if section:
        directory_values += re.findall(r'(?m)^Directories\s*=([^\n]*)', section[1])
directories = list(dict.fromkeys(d.strip() for value in directory_values for d in value.split(',') if d.strip()))
if '48x48/apps' not in directories:
    directories.append('48x48/apps')
theme['Directories'] = ','.join(directories)
parents = [d.strip() for d in theme.get('Inherits', inherited).split(',') if d.strip() and d.strip() not in (name, 'hicolor')]
for parent in inherited.split(','):
    if parent != 'hicolor' and parent not in parents:
        parents.append(parent)
parents.append('hicolor')
theme['Inherits'] = ','.join(parents)
if not parser.has_section('48x48/apps'):
    parser.add_section('48x48/apps')
parser['48x48/apps'].update(Size='48', Context='Applications', Type='Fixed')
out = io.StringIO()
parser.write(out, space_around_delimiters=False)
output = out.getvalue()
# Keep valid personal indexes byte-for-byte; repair old indexes that never
# declared the Qortal app directory, even during a preserve-existing rebuild.
if previous:
    old = configparser.ConfigParser(interpolation=None)
    old.optionxform = str
    try:
        old.read_string(previous)
        unchanged = {s: dict(old[s]) for s in old.sections()} == {s: dict(parser[s]) for s in parser.sections()}
    except configparser.Error:
        unchanged = False
    if unchanged:
        sys.exit(0)
    backup = Path(os.environ.get('REBUILT_MACHINE_BACKUP_DIR') or Path.home() / 'backups/qortal-icons')
    backup.mkdir(parents=True, exist_ok=True)
    shutil.copy2(target, backup / f'qortal-index-{time.time_ns()}.theme')
fd, tmp = tempfile.mkstemp(prefix='index.theme.', dir=target.parent)
try:
    with os.fdopen(fd, 'w') as out:
        out.write(output)
    os.chmod(tmp, 0o644)
    os.replace(tmp, target)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PYINDEX

for name in "${ICON_NAMES[@]}"; do
  if [ "${QORTAL_ICONS_PRESERVE_EXISTING:-0}" != 1 ] || [ ! -s "${TARGET_THEME_DIR}/${name}.png" ]; then
    install -m 644 "$WORK_DIR/rendered/${name}.png" "${TARGET_THEME_DIR}/${name}.png"
  fi
  # hicolor is the standard fallback in every desktop icon theme. These names
  # must resolve even when GNOME/Cinnamon keeps or later selects another theme.
  if [ "${QORTAL_ICONS_PRESERVE_EXISTING:-0}" != 1 ] || [ ! -s "$HICOLOR_DIR/48x48/apps/${name}.png" ]; then
    install -m 644 "$WORK_DIR/rendered/${name}.png" "$HICOLOR_DIR/48x48/apps/${name}.png"
  fi
done

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  for theme_dir in "$ICON_CACHE_DIR" "$HICOLOR_DIR"; do
    gtk-update-icon-cache -f -t "$theme_dir" || echo "[!] Could not refresh icon cache: $theme_dir" >&2
  done
fi
touch "$ICON_CACHE_DIR" "$HICOLOR_DIR"

# Desktop identifiers may contain multiple colon-separated names, e.g.
# ubuntu:GNOME, GNOME:GNOME-Classic, or X-Cinnamon.
CURRENT_DESKTOP=$(printf '%s' "${XDG_CURRENT_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')
set_gsettings_theme() {
  if ! command -v gsettings >/dev/null 2>&1 || \
      ! gsettings set "$1" icon-theme "$ICON_THEME_NAME"; then
    echo "[!] Could not select the custom theme for $1. Qortal icons are installed in hicolor." >&2
  fi
}

if [ "${QORTAL_ICONS_SELECT_THEME:-1}" = 1 ]; then
case "$CURRENT_DESKTOP" in
  *cinnamon*)
    set_gsettings_theme org.cinnamon.desktop.interface
    ;;
  *gnome* | *unity*)
    set_gsettings_theme org.gnome.desktop.interface
    ;;
  *xfce*)
    if command -v xfconf-query >/dev/null 2>&1; then
      xfconf-query -c xsettings -p /Net/IconThemeName -s "$ICON_THEME_NAME" || \
        echo "[!] Could not select the XFCE theme. Qortal icons are installed in hicolor." >&2
    fi
    ;;
  *plasma* | *kde*)
    if command -v kwriteconfig6 >/dev/null 2>&1; then
      kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ICON_THEME_NAME" || true
    elif command -v kwriteconfig5 >/dev/null 2>&1; then
      kwriteconfig5 --file kdeglobals --group Icons --key Theme "$ICON_THEME_NAME" || true
    fi
    if command -v qdbus >/dev/null 2>&1; then
      qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    fi
    ;;
  *)
    echo "ℹ️ No supported desktop session detected. Qortal icons are installed for the next login."
    ;;
esac
fi

echo "✅ All seven Qortal icons installed in ${ICON_THEME_NAME} and the hicolor fallback."
echo "ℹ️ If an existing panel still shows cached icons, log out and back in."

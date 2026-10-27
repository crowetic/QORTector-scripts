#!/bin/bash

set -euo pipefail

for cmd in rsync curl unzip; do
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
        rsync -a "$WORK_DIR/extracted/Pictures/" "${HOME}/Pictures/"
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
cat > "${ICON_CACHE_DIR}/index.theme" <<EOF
[Icon Theme]
Name=${ICON_THEME_NAME}
Comment=Qortal application icons with system theme artwork
Inherits=${INHERITED_THEMES}
Directories=48x48/apps

[48x48/apps]
Size=48
Context=Applications
Type=Fixed
EOF

for name in "${ICON_NAMES[@]}"; do
  install -m 644 "$WORK_DIR/rendered/${name}.png" "${TARGET_THEME_DIR}/${name}.png"
  # hicolor is the standard fallback in every desktop icon theme. These names
  # must resolve even when GNOME/Cinnamon keeps or later selects another theme.
  install -m 644 "$WORK_DIR/rendered/${name}.png" "$HICOLOR_DIR/48x48/apps/${name}.png"
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

echo "✅ All seven Qortal icons installed in ${ICON_THEME_NAME} and the hicolor fallback."
echo "ℹ️ If an existing panel still shows cached icons, log out and back in."

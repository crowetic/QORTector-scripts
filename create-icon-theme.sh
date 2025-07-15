#!/bin/bash

set -e

DEBUG=${DEBUG:-false}

log() {
  echo -e "$1"
}

debug() {
  if [ "$DEBUG" = true ]; then echo -e "[DEBUG] $1"; fi
}

# Dependencies
for cmd in rsync curl unzip convert; do
  if ! command -v $cmd &>/dev/null; then
    echo "[!] Required command '$cmd' is not installed."
    exit 1
  fi
done

# Detect icon install path
ICON_THEME_NAME="Yaru-blue-qortal"
ICON_SOURCE_DIR="${HOME}/Pictures/icons/icons_theme"
if [ -d "$HOME/.local/share/icons" ]; then
  USER_ICON_ROOT="$HOME/.local/share/icons"
else
  USER_ICON_ROOT="$HOME/.icons"
fi

ICON_CACHE_DIR="${USER_ICON_ROOT}/${ICON_THEME_NAME}"
TARGET_THEME_DIR="${ICON_CACHE_DIR}/48x48/apps"
mkdir -p "${TARGET_THEME_DIR}"

# Download icons if missing
if [ ! -d "${ICON_SOURCE_DIR}" ]; then
  log "📥 Downloading Qortal icons..."
  mkdir -p "${HOME}/iconTemp"
  trap 'rm -rf "${HOME}/iconTemp"' EXIT
  cd "${HOME}/iconTemp"
  curl -L -O https://cloud.qortal.org/s/machinePicturesFolder/download
  unzip download 
  mv Pictures/* "${HOME}/Pictures/"
  cd
fi

# Copy and modify base icon theme
if [ ! -d "${ICON_CACHE_DIR}" ]; then
  log "🎨 Creating theme '${ICON_THEME_NAME}' from Yaru-dark..."

  if [ -d /usr/share/icons/Yaru-dark ]; then
    rsync -a /usr/share/icons/Yaru-dark/ "${ICON_CACHE_DIR}/"
  else
    echo "[!] Yaru-dark not found. Cannot create icon theme."
    exit 1
  fi

  # Copy over index.theme
  if [ -f /usr/share/icons/Yaru-blue-dark/index.theme ]; then
    cp /usr/share/icons/Yaru-blue-dark/index.theme "${ICON_CACHE_DIR}/index.theme"
  elif [ ! -f "${ICON_CACHE_DIR}/index.theme" ]; then
    cat <<EOF > "${ICON_CACHE_DIR}/index.theme"
[Icon Theme]
Name=${ICON_THEME_NAME}
Comment=Qortal custom icons with Yaru base
Inherits=Yaru-dark,Yaru,hicolor
Directories=48x48/apps

[48x48/apps]
Size=48
Context=Applications
Type=Fixed
EOF
  fi

  sed -i "s/^Name=.*/Name=${ICON_THEME_NAME}/" "${ICON_CACHE_DIR}/index.theme"
  sed -i "s/^Inherits=.*/Inherits=Yaru-blue-dark,Yaru-dark,Yaru,hicolor/" "${ICON_CACHE_DIR}/index.theme"
fi

# Map and install icons
declare -A ICON_MAP=(
  ["qortal-menu-button.png"]="qortal-menu-button"
  ["qortal-menu-button-2.png"]="qortal-menu-button-2"
  ["qortal-menu-button-3.png"]="qortal-menu-button-3"
  ["qortal-menu-button-4.png"]="qortal-menu-button-4"
  ["qortal-ui.png"]="qortal-ui"
  ["qortal-hub.png"]="qortal-hub"
  ["qortal.png"]="qortal"
)

install_icon() {
  local src="$1"
  local name="$2"
  local dest="${TARGET_THEME_DIR}/${name}.png"

  if [ ! -f "$src" ]; then
    echo "[!] Icon not found: $src"
    return
  fi

  if command -v convert &>/dev/null; then
    convert "$src" -resize 48x48 "$dest"
    debug "Installed and resized $name to $dest"
  else
    cp "$src" "$dest"
    debug "Copied $name to $dest without resizing"
  fi
}

log "🧩 Installing icons..."
for src in "${!ICON_MAP[@]}"; do
  install_icon "${ICON_SOURCE_DIR}/${src}" "${ICON_MAP[$src]}"
done

# Update icon cache
if command -v gtk-update-icon-cache &>/dev/null && [ -f "${ICON_CACHE_DIR}/index.theme" ]; then
  gtk-update-icon-cache -f "${ICON_CACHE_DIR}" || true
fi

# Set icon theme based on DE
CURRENT_DE=$(echo "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}" | tr '[:upper:]' '[:lower:]')

log "🖥️ Detected Desktop Environment: $CURRENT_DE"

case "$CURRENT_DE" in
  cinnamon)
    gsettings set org.cinnamon.desktop.interface icon-theme "${ICON_THEME_NAME}" 2>/dev/null || true
    ;;
  gnome)
    gsettings set org.gnome.desktop.interface icon-theme "${ICON_THEME_NAME}" 2>/dev/null || true
    ;;
  mate)
    gsettings set org.mate.interface icon-theme "${ICON_THEME_NAME}" 2>/dev/null || true
    ;;
  xfce|xfce4)
    xfconf-query -c xsettings -p /Net/IconThemeName -s "${ICON_THEME_NAME}" 2>/dev/null || true
    ;;
  kde|plasma)
    kwriteconfig5 --file kdeglobals --group Icons --key Theme "${ICON_THEME_NAME}" 2>/dev/null || true
    ;;
  *)
    log "[ℹ️] Unknown or unsupported DE. Please set '${ICON_THEME_NAME}' manually in system settings."
    ;;
esac

log "✅ Qortal icons installed into theme '${ICON_THEME_NAME}'"
log "ℹ️ If icons don't appear immediately, restart your session or reapply theme."

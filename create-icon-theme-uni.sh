#!/bin/bash

set -euo pipefail

for cmd in rsync curl unzip convert; do
  if ! command -v "$cmd" >/dev/null; then
    echo "[!] Required command '$cmd' is not installed. Please install it and re-run."
    exit 1
  fi
done

ICON_SOURCE_DIR="${HOME}/Pictures/icons/icons_theme"
ICON_THEME_NAME="Yaru-blue-qortal"
ICON_CACHE_DIR="${HOME}/.icons/${ICON_THEME_NAME}"
TARGET_THEME_DIR="${ICON_CACHE_DIR}/48x48/apps"

# Download icons if missing
if [ ! -d "${ICON_SOURCE_DIR}" ]; then
  echo "🔽 Downloading Qortal icon set..."
  mkdir -p "${HOME}/iconTemp"
  trap 'rm -rf "${HOME}/iconTemp"' EXIT
  cd "${HOME}/iconTemp" || exit 1

  #TODO - UPDATE THESE DOWNLOAD LOCATIONS WITH QDN LOCATIONS (MOST LIKELY PUBLISHED AS A WEBSITE TO ALLOW DIRECT WGET DOWNLOADS)

  PRIMARY_URL="https://cloud.qortal.org/s/machinePicturesFolder/download" 
  BACKUP_URL="https://cloud.crowetic.com/s/m9GZyy8k6n7NYJZ/download"  

  echo "🌐 Trying primary source..."
  if curl -fL -o Pictures.zip "$PRIMARY_URL"; then
    echo "✅ Downloaded from primary."
  else
    echo "⚠️ Primary download failed. Trying backup source..."
    if curl -fL -o Pictures.zip "$BACKUP_URL"; then
      echo "✅ Downloaded from backup."
    else
      echo "❌ Both downloads failed. Aborting. ICON FILES FAILED TO DOWNLOAD, PLEASE RUN ./create-icon-theme-uni.sh LATER TO TRY AGAIN!"
      exit 1
    fi
  fi

  if unzip Pictures.zip; then
    echo "📂 Extracted icon archive."
    mv Pictures/* "${HOME}/Pictures/"
  else
    echo "❌ Failed to unzip icon archive. Aborting."
    exit 1
  fi

  cd || exit 1
fi


# Define icon mappings
declare -A ICON_MAP=(
  ["qortal-menu-button.png"]="qortal-menu-button"
  ["qortal-menu-button-2.png"]="qortal-menu-button-2"
  ["qortal-menu-button-3.png"]="qortal-menu-button-3"
  ["qortal-menu-button-4.png"]="qortal-menu-button-4"
  ["qortal-ui.png"]="qortal-ui"
  ["qortal-hub.png"]="qortal-hub"
  ["qortal.png"]="qortal"
)

# Step 1: Choose base theme
BASE_THEME_DIR=""
if [ -d "/usr/share/icons/Yaru-dark" ]; then
  BASE_THEME_DIR="/usr/share/icons/Yaru-dark"
  echo "[*] Using Yaru-dark as base."
else
  CURRENT_THEME=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
  if [ -n "$CURRENT_THEME" ] && [ -d "/usr/share/icons/$CURRENT_THEME" ]; then
    BASE_THEME_DIR="/usr/share/icons/$CURRENT_THEME"
    echo "[*] Falling back to current icon theme: $CURRENT_THEME"
  else
    echo "[!] Could not find Yaru-dark or current theme. Creating minimal fallback..."
    mkdir -p "${ICON_CACHE_DIR}/48x48/apps"
    cat <<EOF > "${ICON_CACHE_DIR}/index.theme"
[Icon Theme]
Name=${ICON_THEME_NAME}
Inherits=hicolor
Directories=48x48/apps

[48x48/apps]
Size=48
Context=Applications
Type=Fixed
EOF
  fi
fi

# Step 2: Copy base theme if found
if [ -n "$BASE_THEME_DIR" ] && [ ! -d "${ICON_CACHE_DIR}" ]; then
  echo "[*] Copying base theme from: $BASE_THEME_DIR"
  mkdir -p "${ICON_CACHE_DIR}"
  rsync -a "$BASE_THEME_DIR/" "${ICON_CACHE_DIR}/"

  if [ -f "/usr/share/icons/Yaru-blue-dark/index.theme" ]; then
    cp /usr/share/icons/Yaru-blue-dark/index.theme "${ICON_CACHE_DIR}/index.theme"
  fi

  sed -i 's/^Name=.*/Name=Yaru-blue-qortal/' "${ICON_CACHE_DIR}/index.theme"
  sed -i 's/^Inherits=.*/Inherits=Yaru-blue-dark,Yaru-dark,Yaru,hicolor/' "${ICON_CACHE_DIR}/index.theme"

  if ! grep -q "48x48/apps" "${ICON_CACHE_DIR}/index.theme"; then
    echo "Directories=48x48/apps" >> "${ICON_CACHE_DIR}/index.theme"
    echo "
[48x48/apps]
Size=48
Context=Applications
Type=Fixed" >> "${ICON_CACHE_DIR}/index.theme"
  fi
fi

# Step 3: Install icons
mkdir -p "${TARGET_THEME_DIR}"

install_icon() {
  local src="$1"
  local name="$2"
  local dest="${TARGET_THEME_DIR}/${name}.png"

  if [ ! -f "$src" ]; then
    echo "[!] Missing source icon: $src"
    return
  fi

  echo "[*] Installing icon: $name"
  convert "$src" -resize 48x48 "$dest"
}

for src in "${!ICON_MAP[@]}"; do
  install_icon "${ICON_SOURCE_DIR}/${src}" "${ICON_MAP[$src]}"
done

# Step 4: Update icon cache
if [ -f "${ICON_CACHE_DIR}/index.theme" ]; then
  gtk-update-icon-cache -f "${ICON_CACHE_DIR}" || echo "[!] gtk-update-icon-cache failed or not found."
fi

# Step 5: Set icon theme if DE supports it
CURRENT_DESKTOP=$(echo "${XDG_CURRENT_DESKTOP}" | tr '[:upper:]' '[:lower:]')

# Normalize aliases
case "$CURRENT_DESKTOP" in
  x-cinnamon) CURRENT_DESKTOP="cinnamon" ;;
  xfce*) CURRENT_DESKTOP="xfce" ;;
  kde-plasma) CURRENT_DESKTOP="plasma" ;;
esac

if command -v gsettings >/dev/null; then
  case "$CURRENT_DESKTOP" in
    cinnamon)
      gsettings set org.cinnamon.desktop.interface icon-theme "${ICON_THEME_NAME}"
      ;;
    gnome)
      gsettings set org.gnome.desktop.interface icon-theme "${ICON_THEME_NAME}"
      ;;
    xfce)
      xfconf-query -c xsettings -p /Net/IconThemeName -s "${ICON_THEME_NAME}" 2>/dev/null
      ;;
    kde | plasma)
      kwriteconfig5 --file kdeglobals --group Icons --key Theme "${ICON_THEME_NAME}"
      ;;
    *)
      echo "[!] Unsupported or unknown DE: '$CURRENT_DESKTOP'. Set icon theme manually if needed."
      ;;
  esac
else
  echo "[!] gsettings not available. Please set icon theme manually if needed."
fi


echo "✅ Qortal icons installed into local theme: ${ICON_THEME_NAME}"
echo "ℹ️  You can now use Icon=qortal-ui (etc.) in .desktop files."
echo "💡  If icons don't show up immediately, try logging out and back in."

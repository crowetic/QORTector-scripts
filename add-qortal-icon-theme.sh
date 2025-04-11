#!/bin/bash

# Customize Yaru-blue-dark icon theme locally and add Qortal icons
ICON_THEME_NAME="Yaru-blue-qortal"
ICON_SOURCE_DIR="${HOME}/Pictures/icons/icons_theme"
ICON_CACHE_DIR="${HOME}/.icons/${ICON_THEME_NAME}"
TARGET_THEME_DIR="${ICON_CACHE_DIR}/48x48/apps"

# Mapping of source icons to icon names
declare -A ICON_MAP=(
  ["qortal-menu-button.png"]="qortal-menu-button"
  ["qortal-menu-button-2.png"]="qortal-menu-button-2"
  ["qortal-menu-button-3.png"]="qortal-menu-button-3"
  ["qortal-menu-button-4.png"]="qortal-menu-button-4"
  ["qortal-ui.png"]="qortal-ui"
  ["qortal-hub.png"]="qortal-hub"
  ["qortal.png"]="qortal"
)

# Step 1: Copy system Yaru-dark theme as base
if [ ! -d "${ICON_CACHE_DIR}" ]; then
  echo "[*] Creating local copy of Yaru-dark theme as '${ICON_THEME_NAME}'..."
  mkdir -p "${ICON_CACHE_DIR}"
  rsync -a /usr/share/icons/Yaru-dark/ "${ICON_CACHE_DIR}/"

  # Copy index.theme from Yaru-blue-dark if it exists
  if [ -f /usr/share/icons/Yaru-blue-dark/index.theme ]; then
    cp /usr/share/icons/Yaru-blue-dark/index.theme "${ICON_CACHE_DIR}/index.theme"
  fi

  # Update index.theme metadata
  sed -i 's/^Name=.*/Name=Yaru-blue-qortal/' "${ICON_CACHE_DIR}/index.theme"
  sed -i 's/^Inherits=.*/Inherits=Yaru-blue-dark,Yaru-dark,Yaru,hicolor/' "${ICON_CACHE_DIR}/index.theme"

  # Ensure Directories includes 48x48/apps
  if ! grep -q "48x48/apps" "${ICON_CACHE_DIR}/index.theme"; then
    echo "Directories=48x48/apps" >> "${ICON_CACHE_DIR}/index.theme"
    echo "
[48x48/apps]
Size=48
Context=Applications
Type=Fixed" >> "${ICON_CACHE_DIR}/index.theme"
  fi
fi

# Step 2: Ensure target icon directory exists
mkdir -p "${TARGET_THEME_DIR}"

# Step 3: Install icons (resized if possible)
install_icon() {
  local src="$1"
  local name="$2"
  local dest="${TARGET_THEME_DIR}/${name}.png"

  if [ ! -f "$src" ]; then
    echo "[!] Source icon not found: $src"
    return
  fi

  if command -v convert &>/dev/null; then
    echo "[*] Resizing and installing $name to ${TARGET_THEME_DIR}"
    convert "$src" -resize 48x48 "$dest"
  else
    echo "[*] Copying $name without resizing to ${TARGET_THEME_DIR}"
    cp "$src" "$dest"
  fi
}

# Step 4: Loop through and install icons
for src in "${!ICON_MAP[@]}"; do
  install_icon "${ICON_SOURCE_DIR}/${src}" "${ICON_MAP[$src]}"
done

# Step 5: Update the icon cache
if [ -f "${ICON_CACHE_DIR}/index.theme" ]; then
  echo "[*] Updating icon cache for '${ICON_THEME_NAME}'..."
  gtk-update-icon-cache -f "${ICON_CACHE_DIR}" || echo "[!] gtk-update-icon-cache failed or not found."
else
  echo "[!] No index.theme file found. Cannot update icon cache."
fi

# Step 6: Set as active icon theme
echo "[*] Setting '${ICON_THEME_NAME}' as the current icon theme..."
gsettings set org.cinnamon.desktop.interface icon-theme "${ICON_THEME_NAME}"

echo "✅ Qortal icons installed into local theme: ${ICON_THEME_NAME}"
echo "   You can now use Icon=qortal-ui (etc.) in .desktop files."
echo "   Theme is now active with blue-dark base styling."


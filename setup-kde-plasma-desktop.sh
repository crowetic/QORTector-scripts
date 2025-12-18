#!/bin/bash
set -euo pipefail

# ===========================
#  Colors
# ===========================
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m'

username=$(whoami)

echo -e "${YELLOW}🖥  KDE PLASMA DESKTOP SETUP FOR USER: ${username}${NC}\n"

# ===========================
#  OPTIONAL: Install KDE Plasma
# ===========================
echo -e "${YELLOW}📦 Installing KDE Plasma meta-packages (comment this out if your image already has Plasma)...${NC}\n"

sudo apt update
# kde-standard gives you a sane default KDE desktop without insane bloat.
sudo apt -y install kde-standard konsole dolphin plasma-discover

echo -e "${GREEN}✅ KDE Plasma packages installed (or already present).${NC}\n"

# ===========================
#  Set Plasma as default session
# ===========================
echo -e "${YELLOW}⚙️  Setting KDE Plasma as default desktop session for this user...${NC}\n"

# For GDM/LightDM, .dmrc + .xsession usually work
cat > "${HOME}/.dmrc" <<EOL
[Desktop]
Session=plasma
EOL

echo "plasma" > "${HOME}/.xsession"

chmod 600 "${HOME}/.dmrc"
chmod +x "${HOME}/.xsession" || true

echo -e "${GREEN}✅ Plasma will be the default session on next login (select it once if needed).${NC}\n"

# ===========================
#  Qortal Icon Theme (your unified script)
# ===========================
echo -e "${YELLOW}🎨 Applying Qortal icon theme (Yaru-blue-qortal)...${NC}\n"

# Expect createIconThemeUni.sh to live in $HOME or current directory.
# Adjust path if you keep it somewhere else.
if [ -x "${HOME}/createIconThemeUni.sh" ]; then
  bash "${HOME}/createIconThemeUni.sh"
elif [ -x "./createIconThemeUni.sh" ]; then
  bash "./createIconThemeUni.sh"
else
  echo -e "${RED}⚠️ createIconThemeUni.sh not found. Skipping icon theme creation.${NC}"
  echo -e "${YELLOW}   Place it in \$HOME or same dir as this script and re-run to apply icons.${NC}"
fi

# Force KDE to use that theme even if the script didn’t detect Plasma yet
kwriteconfig5 --file kdeglobals --group Icons --key Theme "Yaru-blue-qortal" || true

echo -e "${GREEN}✅ KDE icon theme set to Yaru-blue-qortal (where available).${NC}\n"

# ===========================
#  Base KDE look & feel
# ===========================
echo -e "${YELLOW}🎨 Applying base KDE look-and-feel (Breeze Dark)...${NC}\n"

# This is safe to fail if lookandfeeltool isn't there yet
lookandfeeltool -a org.kde.breezedark.desktop 2>/dev/null || \
lookandfeeltool -a org.kde.breeze.dark 2>/dev/null || true

# You can later swap this for a Windows-10 lookalike L&F if you want
# e.g. after you import a global theme from KDE Store.

echo -e "${GREEN}✅ Base KDE dark theme applied (or best-effort).${NC}\n"

# ===========================
#  Wallpaper
# ===========================
WALLPAPER_PATH="${HOME}/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png"

if [ -f "${WALLPAPER_PATH}" ]; then
  echo -e "${YELLOW}🖼  Setting Plasma wallpaper to your Qortal wallpaper...${NC}\n"

  # Use plasmashell's scripting API via qdbus
  qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
var allDesktops = desktops();
for (var i = 0; i < allDesktops.length; i++) {
  var d = allDesktops[i];
  d.wallpaperPlugin = 'org.kde.image';
  d.currentConfigGroup = Array('Wallpaper', 'org.kde.image', 'General');
  d.writeConfig('Image', 'file://${WALLPAPER_PATH}');
}
" 2>/dev/null || true

  echo -e "${GREEN}✅ Wallpaper applied (or best-effort, depending on session).${NC}\n"
else
  echo -e "${RED}⚠️ Wallpaper not found at: ${WALLPAPER_PATH}${NC}"
  echo -e "${YELLOW}   Place your Qortal wallpaper there and re-run this script to set it.${NC}\n"
fi

# ===========================
#  Qortal menu category + launchers
# ===========================
echo -e "${YELLOW}📂 Creating Qortal application category and launchers...${NC}\n"

# XDG Applications category for Qortal
mkdir -p "${HOME}/.local/share/desktop-directories"

cat > "${HOME}/.local/share/desktop-directories/Qortal.directory" <<EOL
[Desktop Entry]
Name=Qortal
Comment=Qortal Applications
Icon=qortal-menu-button-3
Type=Directory
EOL

# Application launchers
mkdir -p "${HOME}/.local/share/applications"

# Qortal Hub launcher
cat > "${HOME}/.local/share/applications/qortal-hub.desktop" <<EOL
[Desktop Entry]
Name=Qortal Hub
Comment=Launch Qortal Hub
Exec=/home/${username}/qortal/Qortal-Hub
Icon=qortal-hub
Terminal=false
Type=Application
Categories=Qortal;Network;
EOL

# If you *ever* bring back Qortal-UI or another app, you can uncomment/extend this:
# cat > "${HOME}/.local/share/applications/qortal-ui.desktop" <<EOL
# [Desktop Entry]
# Name=Qortal UI
# Comment=Launch Qortal User Interface
# Exec=/home/${username}/qortal/Qortal-UI
# Icon=qortal-ui
# Terminal=false
# Type=Application
# Categories=Qortal;Network;
# EOL

# Make sure KDE sees the new stuff
kbuildsycoca5 > /dev/null 2>&1 || true

echo -e "${GREEN}✅ Qortal menu category and launchers installed.${NC}\n"

# ===========================
#  Autostart entries for Qortal Core (optional)
# ===========================
echo -e "${YELLOW}🚀 Creating optional KDE autostart entries for Qortal Core (visible + silent)...${NC}\n"

mkdir -p "${HOME}/.config/autostart"

cat > "${HOME}/.config/autostart/start-qortal-core.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=${HOME}/start-qortal-core.sh
X-GNOME-Autostart-enabled=true
Name=Start Qortal Core
Comment=Start Qortal Core a few seconds after login
X-GNOME-Autostart-Delay=6
EOL

cat > "${HOME}/.config/autostart/auto-fix-qortal.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=${HOME}/auto-fix-qortal.sh
X-GNOME-Autostart-enabled=true
Name=Auto-fix Qortal
Comment=Run Qortal auto-fix script after login
X-GNOME-Autostart-Delay=420
EOL

echo -e "${GREEN}✅ Autostart entries created (they'll also show in KDE's System Settings → Startup & Shutdown).${NC}\n"

# ===========================
#  Done
# ===========================
echo -e "${GREEN}🎉 KDE Plasma desktop configuration complete!${NC}"
echo -e "${YELLOW}➡ Log out, select 'Plasma' on the login screen if needed, and log back in to enjoy the new setup.${NC}"

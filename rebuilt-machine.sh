#!/bin/bash

# Regular Colors
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

echo -e "${YELLOW} UPDATING UBUNTU AND INSTALLING REQUIRED SOFTWARE PACKAGES ${NC}\n"

echo -e "${YELLOW} creating system folders that require admin permissions..."

sudo mkdir -p /usr/share/desktop-directories

sudo tee /usr/share/desktop-directories/qortal.directory > /dev/null <<EOL
[Desktop Entry]
Name=Qortal
Comment=Qortal Applications
Icon=qortal-logo
Type=Directory
EOL

sudo apt update
sudo apt -y --purge remove ubuntu-advantage-tools ubuntu-pro-client*
sudo apt -y upgrade
sudo apt -y install git jq gnome-software unzip vim curl openjdk-21-jre zlib1g-dev vlc chromium-browser p7zip-full libfuse2 htop net-tools bpytop ffmpeg sysbench smartmontools ksnip xsensors fonts-symbola lm-sensors cinnamon-desktop-environment

### SET DEFAULT SESSION TO CINNAMON ###
echo -e "${YELLOW} SETTING CINNAMON AS DEFAULT DESKTOP SESSION ${NC}\n"

# Works for most LightDM and GDM-based setups
echo "cinnamon" > "${HOME}/.xsession"
chmod +x "${HOME}/.xsession"

cat > "${HOME}/.dmrc" <<EOL
[Desktop]
Session=cinnamon
EOL

echo -e "${GREEN} Cinnamon session will be loaded by default on next login! ${NC}\n"

### DOWNLOAD & INSTALL QORTAL CORE ###
echo -e "${YELLOW} DOWNLOADING QORTAL CORE AND QORT SCRIPT ${NC}\n"

cd "${HOME}"
mkdir -p backups

if [ -d qortal ]; then
  echo -e "${PURPLE} qortal DIRECTORY FOUND, BACKING UP ORIGINAL TO '~/backups' AND RE-INSTALLING ${NC}\n"
  mv qortal "backups/qortal-$(date +%s)"
fi

curl -L -O https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
unzip qortal*.zip
rm qortal*.zip
cd qortal
rm -f settings.json
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/settings.json
curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/tools/qort
chmod +x *.sh qort

cd "${HOME}"

### INSTALL QORTAL UI & HUB ###
cd qortal

if [ "$(uname -m)" = "aarch64" ]; then
    echo "${GREEN} ARM 64-bit detected. Downloading ARM64 Qortal Hub and UI ${NC}"
    curl -L -O https://github.com/Qortal/Qortal-Hub/releases/download/v0.5.3/Qortal-Hub-arm64_0.5.3.AppImage
    curl -L -O https://github.com/Qortal/qortal-ui/releases/download/v4.6.1/Qortal-Setup-arm64.AppImage
    mv Qortal-Hub-arm64* Qortal-Hub
    mv Qortal-Setup-arm64* Qortal-UI
else
    curl -L -O https://github.com/Qortal/Qortal-Hub/releases/download/v0.5.3/Qortal-Hub_0.5.3.AppImage
    curl -L -O https://github.com/Qortal/qortal-ui/releases/latest/download/Qortal-Setup-amd64.AppImage
    mv Qortal-Hub* Qortal-Hub
    mv Qortal-Setup* Qortal-UI
fi

chmod +x Qortal-UI Qortal-Hub

### DOWNLOAD EXTRA FILES ###
cd "${HOME}"
curl -L -O https://cloud.qortal.org/s/machine_files/download
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal-core.sh

chmod +x *.sh
unzip download
rsync -raPz Machine-files/* "${HOME}"
rm -rf Machine-files download
mkdir -p "${HOME}/.icons/qortal"

mv "${HOME}/Pictures/icons/blue-grey-menu-button.png" "${HOME}/.icons/qortal/qortal-menu-button.png"
mv "${HOME}/Pictures/icons/QLogo_512.png" "${HOME}/.icons/qortal/qortal-logo.png"
mv "${HOME}/Pictures/icons/qortal-ui.png" "${HOME}/.icons/qortal/qortal-ui.png"
mv "${HOME}/Pictures/icons/qortal-hub-app-logo.png" "${HOME}/.icons/qortal/qortal-hub.png"

rsync -raPz "${HOME}/.icons/qortal/" "${HOME}/Pictures/icons/"

### CINNAMON THEMING - ALWAYS APPLIES EVEN IF CINNAMON ISN'T ACTIVE ###
echo -e "${YELLOW} INSTALLING WINDOWS 10 THEMES FOR CINNAMON ${NC}\n"

mkdir -p "${HOME}/.themes"

# Avoid cloning twice
[ ! -d "${HOME}/.themes/Windows-10" ] && git clone https://github.com/B00merang-Project/Windows-10.git "${HOME}/.themes/Windows-10"
[ ! -d "${HOME}/.themes/Windows-10-Dark" ] && git clone https://github.com/B00merang-Project/Windows-10-Dark.git "${HOME}/.themes/Windows-10-Dark"
[ ! -d "${HOME}/.icons/Flatery" ] && git clone https://github.com/cbrnix/Flatery.git "${HOME}/.icons/Flatery"

### APPLY THEMES (WILL WORK AFTER REBOOT TOO) ###
echo -e "${YELLOW} APPLYING CINNAMON THEMES ${NC}\n"

gsettings set org.cinnamon.desktop.wm.preferences theme "Windows-10-Dark" || true
gsettings set org.cinnamon.desktop.interface gtk-theme "Windows-10-Basic" || true
gsettings set org.cinnamon.theme name "Windows-10" || true
gsettings set org.cinnamon.desktop.background picture-uri "file://${HOME}/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png" || true
gsettings set org.cinnamon.desktop.interface icon-theme "Flatery" || true

### CINNAMON PANEL + MENU CUSTOMIZATION ###
echo -e "${YELLOW} CONFIGURING CINNAMON PANEL AND MENU ${NC}\n"

# Custom icon and label
gsettings set org.cinnamon.menu-use-custom-icon true
gsettings set org.cinnamon.menu.use-custom-label true
gsettings set org.cinnamon menu-icon-name "qortal-menu-button.png"
gsettings set org.cinnamon menu-text "ortal-OS"
gsettings set org.cinnamon menu-icon-size 42

# Menu layout and content
gsettings set org.cinnamon.menu.use-custom-menu-size false
gsettings set org.cinnamon.menu.show-category-icons true
gsettings set org.cinnamon.menu.category-icon-size 34
gsettings set org.cinnamon.menu.show-application-icons true
gsettings set org.cinnamon.menu.application-icon-size 24
gsettings set org.cinnamon.menu.show-favorites true
gsettings set org.cinnamon.menu.favorites-icon-size 42
gsettings set org.cinnamon.menu.show-places true
gsettings set org.cinnamon.menu.show-recent-files false

# Menu behavior
gsettings set org.cinnamon.menu.hover-switch true
gsettings set org.cinnamon.menu.enable-autoscroll true
gsettings set org.cinnamon.menu.enable-path-entry false


### ADD DESKTOP SHORTCUTS ###
echo -e "${YELLOW} CREATING DESKTOP LAUNCHERS ${NC}\n"

mkdir -p "${HOME}/.local/share/desktop-directories"

cat > "${HOME}/.local/share/desktop-directories/qortal.directory" <<EOL
[Desktop Entry]
Name=Qortal
Comment=Qortal Applications
Icon=qortal-logo
Type=Directory
EOL


mkdir -p "${HOME}/.local/share/applications"

cat > "${HOME}/.local/share/applications/qortal-ui.desktop" <<EOL
[Desktop Entry]
Name=Qortal UI
Comment=Launch Qortal User Interface
Exec=/home/${username}/qortal/Qortal-UI
Icon=qortal-ui
Terminal=false
Type=Application
Categories=Qortal;
EOL

cat > "${HOME}/.local/share/applications/qortal-hub.desktop" <<EOL
[Desktop Entry]
Name=Qortal Hub
Comment=Launch Qortal Hub
Exec=/home/${username}/qortal/Qortal-Hub
Icon=qortal-hub
Terminal=false
Type=Application
Categories=Qortal;
EOL


### CRONTAB SETUP ###
echo -e "${YELLOW} SETTING CRONTAB TASKS ${NC}\n"

{
  echo "@reboot sleep 399 && ${HOME}/auto-fix-qortal.sh > \"${HOME}/qortal/auto-fix-startup.log\" 2>&1"
  echo "@reboot ${HOME}/start-qortal-core.sh"
  echo "1 1 */3 * * ${HOME}/auto-fix-qortal.sh > \"${HOME}/qortal/auto-fix-01.log\" 2>&1"
} > rebuilt-machine-cron

crontab rebuilt-machine-cron
rm -f rebuilt-machine-cron

echo -e "${YELLOW} Refreshing Cinnamon Panel/Menu to apply changes ${NC}"
cinnamon --replace > /dev/null 2>&1 &

echo -e "${GREEN} SETUP COMPLETE! CINNAMON WILL BE USED ON NEXT LOGIN. REBOOTING IN 30 SECONDS (use cntrl+c to CANCEL reboot within next 30 seconds if you do not want to reboot now...)${NC}\n"
sleep 10
echo -e "${YELLOW}20 seconds remaining...\n"
sleep 9 
echo -e "10 Seconds remaining...\n"
sleep 4
echo -e "5 seconds remaining...${NC}\n"
sleep 3 
echo "${GREEN} REBOOTING MACHINE NOW!${NC}\n"
sudo reboot

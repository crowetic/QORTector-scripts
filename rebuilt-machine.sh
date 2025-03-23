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

sudo apt update
sudo apt -y --purge remove ubuntu-advantage-tools ubuntu-pro-client*
sudo apt -y upgrade
sudo apt -y install git jq tela-icon-theme gnome-software unzip vim curl openjdk-21-jre zlib1g-dev vlc chromium-browser p7zip-full libfuse2 htop net-tools bpytop ffmpeg sysbench smartmontools ksnip xsensors fonts-symbola lm-sensors cinnamon-desktop-environment

### SET DEFAULT SESSION TO CINNAMON ###
echo -e "${YELLOW} SETTING CINNAMON AS DEFAULT DESKTOP SESSION ${NC}\n"

# Works for most LightDM or .xsession-compatible setups
echo "cinnamon" > ~/.xsession
chmod +x ~/.xsession

# Optional fallback for LightDM users
cat > ~/.dmrc <<EOL
[Desktop]
Session=cinnamon
EOL

echo -e "${GREEN} Cinnamon session has been set as default! ${NC}\n"

### DOWNLOAD & INSTALL QORTAL CORE ###
echo -e "${YELLOW} DOWNLOADING QORTAL CORE AND QORT SCRIPT ${NC}\n"

cd ~
mkdir -p backups

if [ -d qortal ]; then
  echo -e "${PURPLE} qortal DIRECTORY FOUND, BACKING UP ORIGINAL TO '~/backups' AND RE-INSTALLING ${NC}\n"
  mv qortal backups/qortal-$(date +%s)
fi

curl -L -O https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
unzip qortal*.zip
rm qortal*.zip
cd qortal
rm -f settings.json
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/settings.json
curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/tools/qort
chmod +x *.sh qort

cd ~

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
cd ~
curl -L -O https://cloud.qortal.org/s/machine_files/download
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal-core.sh

chmod +x *.sh
unzip download
rsync -raPz Machine-files/* ${HOME}
rm -rf Machine-files download

### CINNAMON DETECTION & THEMING ###
if [ "$XDG_CURRENT_DESKTOP" = "X-Cinnamon" ] || [ -d "/usr/share/cinnamon" ]; then
  echo -e "${YELLOW} CINNAMON DETECTED - INSTALLING WINDOWS 10 THEMES ${NC}\n"

  mkdir -p ${HOME}/.themes
  git clone https://github.com/B00merang-Project/Windows-10.git ~/.themes/Windows-10
  git clone https://github.com/B00merang-Project/Windows-10-Dark.git ~/.themes/Windows-10-Dark

  echo -e "${YELLOW} APPLYING CINNAMON THEMES TO MATCH WINDOWS 10 ${NC}\n"
  gsettings set org.cinnamon.desktop.wm.preferences theme "Windows-10-Dark"
  gsettings set org.cinnamon.desktop.interface gtk-theme "Windows-10-Basic"
  gsettings set org.cinnamon.theme name "Windows-10"
  gsettings set org.cinnamon.desktop.background picture-uri "file://${HOME}/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png"
  gsettings set org.cinnamon.desktop.interface icon-theme "Tela-dark"
else
  echo -e "${RED} Cinnamon not detected, skipping Cinnamon theming. ${NC}"
fi

### ADD DESKTOP SHORTCUTS ###
echo -e "${YELLOW} CREATING DESKTOP LAUNCHERS FOR QORTAL APPLICATIONS ${NC}\n"

mkdir -p ~/.local/share/applications

cat > ~/.local/share/applications/qortal-ui.desktop <<EOL
[Desktop Entry]
Name=Qortal UI
Comment=Launch Qortal User Interface
Exec=/home/${username}/qortal/Qortal-UI
Icon=/home/${username}/Pictures/qortal-ui.png
Terminal=false
Type=Application
Categories=Qortal;
EOL

cat > ~/.local/share/applications/qortal-hub.desktop <<EOL
[Desktop Entry]
Name=Qortal Hub
Comment=Launch Qortal Hub
Exec=/home/${username}/qortal/Qortal-Hub
Icon=/home/${username}/Pictures/qortal-hub-app-logo.png
Terminal=false
Type=Application
Categories=Qortal;
EOL

### CRONTAB SETUP ###
echo -e "${YELLOW} FINISHING UP ${NC}\n"

{
  echo "@reboot sleep 399 && /home/${username}/auto-fix-qortal.sh > \"/home/${username}/qortal/auto-fix-startup.log\" 2>&1"
  echo "@reboot /home/${username}/start-qortal-core.sh"
  echo "1 1 */3 * * /home/${username}/auto-fix-qortal.sh > \"/home/${username}/qortal/auto-fix-01.log\" 2>&1"
} > rebuilt-machine-cron

crontab rebuilt-machine-cron
rm -f rebuilt-machine-cron

echo -e "${YELLOW} CINNAMON SET AS DEFAULT - MACHINE WILL REBOOT IN 10 SECONDS ${NC}\n"
sleep 10
sudo reboot

#!/bin/sh

# Regular Colors
BLACK='\033[0;30m'        # Black
RED='\033[0;31m'          # Red
GREEN='\033[0;32m'        # Green
YELLOW='\033[0;33m'       # Yellow
BLUE='\033[0;34m'         # Blue
PURPLE='\033[0;35m'       # Purple
CYAN='\033[0;36m'         # Cyan
WHITE='\033[0;37m'        # White
NC='\033[0m'              # No Color

echo "${YELLOW} UPDATING UBUNTU AND INSTALLING REQUIRED SOFTWARE PACKAGES ${NC}\n" 

sudo apt update 
# TODO - check if the system is ubuntu, if so then remove the bullshit ubuntu-advantage-tools, then re-install gnome-software - for now, just purge it and install gnome-software assuming it's an ubuntu-compatible distro.
sudo apt -y --purge remove ubuntu-advantage-tools ubuntu-pro-client*
sudo apt -y upgrade
sudo apt -y install gnome-software unzip vim curl openjdk-21-jre zlib1g-dev vlc chromium-browser p7zip-full libfuse2 htop net-tools bpytop ffmpeg sysbench smartmontools ksnip xsensors fonts-symbola lm-sensors cinnamon-desktop-environment

echo "${YELLOW} DOWNLOADING QORTAL CORE AND QORT SCRIPT ${NC}\n"

cd 
if [ -d qortal ]; then
  echo "${PURPLE} qortal DIRECTORY FOUND, BACKING UP ORIGINAL TO '~/backups' AND RE-INSTALLING ${NC}\n"
  mkdir -p backups
  mv qortal backups/
fi
curl -L -O https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
unzip qortal*.zip
rm qortal*.zip
cd qortal
rm settings.json
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/settings.json
chmod +x *.sh
curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/tools/qort
chmod +x qort

cd 

if [ -f qortal/Qortal-UI ]; then
  echo "${PURPLE} PREVIOUS Qortal-UI FOUND, BACKING UP ORIGINAL TO '~/backups/' AND RE-INSTALLING ${NC}\n"
  mv qortal/Qortal-UI ~/backups/
fi 

cd qortal

if [ "$(uname -m)" = "aarch64" ]; then
    echo "ARM 64-bit detected"
    echo "Downloading 64bit arm-based UI and Qortal Hub"
    curl -L -O https://github.com/Qortal/Qortal-Hub/releases/download/v0.5.3/Qortal-Hub-arm64_0.5.3.AppImage
    curl -L -O https://github.com/Qortal/qortal-ui/releases/download/v4.6.1/Qortal-Setup-arm64.AppImage
    chmod +x *.AppImage
    mv Qortal-Hub-arm64* Qortal-Hub
    mv Qortal-Setup-arm64* Qortal-UI
fi

curl -L -O https://github.com/Qortal/Qortal-Hub/releases/download/v0.5.3/Qortal-Hub_0.5.3.AppImage
curl -L -O https://github.com/Qortal/qortal-ui/releases/latest/download/Qortal-Setup-amd64.AppImage
mv Qortal-Setup*.AppImage Qortal-UI
mv Qortal-Hub*.AppImage Qortal-Hub
chmod +x Qortal-UI
chmod +x Qortal-Hub

echo "${YELLOW} DOWNLOADING PICTURE FILES AND OTHER SCRIPTS ${NC}\n"

cd

#curl -L -O https://cloud.qortal.org/s/t4Fy8Lp4kQYiYZN/download/Machine-files.zip
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

echo "${YELLOW} FINISHING UP ${NC}\n"

username=$(whoami)
echo "@reboot sleep 399 && ./auto-fix-qortal.sh > \"/home/${username}/qortal/auto-fix-startup.log\" 2>&1" >> "rebuilt-machine-cron"
echo "@reboot ./start-qortal-core.sh" >> "rebuilt-machine-cron"
echo "1 1 */3 * * /home/$(whoami)/auto-fix-qortal.sh > \"/home/${username}/qortal/auto-fix-01.log\" 2>&1" >> "rebuilt-machine-cron"
chmod +x *.sh

crontab rebuilt-machine-cron

rm -rf rebuilt-machine-cron

echo "${YELLOW} REBOOTING MACHINE IN 10 SECONDS - USE CINNAMON DESKTOP ENVIRONMENT UPON REBOOT BY CLICKING LOGIN NAME THEN SETTINGS ICON AT BOTTOM RIGHT, AND CHANGING TO CINNAMON ${NC}\n" 

sleep 10 

sudo reboot



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
sudo apt -y --purge remove ubuntu-advantage-tools
sudo apt -y upgrade
sudo apt -y install gnome-software unzip vim curl openjdk-17-jre zlib1g-dev libz.so vlc chromium-browser p7zip-full libfuse2 htop net-tools bpytop ffmpeg sysbench smartmontools ksnip xsensors fonts-symbola lm-sensors

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
curl -L -O https://github.com/Qortal/qortal-ui/releases/latest/download/Qortal-Setup-amd64.AppImage
mv Qortal-Setup*.AppImage Qortal-UI
chmod +x Qortal-UI

echo "${YELLOW} DOWNLOADING PICTURE FILES AND OTHER SCRIPTS ${NC}\n"

cd

curl -L -O https://cloud.qortal.org/s/t4Fy8Lp4kQYiYZN/download/Machine-files.zip
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh

chmod +x *.sh

curl -L -O https://cloud.qortal.org/s/6d8qoEkQRDSCTqn/download/rebuilt-machine-setup.txt
mv rebuilt-machine-setup.txt ~/Desktop
if [ -d ~/Pictures/wallpapers ]; then
  echo "${PURPLE} PREVIOUS wallpapers folder FOUND, BACKING UP ORIGINAL TO '~/backups/' AND RE-INSTALLING ${NC}\n"
  mkdir -p ~/backups
  mv ~/Pictures/wallpapers ~/backups
fi
if [ -d ~/Pictures/icons ]; then
  echo "${PURPLE} PREVIOUS icons folder FOUND, BACKING UP ORIGINAL TO '~/backups/' AND RE-INSTALLING ${NC}\n"
  mkdir -p ~/backups
  mv ~/Pictures/icons ~/backups
fi

unzip Machine-files.zip

mv Machine-files/Pictures ~/

echo "${YELLOW} FINISHING UP ${NC}\n"

username=$(whoami)
echo "@reboot sleep 399 && /home/${username}/auto-fix-qortal.sh > \"/home/${username}/qortal/auto-fix-startup.log\" 2>&1" >> "rebuilt-machine-cron"
echo "1 1 */3 * * /home/${username}/auto-fix-qortal.sh > \"/home/${username}/qortal/auto-fix-01.log\" 2>&1" >> "rebuilt-machine-cron"
chmod +x *.sh

crontab rebuilt-machine-cron

rm -rf Machine-files Machine-files.zip rebuilt-machine-cron

echo "${YELLOW} REBOOTING MACHINE IN 10 SECONDS - USE CINNAMON DESKTOP ENVIRONMENT UPON REBOOT BY CLICKING LOGIN NAME THEN SETTINGS ICON AT BOTTOM RIGHT, AND CHANGING TO CINNAMON ${NC}\n" 

sleep 10 

sudo reboot



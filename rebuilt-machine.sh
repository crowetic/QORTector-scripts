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
sudo apt -y upgrade
sudo apt -y install unzip vim curl default-jre cinnamon-desktop-environment vlc chromium-browser p7zip-full libfuse2 htop net-tools bpytop ffmpeg sysbench smartmontools ksnip

echo "${YELLOW} DOWNLOADING QORTAL CORE AND QORT SCRIPT ${NC}\n"

curl -L -O https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
unzip qortal*.zip
rm qortal*.zip
cd qortal
rm settings.json
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/settings.json
chmod +x *.sh
curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/tools/qort
chmod +x qort


echo "${YELLOW} DOWNLOADING QORTAL UI AppImage AND RENAMING ${NC}\n"

cd 
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
mv check-qortal-status.sh ~/qortal

unzip Machine-files.zip

mv Machine-files/Pictures/*.* ~/Pictures/


curl -L -O https://cloud.qortal.org/s/8z4sRiwJCPqM4Fi/download/Qortal-TheFuture-Wallpaper.png
mv Qortal-The*.png ~/Pictures/


curl -L -O https://cloud.qortal.org/s/6d8qoEkQRDSCTqn/download/rebuilt-machine-setup.txt
mv rebuilt-machine-setup.txt ~/Desktop

mkdir -p ~/Pictures/wallpapers
mkdir -p ~/Pictures/icons
mv ~/Pictures/wallpaper*.jpeg ~/Pictures/wallpapers
mv ~/Pictures/Qortal-The*.png ~/Pictures/wallpapers
mv ~/Pictures/*.* ~/Pictures/icons


echo "${YELLOW} FINISHING UP ${NC}\n"

chmod +x *.sh

curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/rebuilt-machine-cron
crontab rebuilt-machine-cron

rm -rf Machine-files Machine-files.zip rebuilt-machine-cron


echo "${YELLOW} REBOOTING MACHINE IN 10 SECONDS - USE CINNAMON DESKTOP ENVIRONMENT UPON REBOOT BY CLICKING LOGIN NAME THEN SETTINGS ICON AT BOTTOM RIGHT, AND CHANGING TO CINNAMON ${NC}\n" 

sleep 10 

sudo reboot



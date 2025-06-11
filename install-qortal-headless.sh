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

echo "${YELLOW} UPDATING AND INSTALLING REQUIRED SOFTWARE PACKAGES ${NC}\n" 

sudo apt update 
sudo apt -y upgrade
sudo apt -y install unzip vim curl openjdk-21-jre p7zip-full htop net-tools bpytop ffmpeg sysbench smartmontools jq qemu-guest-agent haveged util-linux
sudo systemctl enable --now fstrim.timer
sudo systemctl enable --now qemu-guest-agent

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

echo "${YELLOW} DOWNLOADING OTHER CUSTOM SCRIPTS FOR QORTAL ${NC}\n"
cd 
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh


chmod +x *.sh
mv check-qortal-status.sh ~/qortal

echo "${CYAN} RUNNING AUTO-FIX SCRIPT TO SET IT UP..."
./auto-fix-qortal.sh

echo "${YELLOW} FINISHING UP ${NC}\n"

echo "${YELLOW} REBOOTING MACHINE IN 10 SECONDS${NC} - ${RED}IF YOU WOULD NOT LIKE TO REBOOT, PUSH${NC} ${GREEN} CNTRL+C${NC}${RED} WITHIN THE NEXT 10 SECONDS${NC}\n - ${YELLOW}IF YOU WOULD LIKE TO${NC} ${CYAN}START QORTAL AT BOOT${NC}${YELLOW} ADD THE FOLLOWING TO CRON${NC}'${GREEN} @reboot ./start-qortal.sh${NC}' -${YELLOW} YOU CAN ACCESS CRON EDITOR WITH${NC} '${GREEN}crontab -e${NC}\n'" 

sleep 10 

sudo reboot

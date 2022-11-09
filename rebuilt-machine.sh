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

echo "${PURPLE} UPDATING UBUNTU AND INSTALLING REQUIRED SOFTWARE PACKAGES ${NC}\n" 

sudo apt update 
sudo apt -y upgrade
sudo apt -y install unzip vim curl default-jre cinnamon-desktop-environment vlc chromium-browser p7zip-full libfuse2

echo "${BLUE} DOWNLOADING QORTAL CORE AND QORT SCRIPT ${NC}"

curl -L -O https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
unzip qortal*.zip
rm qortal*.zip
cd qortal
chmod +x *.sh
curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/tools/qort
chmod +x qort
cd 

echo "${PURPLE} DOWNLOADING QORTAL UI AppImage AND RENAMING ${NC}"

cd Desktop
curl -L -O https://github.com/Qortal/qortal-ui/releases/download/v1.9.2/Qortal-Setup-amd64.AppImage
mv Qortal-Setup*.AppImage Qortal-UI
chmod +x Qortal-UI

echo "${CYAN} DOWNLOADING IMAGES AND OTHER SCRIPTS ${NC}"

curl -L -O https://cloud.qortal.org/s/t4Fy8Lp4kQYiYZN/download/Machine-files.zip

unzip Machine-files.zip

cd Machine-files

mv Pictures/*.* ~/Pictures/
mv start-qortal.sh ~/

cd 

curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh


echo "${YELLOW} FINISHING UP ${NC}"

chmod +x *.sh

rm -R Machine-files

echo "${CYAN} STARTING QORTAL REFRESH ${NC}" 

./refresh-qortal.sh



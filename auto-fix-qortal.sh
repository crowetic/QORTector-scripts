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

check_internet() {
echo "${YELLOW} Checking internet connection ${NC}\n"

INTERNET_STATUS="UNKNOWN"
TIMESTAMP=$(date +%s)

ping -c 1 -W 0.7 8.8.4.4 > /dev/null 2>&1
if [ $? -eq 0 ]; then
    if [ "$INTERNET_STATUS" != "UP" ]; then
        echo "${BLUE}Internet connection is UP, continuing${NC}\n   $(date +%Y-%m-%dT%H:%M:%S%Z) $(( $(date +%s) - $TIMESTAMP ))"
        INTERNET_STATUS="UP"
        rm -rf ~/Desktop/check-qortal-status.sh
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh && mv check-qortal-status.sh ~/qortal && chmod +x ~/qortal/check-qortal-status.sh
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh && chmod +x start-qortal.sh
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh && chmod +x refresh-qortal.sh
        check_for_pi
    fi
else
    if [ "$INTERNET_STATUS" = "UP" ]; then
        echo "${RED}Internet Connection is DOWN, please fix connection and restart device, script will re-run automatically after 7 min.${NC}\n $(date +%Y-%m-%dT%H:%M:%S%Z) $(( $(date +%s) - $TIMESTAMP ))"
        INTERNET_STATUS="DOWN"
        sleep 30
        exit 1
    fi
fi
}

check_qortal() {
echo "${YELLOW} Checking the version of qortal on local machine VS the version on github... ${NC}\n"

LOCAL_VERSION=$(curl -s localhost:12391/admin/info | grep -oP '"buildVersion":"qortal-\K[^-]*' | sed 's/-.*//' | tr -d '.')
REMOTE_VERSION=$(curl -s "https://api.github.com/repos/qortal/qortal/releases/latest" | grep -oP '"tag_name": "v\K[^"]*' | tr -d '.')

if [ "$LOCAL_VERSION" -ge "$REMOTE_VERSION" ]; then
    echo "${GREEN} Local version is higher than or equal to the remote version, no qortal changes necessary, updating scripts and continuing...${NC}\n"
    check_for_GUI   
else
    update_qortal
fi
}

update_qortal() {
echo "${YELLOW} Your Qortal version is outdated, checking hash of qortal.jar on local machine VS newest released qortal.jar on github and updating your qortal.jar... ${NC}\n"

cd ~/qortal || exit
md5sum qortal.jar > "local.md5"
cd

echo "${CYAN} Grabbing newest released jar to check hash ${NC}\n"
curl -L -O https://github.com/qortal/qortal/releases/latest/download/qortal.jar
md5sum qortal.jar > "remote.md5"

LOCAL=$(cat ~/qortal/local.md5)
REMOTE=$(cat ~/remote.md5)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "${YELLOW} Hash check says your Qortal core is UP-TO-DATE, checking environment and updating scripts... ${NC}\n"
    check_for_GUI
    exit 1
else
    echo "${RED} Hash check confirmed your qortal core is OUTDATED, refreshing and starting qortal...then checking for environment and updating scripts ${NC}\n"
    cd qortal
    killall -9 java
    sleep 3
    rm -rf db log.t* qortal.log run.log run.pid qortal.jar
    cp ~/qortal.jar ~/qortal
    rm ~/qortal.jar
    rm ~/remote.md5 local.md5
    ./start.sh
    check_for_GUI
fi
}



check_for_GUI(){
if [ -n "$DISPLAY" ]; then
    echo "${CYAN} Machine is logged in via GUI, setting up auto-fix-visible for GUI-based machines... ${NC}\n"
        
    echo "${YELLOW} Setting up auto-fix-visible on GUI-based system... first, creating new crontab entry without auto-fix-startup... ${NC}\n"
    sleep 2
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-GUI-cron
    crontab auto-fix-GUI-cron
    rm -rf auto-fix-GUI-cron
    echo "${YELLOW} Setting up new ${NC}\n ${WHITE} 'auto-fix-qortal-GUI.desktop' ${NC}\n ${YELLOW} file for GUI-based machines to run 7 min after startup in a visual fashion. Entry in 'startup' will be called ${NC}\n ${WHITE} 'auto-fix-visible' ${NC}\n"
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal-GUI.desktop
    mkdir -p ~/.config/autostart
    cp auto-fix-qortal-GUI.desktop ~/.config/autostart
    rm -rf ~/auto-fix-qortal-GUI.desktop
    echo "${YELLOW} Your machine will now run 'auto-fix-qortal.sh' script in a fashion you can SEE, 7 MIN AFTER YOU REBOOT your machine. The normal 'background' process for auto-fix-qortal will continue as normal.${NC}\n"
    update_script

else echo "${YELLOW} Non-GUI system detected, skipping 'auto-fix-visible' setup ${NC}\n"
    update_script

fi
}

check_memory(){
totalm=$(free -m | awk '/^Mem:/{print $2}')

echo "${YELLOW} Checking system RAM ... $totalm System RAM ... Configuring system for optimal RAM settings...${NC}\n"
if [ "$totalm" -le 6000 ]; then
    echo "${WHITE} Machine has less than 6GB of RAM, Downloading correct start script for your configuration...${NC}\n"
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/4GB-start.sh && mv 4GB-start.sh ~/qortal/start.sh && chmod +x ~/qortal/start.sh
elif [ "$totalm" -ge 6001 ] && [ "$totalm" -le 16000 ]; then
    echo "${WHITE} Machine has between 6GB and 16GB of RAM, Downloading correct start script for your configuration...${NC}\n"
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-6001-to-16000m.sh && mv start-6001-to-16000m.sh ~/qortal/start.sh && chmod +x ~/qortal/start.sh
else echo "${WHITE} Machine has more than 16GB of RAM, using high-RAM start script and continuing...${NC}\n"
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-high-RAM.sh && mv start-high-RAM.sh ~/qortal/start.sh && chmod +x ~/qortal/start.sh
fi

check_qortal

}

check_for_pi(){
if command -v raspi-config >/dev/null 2>&1 ; then

    echo "${YELLOW} Raspberry Pi machine detected, checking for 32bit pi...${NC}\n"
    
    if [ "$(uname -m | grep 'armv7l')" != "" ]; then
        echo "${WHITE} 32bit ARM detected, using ARM 32bit compatible modified start script${NC}\n"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-modified-memory-args.sh
        chmod +x start-modified-memory-args.sh
        mv start-modified-memory-args.sh ~/qortal/start.sh
        check_qortal
    else
        echo "${WHITE} Machine is not ARM 32bit, checking RAM amount and adding correct start script...${NC}\n"
        totalm=$(free -m | awk '/^Mem:/{print $2}')
        echo "${YELLOW} configuring auto-fix cron...${NC}\n"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron
        crontab auto-fix-cron
        rm -rf auto-fix-cron
        
        if [ "$totalm" -le 6000 ]; then
            echo "${WHITE} 4GB 64bit pi detected, grabbing correct start script and continuing...${NC}\n"
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/4GB-start.sh && mv 4GB-start.sh ~/qortal/start.sh && chmod +x ~/qortal/start.sh
            check_qortal
        else
            echo "${WHITE} 8GB 64bit pi detected, grabbing correct start script and continuing...${NC}\n"
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-6001-to-16000m.sh && mv start-6001-to-16000m.sh ~/qortal/start.sh && chmod +x ~/qortal/start.sh
            check_qortal
        fi
    fi
else echo "${YELLOW} Not a Raspberry pi machine, continuing...${NC}\n"
    check_memory

fi
}

update_script(){
mkdir -p ~/qortal/new-scripts
mkdir -p ~/qortal/new-scripts/backups
cp ~/qortal/new-scripts/auto-fix-qortal.sh ~/qortal/new-scripts/backups
rm -rf ~/qortal/new-scripts/auto-fix-qortal.sh
cp ~/auto-fix-qortal.sh ~/qortal/new-scripts/backups/original.sh
cd ~/qortal/new-scripts
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
chmod +x auto-fix-qortal.sh
cd
cp ~/qortal/new-scripts/auto-fix-qortal.sh .
echo "${YELLOW} Auto-fix script run complete.${NC}\n"
sleep 5 
exit 1
}


check_internet

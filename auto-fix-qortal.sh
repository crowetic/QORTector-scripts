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

core_running=$(curl -s localhost:12391/admin/status)
if [ -z ${core_running} ]; then 
	echo "${RED} CORE DOES NOT SEEM TO BE RUNING, WAITING 2 MINUTES IN CASE IT IS STILL STARTIG UP... ${NC}\n"
	sleep 120
fi

LOCAL_VERSION=$(curl -s localhost:12391/admin/info | grep -oP '"buildVersion":"qortal-\K[^-]*' | sed 's/-.*//' | tr -d '.')
REMOTE_VERSION=$(curl -s "https://api.github.com/repos/qortal/qortal/releases/latest" | grep -oP '"tag_name": "v\K[^"]*' | tr -d '.')

if [ "$LOCAL_VERSION" -ge "$REMOTE_VERSION" ]; then
    echo "${GREEN} Local version is higher than or equal to the remote version, no qortal changes necessary, updating scripts and continuing...${NC}\n"
    check_for_GUI   
else
    check_hash_update_qortal
fi
}

check_hash_update_qortal() {
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
    cd 
    check_for_GUI_already_bootstrapped
fi
}

force_bootstrap() {
echo "${RED} height checks revealed issues, forcing bootstrap... ${NC}\n"
cd qortal
killall -9 java
sleep 3
rm -rf db log.t* qortal.log run.log run.pid
./start.sh
cd 
update_script
}

check_for_GUI_already_bootstrapped(){
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
    echo "${CYAN} continuing to verify node height...${NC}\n"
    update_script

else echo "${YELLOW} Non-GUI system detected, skipping 'auto-fix-visible' setup ${NC}\n"
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron-new
    crontab auto-fix-cron-new
    update_script
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
    echo "${CYAN} continuing to verify node height...${NC}\n"
    #update_script
    check_height

else echo "${YELLOW} Non-GUI system detected, skipping 'auto-fix-visible' setup... configuring  checking node height... ${NC}\n"
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron-new
    crontab auto-fix-cron-new
    #update_script
    check_height
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
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron
        crontab auto-fix-cron
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

# QORTAL BLOCK HEIGHT CHECKS FIRST WITH JQ THEN WITH PYTHON, IF BOTH FAIL, SKIP CHECKS.

check_height() { 

if [ -f auto_fix_last_height.txt ]; then
	previous_local_height=$(cat auto_fix_last_height.txt)
fi

heightjq=$(curl -sS "http://localhost:12391/admin/status" | jq '.height')

if [ -z "$heightjq" ]; then 
	echo "obtaining height with jq failed, trying python..."
	heightpy=$(python -c "import json,urllib.request; print(json.loads(urllib.request.urlopen('http://localhost:12391/admin/status').read().decode())['height'])")
	
	if [ -z "${heightpy}" ]; then
		echo "obtaining height with python also failed, skipping block height checks...is there something wrong with Qortal?"
		no_local_height
	fi
	
	echo "${heightpy}" > "auto_fix_last_height.txt"
	echo "${heightpy} is height from python, since python worked, we are setting local_height variable to heightpy"
	local_height=${heightpy}
	
	# CHECK FOR HEIGHT BEING THE SAME AS LAST SCRIPT RUN
	if [ $previous_local_height -eq $heightpy ]; then
		echo "height check found height hasn't changed since last script run! bootstrapping!"
		force_boostrap
	fi
	
	remote_height_checks
fi 

if [ -n ${heightjq} ]; then
	echo "${heightjq} is height from jq, we will write this to a temp file and local_height variable and verify against other sources..."
	echo "${heightjq}" > "auto_fix_last_height.txt"
	local_height=${heightjq}
	
	if [ $previous_local_height -eq $heightjq ]; then
		echo "height check found height hasn't changed since last script run! bootstrapping!"
		force_bootstrap
	fi
	remote_height_checks
fi
}

no_local_height() {
# height checks failed, is qortal running? 
# make another action here...
echo "have to do other things, node may not be running?"
echo "this portion of the script has not been configured yet"
echo "${RED} Please check that your Qortal Core is running...${NC}\n"
}

remote_height_checks() {

height_api_qortal_org=$(curl -sS "https://api.qortal.org/blocks/height")
height_api_qortal_online=$(curl -sS "https://api.qortal.online/blocks/height")
height_qortal_link=$(curl -sS "https://qortal.link/blocks/height")
height_qortal_name=$(curl -sS "https://qortal.name/blocks/height")

declare -a remote_node_heights #declare an array

#remote_node_heights+=$height_api_qortal_online
#remote_node_heights+=$height_qortal_link
#remote_node_heights+=$height_qortal_name
remote_node_heights+=$height_api_qortal_org

for i in "${remote_node_heights[@]}"; do
  	if (( ${i} - 1500 <= ${local_height} && ${local_height} <= ${i} + 1500 )); then
    		echo "Local height (${local_height}) is within range of node height (${i}). Performing desired action." >&2
    # Perform the desired action here, e.g., running a script or making another API call
    		echo "node height is within range of remote nodes... height seems fine..."
    		update_script
  	else 
  		echo "node is outside the range of remote node(s)... bootstrapping..."
  		force_bootstrap
  	fi >&2
done
}


check_internet

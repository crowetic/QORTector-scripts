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


check_qortal() {
echo "${YELLOW} Checking the version of qortal on local machine VS the version on github... ${NC}\n"

core_running=$(curl -s localhost:12391/admin/status)
if [ -z ${core_running} ]; then 
	echo "${RED} CORE DOES NOT SEEM TO BE RUNING, WAITING 1 MINUTE IN CASE IT IS STILL STARTING UP... ${NC}\n"
	sleep 60
fi

LOCAL_VERSION=$(curl -s localhost:12391/admin/info | grep -oP '"buildVersion":"qortal-\K[^-]*' | sed 's/-.*//' | tr -d '.')
REMOTE_VERSION=$(curl -s "https://api.github.com/repos/qortal/qortal/releases/latest" | grep -oP '"tag_name": "v\K[^"]*' | tr -d '.')

if [ "$LOCAL_VERSION" -ge "$REMOTE_VERSION" ]; then
    echo "${GREEN} Local version is higher than or equal to the remote version, no qortal updates needed... continuing...${NC}\n"
    check_for_GUI   
else
    check_hash_update_qortal
fi
}


check_hash_update_qortal() {
echo "${RED}API-call-based version checking FAILED${NC}${YELLOW}. ${NC}${CYAN}Proceeding to HASH CHECK${NC}${YELLOW}, checking hash of qortal.jar on local machine VS newest released qortal.jar on github and updating your qortal.jar if needed... ${NC}\n"
cd ~/qortal || exit
md5sum qortal.jar > "local.md5"
cd
echo "${CYAN} Grabbing newest released jar to check hash... ${NC}\n"
curl -L -O https://github.com/qortal/qortal/releases/latest/download/qortal.jar
md5sum qortal.jar > "remote.md5"

LOCAL=$(cat ~/qortal/local.md5)
REMOTE=$(cat ~/remote.md5)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "${CYAN} Hash check says your Qortal core is UP-TO-DATE, checking environment... ${NC}\n"
    check_for_GUI
    exit 1
else
    echo "${RED} Hash check confirmed your qortal core is OUTDATED, ${NC}${YELLOW}updating, bootstrapping, and starting qortal...then checking environment and updating scripts... ${NC}\n"
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


check_for_GUI() {
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
    echo "${YELLOW} Your machine will now run 'auto-fix-qortal.sh' script in a pop-up terminal, 7 MIN AFTER YOU REBOOT your machine. The normal 'background' process for auto-fix-qortal will continue as normal.${NC}\n"
    echo "${CYAN} continuing to verify node height...${NC}\n"

    check_height

else echo "${YELLOW} Non-GUI system detected, skipping 'auto-fix-visible' setup... ${NC}${CYAN}configuring cron then checking node height... ${NC}\n"
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron-new
    crontab auto-fix-cron-new
    rm -rf auto-fix-cron-new

    check_height
fi
}


check_for_GUI_already_bootstrapped() {
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
    rm -rf auto-fix-cron-new
    update_script
fi
}


check_height() {
local_height=$(curl -sS "http://localhost:12391/blocks/height")

if [ -f auto_fix_last_height.txt ]; then
	previous_local_height=$(cat auto_fix_last_height.txt)
	if [ -n ${previous_local_height} ]; then
		if [ "${local_height}" = "${previous_local_height}" ]; then
			echo "${RED} local height has not changed since previous script run... waiting 3 minutes and checking height again, if height still hasn't changed, forcing bootstrap... ${NC}\n"
			sleep 188
			checked_height=$(curl "localhost:12391/blocks/height")
			sleep 2
			if [ "${checked_height}" = "${previous_local_height}" ]; then
				echo "${RED} block height still has not changed... forcing bootstrap... ${NC}\n"
				force_bootstrap
			fi
		
		fi
	fi
fi

if [ -z ${local_height} ]; then
	echo "${RED} local API call for block height returned empty, IS YOUR QORTAL CORE RUNNING? ${NC}\n"
	echo "${RED} if this doesn't work, then the script encountered an issue that it isn't fully equipped to handle, it may fix it upon a restart, TRY RESTARTING THE COMPUTER and WAITING 15 MINUTES... ${NC}\n"
	no_local_height
else
	echo ${local_height} > auto_fix_last_height.txt
fi

remote_height_checks
}


no_local_height() {
# height checks failed, is qortal running? 
# make another action here...
echo "${WHITE} Checking if node is bootstrapping or not...${NC}\n"

# Check if the main log file exists
if [ -f ~/qortal/qortal.log ]; then
  if tail -n 5 ~/qortal/qortal.log | grep -E -i 'bootstrap|bootstrapping' > /dev/null; then
    echo "${RED} NODE SEEMS TO BE BOOTSTRAPPING, UPDATING SCRIPT AND EXITING, NEXT RUN WILL FIND/FIX ANY ISSUES ${NC}\n"
    update_script
  fi
else
  echo "Checking for old log method..."
  old_log_found=false

  # Check for old log files and process them
  for log_file in ~/qortal/log.t*; do
    if [ -f "$log_file" ]; then
      old_log_found=true
      echo "${YELLOW}Old log method found, backing up old logs and updating logging method...${NC}\n"
      mkdir -p ~/qortal/backup/logs
      # Move old log files to the backup directory
      mv ~/qortal/log.t* ~/qortal/backup/logs
      mv ~/qortal/log4j2.properties ~/qortal/backup/logs
      # Download the new log4j2.properties file
      curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/log4j2.properties
      # Move the new log4j2.properties file to the qortal directory
      mv log4j2.properties ~/qortal
      echo -e "${RED}Stopping Qortal to apply new logging method...${NC}\n"
      # Stop Qortal to apply changes
      cd ~/qortal
      ./stop.sh 
      cd ~
      break
    fi
  done

  if ! $old_log_found; then
    echo "No old log files found."
  fi
fi

echo "${GREEN} Starting Qortal Core and sleeping for 2.5 min to let it startup fully, PLEASE WAIT... ${NC}\n"
cd ~/qortal
./start.sh 
sleep 166
cd 
echo "${GREEN} Checking if Qortal started correctly... ${NC}\n"
local_height_check=$(curl -sS "http://localhost:12391/blocks/height")
node_works=$(curl -sS "http://localhost:12391/admin/status")

if [ -n ${local_height_check} ]; then
	echo "${GREEN} local height is ${NC}${CYAN} ${local_height_check}${NC}\n"
	echo "${GREEN} node is GOOD, re-trying height check and continuing...${NC}\n"
	check_height_2
else 
	echo "${RED} starting Qortal Core FAILED... script will exit now until future updates add additional features...sorry the script couldn't resolve your issues! It will update automatically if you have it configured to run automatically! ${NC}${CYAN}It is possible that the script will fix the issue IF YOU RESTART YOUR COMPUTER AND WAIT 15 MINUTES...${NC}\n"
	update_script
fi
}


remote_height_checks() {
    height_api_qortal_org=$(curl -sS --connect-timeout 10 "https://api.qortal.org/blocks/height")
    height_qortal_link=$(curl -sS --connect-timeout 10 "https://qortal.link/blocks/height")
    local_height=$(curl -sS --connect-timeout 10 "http://localhost:12391/blocks/height")

    if [ -z "$height_api_qortal_org" ] || [ -z "$height_qortal_link" ]; then
        echo "${RED}Failed to fetch data from one or more remote URLs. Skipping remote node checks and updating script ${NC}\n"
        update_script
    fi

    if [ "$height_api_qortal_org" -ge $((local_height - 1500)) ] && [ "$height_api_qortal_org" -le $((local_height + 1500)) ]; then
        echo "${YELLOW}Local height ${NC}(${CYAN}${local_height}${NC})${YELLOW} is within 1500 block range of api.qortal.org node height ${NC}(${GREEN}${height_api_qortal_org}${NC})."
        echo "${GREEN}api.qortal.org height checks PASSED updating script...${NC}"
        update_script
    else
        echo "${RED}Node is outside the 1500 block range of api.qortal.org, checking another node to be sure...${NC}"
        if [ "$height_qortal_link" -ge $((local_height - 1500)) ] && [ "$height_qortal_link" -le $((local_height + 1500)) ]; then
            echo "${YELLOW}Local height ${NC}(${CYAN}${local_height}${NC})${YELLOW} is within 1500 block range of qortal.link node height ${NC}(${GREEN}${height_qortal_link}${NC})."
            echo "${GREEN}qortal.link height checks PASSED updating script...${NC}"
            update_script
        else
            echo "${RED}SECOND remote node check FAILED... ${NC}${YELLOW}assuming local node needs bootstrapping... bootstrapping in 5 seconds...${NC}\n"
            force_bootstrap
        fi
    fi
}


check_height_2() { 
local_height=$(curl -sS "http://localhost:12391/blocks/height")

if [ -f auto_fix_last_height.txt ]; then
	previous_local_height=$(cat auto_fix_last_height.txt)
	if [ -n ${previous_local_height} ]; then
		if [ "${local_height}" = "${previous_local_height}" ]; then
			echo "${RED} local height has not changed since previous script run... waiting 3 minutes and checking height again, if height still hasn't changed, forcing bootstrap... ${NC}\n"
			sleep 188
			checked_height=$(curl "localhost:12391/blocks/height")
			sleep 2
			if [ "${checked_height}" = "${previous_local_height}" ]; then
				echo "${RED} block height still has not changed... forcing bootstrap... ${NC}\n"
				force_bootstrap
			fi
		
		fi
	fi
fi

if [ -z ${local_height} ]; then
	echo "${RED} SECOND height check failed, unsure what is going on, but a restart of the node and waiting may fix it... ${NC}\n"
	echo "${CYAN} TRY RESTARTING THE COMPUTER and WAITING 15 MINUTES... ${NC}\n"
	
	update_script
else
	echo ${local_height} > auto_fix_last_height.txt
fi

remote_height_checks
}


force_bootstrap() {
echo "${RED} height check found issues, forcing bootstrap... ${NC}\n"
cd qortal
killall -9 java
sleep 3
rm -rf db log.t* qortal.log run.log run.pid
sleep 5
./start.sh
cd 
update_script
}


update_script() {
echo "${YELLOW}Updating script to newest version and backing up old one...${NC}\n"
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
exit
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



check_internet

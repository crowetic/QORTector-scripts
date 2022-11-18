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

echo "${BLUE} checking internet connection ${NC}\n"
INTERNET_STATUS="UNKNOWN"
TIMESTAMP=`date +%s`
    ping -c 1 -W 0.7 8.8.4.4 > /dev/null 2>&1
    if [ $? -eq 0 ] ; then
        if [ "$INTERNET_STATUS" != "UP" ]; then
            echo "${BLUE}Internet connection is UP, continuing${NC}\n   `date +%Y-%m-%dT%H:%M:%S%Z` $((`date +%s`-$TIMESTAMP))";
            INTERNET_STATUS="UP"
	    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/settings.json && mv settings.json ~/qortal
	    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh && mv check-qortal-status.sh ~/Desktop && chmod +x ~/Desktop/check-qortal-status.sh
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-modified-memory-args.sh && mv start-modified-memory-args.sh ~/qortal/start.sh && chmod +x ~/qortal/start.sh
	fi
    else
        if [ "$INTERNET_STATUS" = "UP" ]; then
            echo "Internet Connection is DOWN, please fix connection and restart device${NC}\n `date +%Y-%m-%dT%H:%M:%S%Z` $((`date +%s`-$TIMESTAMP))";
            INTERNET_STATUS="DOWN"
	    sleep 30
	    exit 1
        fi
    fi



echo "${PURPLE} Checking hash of qortal.jar on local machine VS newest released qortal.jar on github ${NC}\n" 

cd qortal
md5sum qortal.jar > "local.md5"
cd 


echo "${RED} Grabbing newest released jar to check hash ${NC}\n"

curl -L -O https://github.com/qortal/qortal/releases/latest/download/qortal.jar

md5sum qortal.jar > "remote.md5"
 

LOCAL=$(cat ~/qortal/local.md5) 
REMOTE=$(cat ~/remote.md5)


if [ "$LOCAL" = "$REMOTE" ]; then

    echo "${BLUE} Your Qortal Core is up-to-date! No action needed. ${NC}\n" 
    sleep 5 
    rm ~/qortal.jar 
    rm ~/qortal/local.md5 remote.md5 
    mkdir ~/qortal/new-scripts
    mkdir ~/qortal/new-scripts/backups
    mv ~/qortal/new-scripts/auto-fix-qortal.sh ~/qortal/new-scripts/backups
    cp ~/auto-fix-qortal.sh ~/qortal/new-scripts/backups/original.sh
    cd ~/qortal/new-scripts
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
    chmod +x auto-fix-qortal.sh
    cd
    cp ~/qortal/new-scripts/auto-fix-qortal.sh .
    exit 1

else 
	echo "${CYAN} Your Qortal Core is OUTDATED, refreshing and starting qortal... ${NC}\n"
	cd qortal
        killall -9 java
        sleep 5
        rm -R db
        rm qortal.jar
        rm log.t*
	mv ~/qortal.jar . 
        rm ~/remote.md5 local.md5 
        ./start.sh
	mkdir ~/qortal/new-scripts
        mkdir ~/qortal/new-scripts/backups
        mv ~/qortal/new-scripts/auto-fix-qortal.sh ~/qortal/new-scripts/backups
        cp ~/auto-fix-qortal.sh ~/qortal/new-scripts/backups/original.sh
        cd ~/qortal/new-scripts
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
        chmod +x auto-fix-qortal.sh
        cd
        cp ~/qortal/new-scripts/auto-fix-qortal.sh .
fi


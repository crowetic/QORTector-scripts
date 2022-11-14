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
    exit 1

else 
	echo "${CYAN} Your Qortal Core is OUTDATED, refreshing and starting qortal... ${NC}\n"
	cd qortal
        killall -9 java
        sleep 5
        rm -R db
        rm start.sh
        rm qortal.jar
        rm log.t*
	mv ~/qortal.jar . 
        rm ~/remote.md5 local.md5 
	curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-modified-memory-args.sh
        mv start-modified-memory-args.sh start.sh
        chmod +x start.sh
        ./start.sh
fi


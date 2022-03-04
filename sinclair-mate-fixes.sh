#!/bin/sh

echo BACKING UP CRONTAB

crontab -l > cron.backup

echo MAKING CHANGES TO QORTAL START SCRIPT

cd /home/pi/qortal
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-modified-memory-args.sh
mv start.sh original-start-script-sh
mv start-modified-memory-args.sh start.sh
chmod +x start.sh

cd /home/pi

echo DOWNLOADING AUTO-RESTART SCRIPT AND CONFIGURING CRON TO USE IT

wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/reboot-mate.sh
chmod +x reboot-mate.sh
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/restart-cron
crontab restart-cron

echo STOPPING QORTAL AND STARTING WITH NEW SCRIPT

cd /home/pi/qortal
./stop.sh && sleep 10 && killall -9 java
./start.sh

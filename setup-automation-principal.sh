#!/bin/sh
cd 
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
chmod +x auto-fix-qortal.sh
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh 
chmod +x start-qortal.sh
gnome-terminal -- ./auto-fix-qortal.sh
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron-principal
crontab auto-fix-cron-principal
rm auto-fix-cron-principal
rm setup-automation-principal.sh
exit 1

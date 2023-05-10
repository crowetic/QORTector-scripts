#!/bin/sh
cd 
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
chmod +x auto-fix-qortal.sh
gnome-terminal -- ./auto-fix-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron-principal
crontab auto-fix-cron-principal
rm auto-fix-cron-principal
rm setup-automation-principal.sh
exit 1

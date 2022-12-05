#!/bin/sh
cd 
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
chmod +x auto-fix-qortal.sh
mate-terminal -- ./auto-fix-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron
crontab auto-fix-cron
rm auto-fix-cron
rm setup-pi-aut0mation.sh
exit 1

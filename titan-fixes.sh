#!/bin/sh


echo ...downloading config changes...

wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/cmdline.txt

wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/config.txt

echo ...copying config changes...

sudo mv config.txt /boot && sudo mv cmdline.txt /boot

echo ...doing system updates...

sudo apt update && sudo apt -y upgrade

echo ...installing bluetooth packages...

sudo apt -y install bluemon bluez bluez-tools libpam-blue pi-bluetooth bluez-firmware bluetooth

echo ...installing mesa GPU packages...

sudo apt -y install mesa libgles2-mesa libgles2-mesa-dev xorg-dev

echo ...restarting system...

sudo reboot


#!/bin/sh
# this script will setup the default ubuntu 64 image with all of the necessary dependencies and installations for Qortal, and a few added scripts to start Qortal on boot, and run the UI.

# it is recommended that you disable sleep settings so the pi doesn't turn screen off or go to sleep, as that will cause issues potentially. 

echo "---INSTALLING UPDATES AND UPGRADES TO EXISTING SOFTWARE---"

sudo apt update && sudo apt -y upgrade

echo "---INSTALLING GIT, JAVA, CURL, VIM, UNZIP, P7ZIP-FULL, AND CINNAMON DESKTOP---"

sudo apt install -y git default-jre curl vim cinnamon-desktop-environment unzip p7zip-full openssh-server htop

# you will need to change the boot environment when you install cinnamon, log out, then when you log back in click the settings toggle at the bottom after clicking the username and change to cinnamon, else it will continue using unity.

echo "---INSTALLING NODEJS 14 AND YARN (FOR BUILDING THE UI)---"

# this may need modification as the nodejs versions change, or may need to add the apt key for yarn as time goes on.

curl -fsSL https://deb.nodesource.com/setup_14.x | sudo -E bash -
curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/yarnkey.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt update && sudo apt -y install nodejs yarn

# I also change the menu icon on the menu to the qortal icon from wiki.qortal.org - and get the qortal desktop background for good measure. :)

echo "---INSTALLING PYTHON AND NPM PYTHON FOR UI BUILD PROCESS---"

sudo apt update && sudo apt install python 
npm install python

echo "---DOWNLOADING QORTAL 1.4.6 CORE---"

# obviously this will have to be updated to include the newer versions when released.

echo "---UNZIPPING QORTAL CORE AND MAKING SH FILES EXECUTABLE, ALSO DOWNLOADING THE QORT SCRIPT FOR EASE OF USE OF API---"

wget https://github.com/Qortal/qortal/releases/download/v1.5.3/qortal-1.5.3.zip
unzip qortal*.zip
rm qortal*.zip
cd qortal
chmod +x *.sh
wget https://raw.githubusercontent.com/Qortal/qortal/master/tools/qort
chmod +x qort

#you can choose to download the bootstrap here, or simply start qortal with ./start.sh

echo "---YOU CAN NOW START QORTAL WITH ./start.sh IN THIS FOLDER---"

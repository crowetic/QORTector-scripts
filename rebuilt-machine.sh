#!/bin/sh

# Regular Colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m'

username=$(whoami)

echo "${YELLOW} 🛠 UPDATING 🛠 UBUNTU AND INSTALLING REQUIRED SOFTWARE 📦 PACKAGES 📦 ${NC}\n"

echo "${YELLOW} ⚙️ creating system folders that require admin permissions... and disabling 'ubuntu pro' notices in terminal..."
sudo pro config set apt_news=false

sudo apt update
sudo apt -y upgrade
sudo apt -y install git jq gnome-software openssh-server unzip vim curl openjdk-21-jre yaru-theme-icon yaru-theme-gtk yaru-theme-unity zlib1g-dev vlc chromium-browser p7zip-full libfuse2 htop net-tools bpytop ffmpeg sysbench smartmontools ksnip xsensors fonts-symbola lm-sensors gparted cinnamon-desktop-environment

echo "${YELLOW} 📦 INSTALLING SENSORS MONITOR APPLET FOR PANEL...${NC}\n"

mkdir -p "${HOME}/.local/share/cinnamon/applets"
cd "${HOME}/.local/share/cinnamon/applets"
wget -O sensors-monitor.zip "https://cinnamon-spices.linuxmint.com/files/applets/Sensors@claudiux.zip"
unzip sensors-monitor.zip -d Sensors@claudiux
rm sensors-monitor.zip
cd ${HOME}

echo "✅ Applet installed. You can now add 'Sensors Monitor' to your panel manually."

### SET DEFAULT SESSION TO CINNAMON ###
echo "${YELLOW} ⚙️ SETTING CINNAMON AS DEFAULT DESKTOP SESSION ${NC}\n"

# Works for most LightDM and GDM-based setups
echo "cinnamon" > "${HOME}/.xsession"
chmod +x "${HOME}/.xsession"

cat > "${HOME}/.dmrc" <<EOL
[Desktop]
Session=cinnamon
EOL

echo "${GREEN} Cinnamon session will be loaded by default on next login! ${NC}\n"

### DOWNLOAD & INSTALL QORTAL CORE ###
echo "${YELLOW} ⬇️ DOWNLOADING QORTAL CORE AND QORT SCRIPT ${NC}\n"

cd "${HOME}"
mkdir -p backups

if [ -d qortal ]; then
  echo "${PURPLE} qortal DIRECTORY FOUND, BACKING UP ORIGINAL TO '~/backups' AND RE-INSTALLING ${NC}\n"
  mv qortal "backups/qortal-$(date +%s)"
fi

curl -L -O https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
unzip qortal*.zip
rm qortal*.zip
cd qortal
rm -f settings.json
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/settings.json
curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/tools/qort
chmod +x *.sh qort

cd "${HOME}"

### INSTALL QORTAL UI & HUB ###
cd qortal

if [ "$(uname -m)" = "aarch64" ]; then
    echo "${GREEN} ARM 64-bit detected. Downloading ARM64 Qortal Hub and UI ${NC}"
    curl -L -O https://github.com/Qortal/Qortal-Hub/releases/download/v0.5.3/Qortal-Hub-arm64_0.5.3.AppImage
    curl -L -O https://github.com/Qortal/qortal-ui/releases/download/v4.6.1/Qortal-Setup-arm64.AppImage
    mv Qortal-Hub-arm64* Qortal-Hub
    mv Qortal-Setup-arm64* Qortal-UI
else
    curl -L -O https://github.com/Qortal/Qortal-Hub/releases/download/v0.5.3/Qortal-Hub_0.5.3.AppImage
    curl -L -O https://github.com/Qortal/qortal-ui/releases/latest/download/Qortal-Setup-amd64.AppImage
    mv Qortal-Hub* Qortal-Hub
    mv Qortal-Setup* Qortal-UI
fi

chmod +x Qortal-UI Qortal-Hub

### DOWNLOAD EXTRA FILES ###
cd "${HOME}"

curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal-core.sh
curl -L -O https://cloud.qortal.org/s/machinefilesnew/download

chmod +x *.sh
unzip download
rsync -raPz Machine-files/* "${HOME}"


rm -rf download Machine-files
### CINNAMON THEMING - ALWAYS APPLIES EVEN IF CINNAMON ISN'T ACTIVE ###
echo "${YELLOW} 📦 INSTALLING WINDOWS 10 THEMES FOR CINNAMON ${NC}\n"

mkdir -p "${HOME}/.themes"

if [ ! -d "${HOME}/.themes/Windows-10" ]; then
	wget -O Windows-10.zip "https://cinnamon-spices.linuxmint.com/files/themes/Windows-10.zip?time=$(date +%s)"
	unzip Windows-10.zip
	mv Windows-10 "${HOME}/.themes"
	rm Windows-10.zip
fi

# Avoid cloning twice
[ ! -d "${HOME}/.themes/Windows-10-Dark" ] && git clone https://github.com/B00merang-Project/Windows-10-Dark.git "${HOME}/.themes/Windows-10-Dark"

### APPLY THEMES (WILL WORK AFTER REBOOT TOO) ###
echo "${YELLOW} ⚙️ APPLYING CINNAMON THEMES ${NC}\n"

gsettings set org.cinnamon.desktop.wm.preferences theme "Windows-10-Dark" || true
gsettings set org.cinnamon.desktop.interface gtk-theme "Windows-10-Dark" || true
gsettings set org.cinnamon.theme name "Windows-10" || true
gsettings set org.cinnamon.desktop.background picture-uri "file://${HOME}/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png" || true
gsettings set org.cinnamon.desktop.interface icon-theme "Yaru-blue-dark" || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true

### CINNAMON PANEL + MENU CUSTOMIZATION ###
echo "${YELLOW} ⚙️ CREATING CINNAMON PANEL AND MENU CONFIGURATION SCRIPT AND SETTING TO RUN POST-STARTUP NEXT TIME. ${NC}\n"

cat > "$HOME/apply-cinnamon-settings.sh" <<'EOL'
#!/bin/bash
sleep 5
testing without settting these settings first. 
gsettings set org.cinnamon.desktop.wm.preferences theme "Windows-10"
gsettings set org.cinnamon.desktop.interface gtk-theme "Windows-10-Dark"
gsettings set org.cinnamon.theme name "Windows-10"
gsettings set org.cinnamon.desktop.interface icon-theme "Yaru-blue-dark"
gsettings set org.cinnamon.desktop.background picture-uri "file://$HOME/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

echo "Downloading additional settings..."
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/cinnamon-settings.json
mkdir -p "${HOME}/.cinnamon/configs/menu@cinnamon.org"

# Copy your preconfigured menu JSON
cp cinnamon-settings.json "${HOME}/.cinnamon/configs/menu@cinnamon.org/0.json"

EOL

chmod +x "$HOME/apply-cinnamon-settings.sh"

echo "${GREEN} ⬇️ Downloading additional ${NC}${YELLOW}CINNAMON${NC}${GREEN}settings${NC}\n"

curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/cinnamon-settings.json
mkdir -p "${HOME}/.cinnamon/configs/menu@cinnamon.org"
cp cinnamon-settings.json "${HOME}/.cinnamon/configs/menu@cinnamon.org/0.json"

echo "${YELLOW} Configuring terminal, default apps, and more...${NC}\n"
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/configure-terminal-and-more.sh
chmod +x configure-terminal-and-more.sh
./configure-terminal-and-more.sh 
cd "${HOME}"

echo "continuing desktop configuration..."

mkdir -p "$HOME/.config/autostart"

cat > "$HOME/.local/share/applications/apply-cinnamon-settings.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=gnome-terminal -- ./apply-cinnamon-settings.sh
Hidden=false
NoDisplay=false
Name=Apply Cinnamon Settings
Comment=Reapplies Cinnamon panel, theme, and menu customizations
EOL

cat > "${HOME}/.config/autostart/auto-fix-qortal-GUI.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=gnome-terminal -- ./auto-fix-qortal.sh
X-GNOME-Autostart-enabled=true
NoDisplay=false
Hidden=false
Name[en_US]=auto-fix-visible
Comment[en_US]=Run auto-fix script visibly 7 min after system startup.
X-GNOME-Autostart-Delay=420
EOL

cat > "${HOME}/.config/autostart/start-qortal.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=./start-qortal-core.sh
X-GNOME-Autostart-enabled=true
NoDisplay=false
Hidden=false
Name[en_US]=start-qortal
Comment[en_US]=start qortal core 6 seconds after boot
X-GNOME-Autostart-Delay=6
EOL

### ADD DESKTOP SHORTCUTS ###
echo "${YELLOW} CREATING DESKTOP LAUNCHERS ${NC}\n"

mkdir -p "${HOME}/.local/share/desktop-directories"

cat > "${HOME}/.local/share/desktop-directories/qortal.directory" <<EOL
[Desktop Entry]
Name=Qortal
Comment=Qortal Applications
Icon=qortal-logo
Type=Directory
EOL


mkdir -p "${HOME}/.local/share/applications"

cat > "${HOME}/.local/share/applications/qortal-ui.desktop" <<EOL
[Desktop Entry]
Name=Qortal UI
Comment=Launch Qortal User Interface
Exec=/home/${username}/qortal/Qortal-UI
Icon=qortal-ui
Terminal=false
Type=Application
Categories=Qortal;
EOL

cat > "${HOME}/.local/share/applications/qortal-hub.desktop" <<EOL
[Desktop Entry]
Name=Qortal Hub
Comment=Launch Qortal Hub
Exec=/home/${username}/qortal/Qortal-Hub
Icon=qortal-hub
Terminal=false
Type=Application
Categories=Qortal;
EOL

echo "${CYAN} Adding CUSTOM QORTAL ICON THEME...${NC}\n"
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/add-qortal-icon-theme.sh
chmod +x add-qortal-icon-theme.sh

# # Create autostart task to run it once after login
# cat > "${HOME}/.config/autostart/apply-qortal-icons.desktop" <<EOL
# [Desktop Entry]
# Type=Application
# Exec=gnome-terminal -- ./apply-icon-theme-firstboot.sh
# Hidden=false
# NoDisplay=false
# X-GNOME-Autostart-enabled=true
# Name=Apply Qortal Icons
# Comment=Applies Qortal icon theme and removes itself
# EOL

# cat > "$HOME/apply-icon-theme-firstboot.sh" <<'EOL'
# #!/bin/bash
# sleep 10
# echo "APPLYING QORTAL ICON THEME..."
# echo 
# echo "NOTE: THE ICONS IN SOME CASES (SUCH AS MENU BUTTON) MAY NOT WORK IMMEDIATELY, MAY REQUIRE A REBOOT TO DISPLAY PROPERLY..."
# sleep 10
# echo 
# echo "executing icon theme script..."
# ./add-qortal-icon-theme.sh 
# echo "COMPLETE. You now have 'qortal-hub' 'qortal' 'qortal-ui' and 'qortal-menu-button' through 'qortal-menu-button-4' icons usable throughout system on main account."
# echo 
# echo "(again, menu button icon may require a restart to display properly."
# sleep 5
# echo "removing startup script and closing in 5 seconds"
# sleep 4
# rm ".config/autostart/apply-qortal-icons.desktop"
# exit

# EOL

# chmod +x apply-icon-theme-first-boot.sh

./add-qortal-icon-theme.sh
cd "${HOME}"

### CRONTAB SETUP ###
echo "${YELLOW} SETTING CRONTAB TASKS ${NC}\n"

{
  echo "1 1 */3 * * ${HOME}/auto-fix-qortal.sh > \"${HOME}/qortal/auto-fix-01.log\" 2>&1"
} > rebuilt-machine-cron

crontab rebuilt-machine-cron
rm -f rebuilt-machine-cron rebuilt-machine*.txt configure-terminal-and-more.sh cinnamon-settings.json

echo "${YELLOW} Refreshing Cinnamon Panel/Menu to apply changes ${NC}"
cinnamon --replace > /dev/null 2>&1 &

echo "${GREEN} SETUP COMPLETE! CINNAMON WILL BE USED ON NEXT LOGIN. REBOOTING IN 30 SECONDS (use cntrl+c to CANCEL reboot within next 30 seconds if you do not want to reboot now... NOTE - YOU MUST REBOOT TO FINISH ALL SETUP. IF CINNAMON DESKTOP IS NOT SELECTED, SELECT IT PRIOR TO INPUTTING LOGIN PASSWORD UPON REBOOT.)${NC}\n"
sleep 10
echo "${YELLOW}20 seconds remaining...${NC}\n"
sleep 9 
echo "${RED}10 Seconds remaining...${NC}\n"
sleep 4
echo "${RED}5 seconds remaining...${NC}\n"
sleep 3 
echo "${GREEN} REBOOTING MACHINE NOW!${NC}\n"
sudo reboot

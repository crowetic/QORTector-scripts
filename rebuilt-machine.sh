#!/bin/bash

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

download_with_retry() {
  local url="$1"
  local output="$2"
  local attempts="${3:-6}"
  local try=1
  local backoff=2
  local tmp="${output}.part"

  rm -f "$tmp"

  if command -v wget >/dev/null 2>&1; then
    while [ "$try" -le "$attempts" ]; do
      echo "${CYAN} 🌐 Download attempt ${try}/${attempts} (wget): ${url} ${NC}"
      if wget --tries=1 --timeout=30 --continue -O "$tmp" "$url" && [ -s "$tmp" ]; then
        mv -f "$tmp" "$output"
        return 0
      fi
      if [ "$try" -lt "$attempts" ]; then
        echo "${YELLOW} ⚠️ wget attempt failed. Retrying in ${backoff}s... ${NC}"
        sleep "$backoff"
        if [ "$backoff" -lt 20 ]; then
          backoff=$((backoff * 2))
          [ "$backoff" -gt 20 ] && backoff=20
        fi
      fi
      try=$((try + 1))
    done

    echo "${YELLOW} ⚠️ wget retries exhausted. Trying curl fallback... ${NC}"
    if curl --fail --location --show-error --http1.1 --continue-at - --output "$tmp" "$url" && [ -s "$tmp" ]; then
      mv -f "$tmp" "$output"
      return 0
    fi
  else
    while [ "$try" -le "$attempts" ]; do
      echo "${CYAN} 🌐 Download attempt ${try}/${attempts} (curl): ${url} ${NC}"
      if curl --fail --location --show-error --http1.1 --continue-at - --output "$tmp" "$url" && [ -s "$tmp" ]; then
        mv -f "$tmp" "$output"
        return 0
      fi
      if [ "$try" -lt "$attempts" ]; then
        echo "${YELLOW} ⚠️ curl attempt failed. Retrying in ${backoff}s... ${NC}"
        sleep "$backoff"
        if [ "$backoff" -lt 20 ]; then
          backoff=$((backoff * 2))
          [ "$backoff" -gt 20 ] && backoff=20
        fi
      fi
      try=$((try + 1))
    done
  fi

  rm -f "$tmp"
  echo "${RED} ❌ Failed to download: ${url} ${NC}"
  return 1
}

echo "${YELLOW} 🛠 UPDATING 🛠 UBUNTU AND INSTALLING REQUIRED SOFTWARE 📦 PACKAGES 📦 ${NC}\n"

echo "${YELLOW} ⚙️ creating system folders that require admin permissions... and disabling 'ubuntu pro' notices in terminal..."
sudo pro config set apt_news=false

sudo apt update
sudo apt -y upgrade
sudo apt -y install git jq gnome-software openssh-server unzip vim curl wget ca-certificates openjdk-21-jre yaru-theme-icon yaru-theme-gtk yaru-theme-unity zlib1g-dev vlc chromium-browser p7zip-full htop net-tools bpytop ffmpeg sysbench smartmontools ksnip xsensors fonts-symbola lm-sensors gparted cinnamon-desktop-environment
sudo apt -y install libfuse2t64 || sudo apt -y install libfuse2 || true

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

### RUN FULL QORTAL SETUP ###
echo "${YELLOW} ⚙️ RUNNING FULL QORTAL SETUP VIA Qortal-Setup-Linux.sh ${NC}\n"
if [ -f "${SCRIPT_DIR}/Qortal-Setup-Linux.sh" ]; then
  chmod +x "${SCRIPT_DIR}/Qortal-Setup-Linux.sh"
  bash "${SCRIPT_DIR}/Qortal-Setup-Linux.sh"
else
  echo "${RED}❌ Could not find ${SCRIPT_DIR}/Qortal-Setup-Linux.sh${NC}"
  exit 1
fi


### DOWNLOAD EXTRA FILES ###
cd "${HOME}"

download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh" "refresh-qortal.sh" 5
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh" "auto-fix-qortal.sh" 5
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh" "check-qortal-status.sh" 5
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh" "start-qortal.sh" 5
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal-core.sh" "start-qortal-core.sh" 5
#todo update the download location below to multiple locations and QDN location
download_with_retry "https://cloud.qortal.org/s/machinefilesnew/download" "download" 6

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
gsettings set org.cinnamon.desktop.wm.preferences theme "Windows-10"
gsettings set org.cinnamon.desktop.interface gtk-theme "Windows-10-Dark"
gsettings set org.cinnamon.theme name "Windows-10"
gsettings set org.cinnamon.desktop.interface icon-theme "Yaru-blue-dark"
gsettings set org.cinnamon.desktop.background picture-uri "file://$HOME/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

echo "Downloading additional settings..."
if command -v wget >/dev/null 2>&1; then
  wget -O cinnamon-settings.json "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/cinnamon-settings.json"
else
  curl -L -o cinnamon-settings.json "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/cinnamon-settings.json"
fi
mkdir -p "${HOME}/.cinnamon/configs/menu@cinnamon.org"

# Copy your preconfigured menu JSON
cp cinnamon-settings.json "${HOME}/.cinnamon/configs/menu@cinnamon.org/0.json"

echo "${CYAN} Adding CUSTOM QORTAL ICON THEME...${NC}\n"
if command -v wget >/dev/null 2>&1; then
  wget -O add-qortal-icon-theme.sh "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/add-qortal-icon-theme.sh"
else
  curl -L -o add-qortal-icon-theme.sh "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/add-qortal-icon-theme.sh"
fi
chmod +x add-qortal-icon-theme.sh
./add-qortal-icon-theme.sh

EOL

chmod +x "$HOME/apply-cinnamon-settings.sh"

echo "${GREEN} ⬇️ Downloading additional ${NC}${YELLOW}CINNAMON${NC}${GREEN}settings${NC}\n"

download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/cinnamon-settings.json" "cinnamon-settings.json" 5
mkdir -p "${HOME}/.cinnamon/configs/menu@cinnamon.org"
cp cinnamon-settings.json "${HOME}/.cinnamon/configs/menu@cinnamon.org/0.json"

echo "${YELLOW} Configuring terminal, default apps, and more...${NC}\n"
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/configure-terminal-and-more.sh" "configure-terminal-and-more.sh" 5
chmod +x configure-terminal-and-more.sh
./configure-terminal-and-more.sh 
cd "${HOME}"

echo "continuing desktop configuration..."

mkdir -p "$HOME/.config/autostart"
mkdir -p "$HOME/.local/share/applications"

cat > "$HOME/.local/share/applications/apply-cinnamon-settings.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=gnome-terminal -- ${HOME}/apply-cinnamon-settings.sh
Hidden=false
NoDisplay=false
Name=Apply Cinnamon Settings
Comment=Reapplies Cinnamon panel, theme, and menu customizations
EOL

cat > "${HOME}/.config/autostart/auto-fix-qortal-GUI.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=gnome-terminal -- ${HOME}/auto-fix-qortal.sh
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
Exec=${HOME}/start-qortal-core.sh
X-GNOME-Autostart-enabled=true
NoDisplay=false
Hidden=false
Name[en_US]=start-qortal
Comment[en_US]=start qortal core 6 seconds after boot
X-GNOME-Autostart-Delay=6
EOL

echo "${CYAN} Adding CUSTOM QORTAL ICON THEME...${NC}\n"
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/add-qortal-icon-theme.sh" "add-qortal-icon-theme.sh" 5
chmod +x add-qortal-icon-theme.sh

./add-qortal-icon-theme.sh

echo "${YELLOW} 🔄 Forcing Cinnamon Menu Refresh...${NC}"
cinnamon --replace > /dev/null 2>&1 &

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

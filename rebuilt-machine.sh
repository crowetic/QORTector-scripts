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
QORTAL_SETUP_URL="https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/Qortal-Setup-Linux.sh"

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

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_headless_mode() {
  if [ "${REBUILT_MACHINE_HEADLESS:-0}" = "1" ]; then
    return 0
  fi

  if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
    return 1
  fi

  if [ -d /usr/share/xsessions ] || [ -d /usr/share/wayland-sessions ]; then
    return 1
  fi

  return 0
}

install_packages_if_available() {
  local package

  for package in "$@"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      echo "${CYAN} 📦 Installing package: ${package} ${NC}"
      sudo apt-get install -y "$package"
    else
      echo "${YELLOW} ⚠️ Package not available on this system, skipping: ${package} ${NC}"
    fi
  done
}

install_first_available_package() {
  local package

  for package in "$@"; do
    if apt-cache show "$package" >/dev/null 2>&1; then
      echo "${CYAN} 📦 Installing preferred package: ${package} ${NC}"
      sudo apt-get install -y "$package"
      return 0
    fi
  done

  return 1
}

ensure_qortal_setup_script() {
  local local_script="${SCRIPT_DIR}/Qortal-Setup-Linux.sh"
  local fallback_script="${HOME}/Qortal-Setup-Linux.sh"

  QORTAL_SETUP_SCRIPT=""

  if [ -f "$local_script" ]; then
    QORTAL_SETUP_SCRIPT="$local_script"
    return 0
  fi

  echo "${YELLOW} ⚠️ Local Qortal-Setup-Linux.sh not found. Downloading a fresh copy... ${NC}"

  if download_with_retry "$QORTAL_SETUP_URL" "$fallback_script" 6; then
    chmod +x "$fallback_script"
    QORTAL_SETUP_SCRIPT="$fallback_script"
    return 0
  fi

  return 1
}

HEADLESS_MODE=false
if is_headless_mode; then
  HEADLESS_MODE=true
fi

echo "${YELLOW} 🛠 UPDATING 🛠 UBUNTU AND INSTALLING REQUIRED SOFTWARE 📦 PACKAGES 📦 ${NC}\n"
echo "${CYAN} ℹ️ Detected install mode: $( [ "$HEADLESS_MODE" = true ] && echo "headless/server" || echo "desktop" ) ${NC}\n"

echo "${YELLOW} ⚙️ creating system folders that require admin permissions... and disabling 'ubuntu pro' notices in terminal..."
if command_exists pro; then
  sudo pro config set apt_news=false || true
fi

sudo apt-get update
sudo apt-get -y upgrade

install_packages_if_available \
  git jq openssh-server unzip vim curl wget ca-certificates zlib1g-dev \
  p7zip-full htop net-tools bpytop ffmpeg sysbench smartmontools \
  fonts-symbola lm-sensors rsync xdg-utils

install_first_available_package \
  openjdk-21-jre openjdk-21-jre-headless openjdk-17-jre openjdk-17-jre-headless || \
  echo "${YELLOW} ⚠️ Unable to install a supported Java runtime automatically. ${NC}"

install_first_available_package libfuse2t64 libfuse2 || true

if [ "$HEADLESS_MODE" = false ]; then
  install_packages_if_available \
    gnome-software yaru-theme-icon yaru-theme-gtk yaru-theme-unity \
    vlc chromium-browser ksnip xsensors gparted cinnamon-desktop-environment \
    gnome-terminal dconf-cli gedit eog evince
else
  echo "${CYAN} ℹ️ Headless mode detected. Skipping Cinnamon and GUI package installation. ${NC}\n"
fi

if [ "$HEADLESS_MODE" = false ]; then
  echo "${YELLOW} 📦 INSTALLING SENSORS MONITOR APPLET FOR PANEL...${NC}\n"

  mkdir -p "${HOME}/.local/share/cinnamon/applets"
  cd "${HOME}/.local/share/cinnamon/applets" || exit 1
  if download_with_retry "https://cinnamon-spices.linuxmint.com/files/applets/Sensors@claudiux.zip" "sensors-monitor.zip" 5; then
    unzip -o sensors-monitor.zip -d Sensors@claudiux
    rm -f sensors-monitor.zip
    echo "✅ Applet installed. You can now add 'Sensors Monitor' to your panel manually."
  else
    echo "${YELLOW} ⚠️ Could not download the Sensors Monitor applet. Continuing without it. ${NC}"
  fi
  cd "${HOME}" || exit 1

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
else
  echo "${CYAN} ℹ️ Headless mode detected. Skipping Cinnamon session configuration. ${NC}\n"
fi

### RUN FULL QORTAL SETUP ###
echo "${YELLOW} ⚙️ RUNNING FULL QORTAL SETUP VIA Qortal-Setup-Linux.sh ${NC}\n"
if ensure_qortal_setup_script && [ -n "$QORTAL_SETUP_SCRIPT" ] && [ -f "$QORTAL_SETUP_SCRIPT" ]; then
  chmod +x "$QORTAL_SETUP_SCRIPT"
  bash "$QORTAL_SETUP_SCRIPT"
else
  echo "${RED}❌ Could not obtain Qortal-Setup-Linux.sh automatically.${NC}"
  exit 1
fi


### DOWNLOAD EXTRA FILES ###
cd "${HOME}" || exit 1

download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh" "refresh-qortal.sh" 5
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh" "auto-fix-qortal.sh" 5
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh" "check-qortal-status.sh" 5
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh" "start-qortal.sh" 5
download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal-core.sh" "start-qortal-core.sh" 5
#todo update the download location below to multiple locations and QDN location
download_with_retry "https://cloud.qortal.org/s/machinefilesnew/download" "download" 6

chmod +x ./*.sh 2>/dev/null || true

if unzip -o download >/dev/null 2>&1 && [ -d Machine-files ]; then
  rsync -raPz Machine-files/ "${HOME}/"
else
  echo "${YELLOW} ⚠️ Could not unpack Machine-files bundle cleanly. Continuing with the rest of setup. ${NC}"
fi


rm -rf download Machine-files
if [ "$HEADLESS_MODE" = false ]; then
  ### CINNAMON THEMING ###
  echo "${YELLOW} 📦 INSTALLING WINDOWS 10 THEMES FOR CINNAMON ${NC}\n"

  mkdir -p "${HOME}/.themes"

  if [ ! -d "${HOME}/.themes/Windows-10" ]; then
    if download_with_retry "https://cinnamon-spices.linuxmint.com/files/themes/Windows-10.zip?time=$(date +%s)" "Windows-10.zip" 5; then
      unzip -o Windows-10.zip >/dev/null 2>&1
      mv -f Windows-10 "${HOME}/.themes/" 2>/dev/null || true
      rm -f Windows-10.zip
    else
      echo "${YELLOW} ⚠️ Unable to download Windows-10 Cinnamon theme. Continuing. ${NC}"
    fi
  fi

  if [ ! -d "${HOME}/.themes/Windows-10-Dark" ]; then
    git clone https://github.com/B00merang-Project/Windows-10-Dark.git "${HOME}/.themes/Windows-10-Dark" || true
  fi

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
gsettings set org.cinnamon.desktop.wm.preferences theme "Windows-10" || true
gsettings set org.cinnamon.desktop.interface gtk-theme "Windows-10-Dark" || true
gsettings set org.cinnamon.theme name "Windows-10" || true
gsettings set org.cinnamon.desktop.interface icon-theme "Yaru-blue-dark" || true
gsettings set org.cinnamon.desktop.background picture-uri "file://$HOME/Pictures/wallpapers/Qortal-TheFuture-Wallpaper.png" || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true

echo "Downloading additional settings..."
if command -v wget >/dev/null 2>&1; then
  wget -O cinnamon-settings.json "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/cinnamon-settings.json"
else
  curl -L -o cinnamon-settings.json "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/cinnamon-settings.json"
fi
mkdir -p "${HOME}/.cinnamon/configs/menu@cinnamon.org"

cp cinnamon-settings.json "${HOME}/.cinnamon/configs/menu@cinnamon.org/0.json"

if command -v wget >/dev/null 2>&1; then
  wget -O add-qortal-icon-theme.sh "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/add-qortal-icon-theme.sh"
else
  curl -L -o add-qortal-icon-theme.sh "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/add-qortal-icon-theme.sh"
fi
chmod +x add-qortal-icon-theme.sh
./add-qortal-icon-theme.sh || true
EOL

  cat > "$HOME/run-script-in-terminal.sh" <<'EOL'
#!/bin/bash
TARGET_SCRIPT="$1"
shift || true

if [ -z "$TARGET_SCRIPT" ] || [ ! -x "$TARGET_SCRIPT" ]; then
  echo "Target script is missing or not executable: $TARGET_SCRIPT"
  exit 1
fi

if command -v gnome-terminal >/dev/null 2>&1; then
  exec gnome-terminal -- "$TARGET_SCRIPT" "$@"
elif command -v mate-terminal >/dev/null 2>&1; then
  exec mate-terminal -- "$TARGET_SCRIPT" "$@"
elif command -v xfce4-terminal >/dev/null 2>&1; then
  exec xfce4-terminal -e "$TARGET_SCRIPT"
elif command -v x-terminal-emulator >/dev/null 2>&1; then
  exec x-terminal-emulator -e "$TARGET_SCRIPT"
else
  exec "$TARGET_SCRIPT" "$@"
fi
EOL

  chmod +x "$HOME/apply-cinnamon-settings.sh" "$HOME/run-script-in-terminal.sh"

  echo "${GREEN} ⬇️ Downloading additional ${NC}${YELLOW}CINNAMON${NC}${GREEN}settings${NC}\n"

  download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/cinnamon-settings.json" "cinnamon-settings.json" 5
  mkdir -p "${HOME}/.cinnamon/configs/menu@cinnamon.org"
  cp -f cinnamon-settings.json "${HOME}/.cinnamon/configs/menu@cinnamon.org/0.json"

  echo "${YELLOW} Configuring terminal, default apps, and more...${NC}\n"
  if download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/configure-terminal-and-more.sh" "configure-terminal-and-more.sh" 5; then
    chmod +x configure-terminal-and-more.sh
    ./configure-terminal-and-more.sh || echo "${YELLOW} ⚠️ Desktop preference configuration returned a non-zero status. Continuing. ${NC}"
  fi
  cd "${HOME}" || exit 1

  echo "continuing desktop configuration..."

  mkdir -p "$HOME/.config/autostart"
  mkdir -p "$HOME/.local/share/applications"

  cat > "$HOME/.local/share/applications/apply-cinnamon-settings.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=${HOME}/run-script-in-terminal.sh ${HOME}/apply-cinnamon-settings.sh
Hidden=false
NoDisplay=false
Name=Apply Cinnamon Settings
Comment=Reapplies Cinnamon panel, theme, and menu customizations
EOL

  cat > "${HOME}/.config/autostart/auto-fix-qortal-GUI.desktop" <<EOL
[Desktop Entry]
Type=Application
Exec=${HOME}/run-script-in-terminal.sh ${HOME}/auto-fix-qortal.sh
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
  if download_with_retry "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/add-qortal-icon-theme.sh" "add-qortal-icon-theme.sh" 5; then
    chmod +x add-qortal-icon-theme.sh
    ./add-qortal-icon-theme.sh || true
  fi

  echo "${YELLOW} 🔄 Forcing Cinnamon Menu Refresh...${NC}"
  if command_exists cinnamon; then
    cinnamon --replace > /dev/null 2>&1 &
  fi
else
  echo "${CYAN} ℹ️ Headless mode detected. Skipping Cinnamon theming, applets, autostart launchers, and desktop preference setup. ${NC}\n"
fi

### CRONTAB SETUP ###
echo "${YELLOW} SETTING CRONTAB TASKS ${NC}\n"

{
  echo "1 1 */3 * * ${HOME}/auto-fix-qortal.sh > \"${HOME}/qortal/auto-fix-01.log\" 2>&1"
} > rebuilt-machine-cron

crontab rebuilt-machine-cron
rm -f rebuilt-machine-cron rebuilt-machine*.txt configure-terminal-and-more.sh cinnamon-settings.json

if [ "$HEADLESS_MODE" = false ]; then
  echo "${YELLOW} Refreshing Cinnamon Panel/Menu to apply changes ${NC}"
  if command_exists cinnamon; then
    cinnamon --replace > /dev/null 2>&1 &
  fi
fi

if [ "$HEADLESS_MODE" = false ]; then
  echo "${GREEN} SETUP COMPLETE! CINNAMON WILL BE USED ON NEXT LOGIN. REBOOTING IN 30 SECONDS (use cntrl+c to CANCEL reboot within next 30 seconds if you do not want to reboot now... NOTE - YOU MUST REBOOT TO FINISH ALL SETUP. IF CINNAMON DESKTOP IS NOT SELECTED, SELECT IT PRIOR TO INPUTTING LOGIN PASSWORD UPON REBOOT.)${NC}\n"
else
  echo "${GREEN} SETUP COMPLETE! HEADLESS MODE CHANGES ARE FINISHED. REBOOTING IN 30 SECONDS (use cntrl+c to CANCEL reboot within next 30 seconds if you do not want to reboot now.)${NC}\n"
fi
sleep 10
echo "${YELLOW}20 seconds remaining...${NC}\n"
sleep 9 
echo "${RED}10 Seconds remaining...${NC}\n"
sleep 4
echo "${RED}5 seconds remaining...${NC}\n"
sleep 3 
echo "${GREEN} REBOOTING MACHINE NOW!${NC}\n"
sudo reboot

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

check_distro() {
  if command -v apt > /dev/null; then
    echo "${YELLOW} Detected Debian-based distribution. Proceeding with installation... ${NC}\n"
  else
    echo "${RED} Unsupported Linux distribution. Exiting... ${NC}\n"
    exit 1
  fi
}

check_display() {
  if command -v xrandr > /dev/null; then
    DISPLAY_AVAILABLE=true
  else
    DISPLAY_AVAILABLE=false
  fi
}

update_and_install_packages() {
  echo "${YELLOW} UPDATING DEBIAN-BASED SYSTEM AND INSTALLING REQUIRED SOFTWARE PACKAGES ${NC}\n"
  
  sudo apt update
  sudo apt -y --purge remove ubuntu-advantage-tools
  sudo apt -y upgrade

  PACKAGES="gnome-software unzip vim curl openjdk-17-jre zlib1g-dev vlc chromium-browser p7zip-full libfuse2 htop net-tools bpytop ffmpeg sysbench smartmontools ksnip xsensors fonts-symbola lm-sensors"

  if [ "$DISPLAY_AVAILABLE" = true ]; then
    PACKAGES="$PACKAGES cinnamon-desktop-environment"
  fi

  for PACKAGE in $PACKAGES; do
    if ! sudo dpkg -l | grep -qw $PACKAGE; then
      echo "${YELLOW} Installing $PACKAGE... ${NC}"
      sudo apt -y install $PACKAGE
    else
      echo "${GREEN} $PACKAGE is already installed. Skipping... ${NC}"
    fi
  done
}

check_qortal_version() {
  echo "${YELLOW} Checking the version of qortal on local machine VS the version on github... ${NC}\n"

  core_running=$(curl -s localhost:12391/admin/status)
  if [ -z "$core_running" ]; then 
    echo "${RED} CORE DOES NOT SEEM TO BE RUNNING, WAITING 1 MINUTE IN CASE IT IS STILL STARTING UP... ${NC}\n"
    sleep 60
  fi

  LOCAL_VERSION=$(curl -s localhost:12391/admin/info | grep -oP '"buildVersion":"qortal-\K[^-]*' | sed 's/-.*//' | tr -d '.')
  REMOTE_VERSION=$(curl -s "https://api.github.com/repos/qortal/qortal/releases/latest" | grep -oP '"tag_name": "v\K[^"]*' | tr -d '.')

  if [ "$LOCAL_VERSION" -ge "$REMOTE_VERSION" ]; then
    echo "${GREEN} Local version is higher than or equal to the remote version, no qortal updates needed... continuing...${NC}\n"
    return 1
  else
    echo "${YELLOW} Updating Qortal Core to version $REMOTE_VERSION... ${NC}\n"
    return 0
  fi
}

download_qortal_core() {
  if [ $SHOULD_UPDATE_QORTAL -eq 0 ]; then
    cd
    if [ -d qortal ]; then
      echo "${PURPLE} qortal DIRECTORY FOUND, BACKING UP ORIGINAL TO '~/backups' AND RE-INSTALLING ${NC}\n"
      mkdir -p ~/backups
      mv -f ~/qortal ~/backups/
    fi
    curl -L -O https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
    unzip qortal*.zip
    rm -rf qortal*.zip
    cd ~/qortal
    rm -rf settings.json
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/settings.json
    chmod +x *.sh
    curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/tools/qort
    chmod +x qort
    echo "$REMOTE_VERSION" > version.txt
    cd
  fi
}

download_qortal_ui() {
  ARCHITECTURE=$(uname -m)
  if [ -f ~/qortal/Qortal-UI ]; then
    echo "${PURPLE} PREVIOUS Qortal-UI FOUND, BACKING UP ORIGINAL TO '~/backups/' AND RE-INSTALLING ${NC}\n"
    mv ~/qortal/Qortal-UI ~/backups/
  fi 
  cd ~/qortal
  if [ "$ARCHITECTURE" = "aarch64" ] || [ "$ARCHITECTURE" = "arm64" ]; then
    curl -L -O https://github.com/Qortal/qortal-ui/releases/latest/download/Qortal-Setup-arm64.AppImage
    mv Qortal-Setup-arm64.AppImage Qortal-UI
  else
    curl -L -O https://github.com/Qortal/qortal-ui/releases/latest/download/Qortal-Setup-amd64.AppImage
    mv Qortal-Setup-amd64.AppImage Qortal-UI
  fi
  chmod +x Qortal-UI
  cd
}

download_other_files() {
  echo "${YELLOW} DOWNLOADING PICTURE FILES AND OTHER SCRIPTS ${NC}\n"
  cd
  curl -L -O https://cloud.qortal.org/s/t4Fy8Lp4kQYiYZN/download/Machine-files.zip
  curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh
  curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
  curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh
  curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh
  chmod +x *.sh

  curl -L -O https://cloud.qortal.org/s/6d8qoEkQRDSCTqn/download/rebuilt-machine-setup.txt
  mv -f ~/rebuilt-machine-setup.txt ~/Desktop
  
  if [ -d ~/Pictures/wallpapers ]; then
    echo "${PURPLE} PREVIOUS wallpapers folder FOUND, BACKING UP ORIGINAL TO '~/backups/' AND RE-INSTALLING ${NC}\n"
    mkdir -p ~/backups
    mv -f ~/Pictures/wallpapers ~/backups/
  fi
  if [ -d ~/Pictures/icons ]; then
    echo "${PURPLE} PREVIOUS icons folder FOUND, BACKING UP ORIGINAL TO '~/backups/' AND RE-INSTALLING ${NC}\n"
    mkdir -p ~/backups
    mv -f ~/Pictures/icons ~/backups/
  fi
  
  unzip Machine-files.zip
  mv -f ~/Machine-files/Pictures ~/Pictures/
}

setup_cron_jobs() {
  echo "${YELLOW} SETTING UP CRON JOBS ${NC}\n"
  username=$(whoami)
  echo "@reboot sleep 399 && /home/${username}/auto-fix-qortal.sh > \"/home/${username}/qortal/auto-fix-startup.log\" 2>&1" >> "rebuilt-machine-cron"
  echo "1 1 */3 * * /home/${username}/auto-fix-qortal.sh > \"/home/${username}/qortal/auto-fix-01.log\" 2>&1" >> "rebuilt-machine-cron"
  chmod +x *.sh
  crontab rebuilt-machine-cron
  rm -rf Machine-files Machine-files.zip rebuilt-machine-cron
}

finish_up() {
  echo "${YELLOW} SCRIPT EXECUTION FOR INSTALL SCRIPT COMPLETE.${NC} ${RED}RESTARTING MACHINE IS RECOMMENDED.${NC}${GREEN} IF YOU ARE RUNNING THE GATEWAY NODE SETUP SCRIPT IT SHOULD CONTINUE NOW ON ITS OWN. ${NC}\n"
}

# Main script execution
check_distro
check_display
update_and_install_packages
check_qortal_version
SHOULD_UPDATE_QORTAL=$?
download_qortal_core
download_qortal_ui
download_other_files
setup_cron_jobs
finish_up


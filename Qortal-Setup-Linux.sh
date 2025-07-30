#!/bin/bash
set -e
trap 'echo -e "\n${RED}❌ Setup cancelled by user. Exiting...${NC}"; exit 1' INT

# Color Codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

intro_block='
---------------------------------------- 
-Qortal Universal Linux Install Script -
----------------------------------------
--------------------------------------------------------------------------------
-(a fully featured setup script for Qortal and Qortal Hub on any Linux Desktop)- 
--------------------------------------------------------------------------------
'
text_001='
This script will:
'
text_002='- Configure target machine as a fully functional Qortal Node'
text_003='- Setup both Qortal Core (qortal) and Qortal Hub (Qortal-Hub) in "${HOME}/qortal"'
text_004='- Correctly establish launchers for Qortal Hub'
text_005='- Correctly create entries in desktop environment menus for Qortal Hub'
text_006='- Ensure Qortal Hub has required no-sandbox flag if system requires it'
text_007='- Ensure all configuration is optimal'
text_008='- Offer to establish automatic Qortal Node checker script that ensures node is always synchronized/updated/ready to use.'
text_009='... AND MUCH MORE! This all ensures that your machine is the most optimal Qortal node possible! '
text_010='Script written by: crowetic'
text_011='Reach out with any questions or issues. This script is meant to work on any Desktop Linux distribution, but if any issues pop up, please let us know!'
text_012='THANK YOU, AND WELCOME TO THE TRUE NEXT GENERATION OF THE INTERNET, QORTAL!'
text_013='Script will now begin... You will need to input system password once at the start. (NOTE - On most terminals you will not see anything while typing password. Just type and push ENTER.)'


echo -e "$intro_block"
sleep 1
echo -e "$text_001"; sleep 1
echo -e "$text_002"; sleep 0.5
echo -e "$text_003"; sleep 0.5
echo -e "$text_004"; sleep 0.5
echo -e "$text_005"; sleep 0.5
echo -e "$text_006"; sleep 0.5
echo -e "$text_007"; sleep 0.5
echo -e "$text_008"; sleep 0.5
echo -e "$text_009"; sleep 0.5
echo
echo -e "$text_010"; sleep 0.5
echo
echo -e "$text_011"; sleep 0.5
echo
echo -e "${CYAN}$text_012${NC}"; sleep 1
echo
echo
echo -e "$text_013"
echo


BACKUP_EXECUTED=false
QORTAL_CORE_GOOD=false


# --- Distro + Package Manager detection (robust) ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID,,}"
    DISTRO_VER="$VERSION_ID"
    DISTRO_LIKE="${ID_LIKE,,}"
else
    echo -e "${RED}❌ Cannot detect Linux distribution. Please install dependencies manually.${NC}"
    exit 1
fi

# Allow override for testing: export QSL_FORCE_FAMILY=debian|rhel|arch|suse|alpine
FAMILY=""
if [ -n "${QSL_FORCE_FAMILY:-}" ]; then
    FAMILY="$QSL_FORCE_FAMILY"
else
    if [[ "$DISTRO_ID" == "ubuntu" || "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "linuxmint" || "$DISTRO_ID" == "raspbian" || "$DISTRO_LIKE" == *"debian"* || "$DISTRO_LIKE" == *"ubuntu"* ]]; then
        FAMILY="debian"
    elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "centos" || "$DISTRO_ID" == "rocky" || "$DISTRO_ID" == "almalinux" || "$DISTRO_LIKE" == *"rhel"* || "$DISTRO_LIKE" == *"fedora"* ]]; then
        FAMILY="rhel"
    elif [[ "$DISTRO_ID" == "arch" || "$DISTRO_ID" == "manjaro" || "$DISTRO_LIKE" == *"arch"* ]]; then
        FAMILY="arch"
    elif [[ "$DISTRO_ID" == "opensuse-tumbleweed" || "$DISTRO_ID" == "opensuse-leap" || "$DISTRO_ID" == "sles" || "$DISTRO_LIKE" == *"suse"* ]]; then
        FAMILY="suse"
    elif [[ "$DISTRO_ID" == "alpine" ]]; then
        FAMILY="alpine"
    fi
fi

# sudo wrapper (don’t use sudo if already root)
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

echo -e "${YELLOW}📋 Detected distro:${NC} ${GREEN}${DISTRO_ID}${NC} ${CYAN}${DISTRO_VER}${NC}  (family=${FAMILY:-unknown})"

echo -e "${CYAN}🔧 Installing dependencies...${NC}"

set +e  # we'll handle fallbacks manually in this block

case "$FAMILY" in
    debian)
        $SUDO apt-get update -y
        # Try JRE 17 (headless acceptable), and libfuse2 for AppImage (Hub)
        $SUDO apt-get install -y curl unzip jq imagemagick zlib1g-dev || true
        $SUDO apt-get install -y openjdk-17-jre || $SUDO apt-get install -y openjdk-17-jre-headless || true
        $SUDO apt-get install -y libfuse2 || true
        ;;
    rhel)
        # dnf or yum
        PM="dnf"; command -v dnf >/dev/null 2>&1 || PM="yum"
        $SUDO $PM -y install curl unzip jq ImageMagick zlib-devel || true
        $SUDO $PM -y install java-17-openjdk || true
        # FUSE2 is typically 'fuse' (FUSE3 is 'fuse3'); AppImage needs FUSE2
        $SUDO $PM -y install fuse || true
        ;;
    arch)
        $SUDO pacman -Sy --noconfirm --needed curl unzip jq zlib imagemagick || true
        $SUDO pacman -Sy --noconfirm --needed jre17-openjdk || true
        # AppImage needs FUSE2 on Arch
        $SUDO pacman -Sy --noconfirm --needed fuse2 || true
        ;;
    suse)
        $SUDO zypper -n refresh
        $SUDO zypper -n install curl unzip jq ImageMagick zlib-devel || true
        $SUDO zypper -n install java-17-openjdk || true
        # FUSE2 compat (package names vary by SUSE version); try both
        $SUDO zypper -n install fuse || true
        $SUDO zypper -n install fuse2 || true
        ;;
    alpine)
        $SUDO apk update
        # Alpine package names differ slightly; prefer openjdk17-jre
        $SUDO apk add --no-cache curl unzip jq imagemagick zlib-dev || true
        $SUDO apk add --no-cache openjdk17-jre || $SUDO apk add --no-cache openjdk17 || true
        # Alpine uses fuse (may need fuse-openrc on non-systemd)
        $SUDO apk add --no-cache fuse || true
        ;;
    *)
        echo -e "${RED}⚠️ Unsupported or unknown distro family (ID=${DISTRO_ID}, LIKE=${DISTRO_LIKE}).${NC}"
        echo -e "${YELLOW}Please install manually: Java 17 JRE, curl, unzip, jq, zlib dev headers, ImageMagick, and FUSE2 (for AppImage).${NC}"
        ;;
esac

set -e

# Post-checks: warn if critical bits missing
MISSING=()
command -v java >/dev/null 2>&1 || MISSING+=("java-17")
command -v curl >/dev/null 2>&1 || MISSING+=("curl")
command -v unzip >/dev/null 2>&1 || MISSING+=("unzip")
command -v jq >/dev/null 2>&1 || MISSING+=("jq")
command -v convert >/dev/null 2>&1 || MISSING+=("ImageMagick")

if [ "${#MISSING[@]}" -gt 0 ]; then
    echo -e "${RED}❌ Missing required tools: ${MISSING[*]}${NC}"
    echo -e "${YELLOW}Install them with your package manager, then re-run the script.${NC}"
    exit 1
fi

# FUSE/AppImage fallback note: If libfuse2 isn't available, Hub can still run with extraction.
if ! ldconfig -p 2>/dev/null | grep -q 'libfuse.so.2'; then
    echo -e "${YELLOW}⚠️ libfuse2 not found. AppImages may fail to mount. We'll fall back to extraction mode when launching the Hub.${NC}"
    export APPIMAGE_EXTRACT_AND_RUN=1
fi


if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ] || [ -d "${HOME}/Desktop" ]; then
    if [ ! -f /usr/share/desktop-directories/Qortal.directory ]; then
    echo -e "${CYAN}📁 Installing system-wide Qortal.directory category...${NC}"
    echo "[Desktop Entry]
Name=Qortal
Icon=qortal-menu-button-3
Type=Directory" | sudo tee /usr/share/desktop-directories/Qortal.directory > /dev/null
    fi
fi

# Download and Install Qortal Core
echo -e "${CYAN}⬇️ Downloading Qortal Core...${NC}"
cd "$HOME"

QORTAL_DIR="$HOME/qortal"
BACKUP_DIR="$HOME/backups/qortal-$(date +%s)"

function stop_qortal_core() {
    echo -e "${CYAN}Stopping Qortal Core...${NC}"
    if [ -f "$QORTAL_DIR/stop.sh" ]; then
        bash "$QORTAL_DIR/stop.sh"
    elif [ -f "$QORTAL_DIR/apikey.txt" ]; then
        curl -sf -X POST "http://localhost:12391/admin/stop" \
            -H "X-API-KEY: $(cat "$QORTAL_DIR/apikey.txt")"
    fi
    echo -e "${CYAN}Sleeping 15s to ensure shutdown...${NC}"
    sleep 15
}

function backup_qortal_dir() {
    mkdir -p "$HOME/backups"
    echo -e "${YELLOW}⚠️ Backing up existing Qortal directory to $BACKUP_DIR...${NC}"
    mv "$QORTAL_DIR" "$BACKUP_DIR"
    BACKUP_EXECUTED=true
}

QORTAL_RUNNING=false
QORTAL_SYNCED=false
BACKUP_EXECUTED=false

if [ -d "$QORTAL_DIR" ]; then
    if pgrep -f "qortal.jar" > /dev/null && curl -sf "http://localhost:12391/admin/status" | grep -q "height"; then
        STATUS_JSON=$(curl -s "http://localhost:12391/admin/status")
        IS_SYNCING=$(echo "$STATUS_JSON" | jq -r '.isSynchronizing')
        SYNC_PERCENT=$(echo "$STATUS_JSON" | jq -r '.syncPercent')

        echo "🛰️ ${YELLOW}Syncing:${NC} ${CYAN}$IS_SYNCING${NC}"
        echo "📊 ${YELLOW}Sync Percent:${NC} ${CYAN}$SYNC_PERCENT${NC}"

        if [[ "$IS_SYNCING" == "false" && "$SYNC_PERCENT" == "100" ]]; then
            QORTAL_SYNCED=true
            QORTAL_RUNNING=true
            echo -e "${GREEN}✅ Qortal is fully synced. No backup needed.${NC}"
        else
            echo -e "${RED}⚠️ Qortal is running but not fully synced.${NC}"
            stop_qortal_core
            backup_qortal_dir
        fi
    else
        echo -e "${YELLOW}Qortal Core is not running or not accessible.${NC}"
        backup_qortal_dir
    fi
fi

# If we backed up or there was no qortal dir, download fresh
if [ "$QORTAL_SYNCED" != "true" ]; then
    echo -e "${CYAN}⬇️ Downloading fresh Qortal Core...${NC}"
    curl -LO https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
    unzip -q qortal.zip
    rm qortal.zip
    chmod +x "$HOME/qortal/"*.sh
    QORTAL_CORE_GOOD=false
else
    QORTAL_CORE_GOOD=true
fi


# Download Architecture-specific Qortal Hub
echo -e "\n ${CYAN}Checking for Desktop Environment..."
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
    echo -e "\n ${YELLOW} Setting up Qortal Icon Theme..."
    curl -LO https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/create-icon-theme-uni.sh
    chmod +x create-icon-theme-uni.sh
    ./create-icon-theme-uni.sh
    echo -e "\n ${GREEN} DESKTOP ENVIRONMENT FOUND, INSTALLING QORTAL HUB..."

    ARCH=$(uname -m)
    echo -e "\n ${CYAN}🔍 Detected architecture: $ARCH${NC}"
    cd "$HOME/qortal"
    if [ "$ARCH" = "aarch64" ]; then
        echo -e "ARM64 NEEDED. Making required modifications to url..."
        HUB_URL="https://github.com/Qortal/Qortal-Hub/releases/latest/download/Qortal-Hub-arm64.AppImage"
    else
        HUB_URL="https://github.com/Qortal/Qortal-Hub/releases/latest/download/Qortal-Hub.AppImage"
    fi

    echo -e "\n ${CYAN}⬇️ Downloading Qortal Hub...${NC}"
    curl -LO "$HUB_URL"
    if [ -f "${HOME}/qortal/Qortal-Hub" ]; then
        echo -e "\n ${GREEN} Existing Hub config found, re-configuring..."
        rm -rf Qortal-Hub
    fi
    mv Qortal-Hub* Qortal-Hub
    chmod +x Qortal-Hub

    cd ${HOME}

    echo -e "\n ${CYAN}🚀 Testing Qortal Hub launch to check if no-sandbox flag is required...${NC}"

    "$HOME/qortal/Qortal-Hub" &
    HUB_PID=$!
    sleep 5
    if ! ps -p "$HUB_PID" > /dev/null; then
        echo -e "${YELLOW}⚠️ Qortal Hub failed without --no-sandbox. Updating launcher accordingly...${NC}"
        SANDBOX_FLAG=" --no-sandbox"
    else
        echo -e "${GREEN}✅ Qortal Hub launched successfully without --no-sandbox. Killing running test instance...${NC}"
        SANDBOX_FLAG=""
        kill -15 ${HUB_PID}
        killall -15 "Qortal Hub"
        wait $HUB_PID 2>/dev/null || true
    fi

    echo -e "${GREEN}✅ Qortal Core + Hub downloaded and ready!${NC}"

    echo -e "${CYAN}🧩 Creating Qortal menu category...${NC}"
    mkdir -p "$HOME/.local/share/desktop-directories"
    cat > "$HOME/.local/share/desktop-directories/Qortal.directory" <<EOL
[Desktop Entry]
Name=Qortal
Comment=Qortal Applications
Icon=qortal-menu-button-3
Type=Directory
EOL

    echo -e "${CYAN}🖥️  Creating Qortal Hub launcher...${NC}"
    mkdir -p "$HOME/.local/share/applications"
    cat > "$HOME/.local/share/applications/qortal-hub.desktop" <<EOL
[Desktop Entry]
Name=Qortal Hub
Comment=Launch Qortal Hub
Exec=$HOME/qortal/Qortal-Hub$SANDBOX_FLAG
Icon=qortal-hub
Terminal=false
Type=Application
Categories=Qortal;
EOL
    echo -e "${CYAN} Creating Qortal Core Desktop Launcher..."
    curl -LO https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal-core.sh
    chmod +x start-qortal-core.sh
    if [ -f "${HOME}/start-qortal-core.sh" ]; then
        cat > "$HOME/.local/share/applications/qortal-core.desktop" <<EOL
[Desktop Entry]
Name=Qortal Core
Comment=Launch Qortal Core
Exec=$HOME/start-qortal-core.sh
Icon=qortal
Terminal=false
Type=Application
Categories=Qortal;
EOL
    else 
        echo -e "${RED}Qortal Start Script failed to download, not creating Qortal Core launcher, start qortal with '${HOME}/qortal/start.sh' script from terminal ${NC}"
    fi

    # Optional desktop copy
    if [ -d "$HOME/Desktop" ]; then
        cp "$HOME/.local/share/applications/qortal-hub.desktop" "$HOME/Desktop/"
    fi

    # Optional force refresh
    if command -v xdg-desktop-menu >/dev/null 2>&1; then
        xdg-desktop-menu forceupdate
    fi

fi

if [ "$BACKUP_EXECUTED" = true ]; then
    echo -e "\n ${GREEN} BACKUP DETECTED! Restoring backed-up qortal folder content... ${NC}"
    LATEST_BACKUP=$(ls -td "${HOME}"/backups/qortal-* | head -n 1)
    if [ -d "${LATEST_BACKUP}/qortal-backup" ]; then
        echo -e "\n Copying qortal-backup folder to new installation directory..."
        rsync -raPz "${LATEST_BACKUP}/qortal-backup/" "${HOME}/qortal/qortal-backup/"
    fi
    if [ -d "${LATEST_BACKUP}/lists" ]; then
        echo -e "\n Copying follow and block lists to new installation directory..."
        rsync -raPz "${LATEST_BACKUP}/lists/" "${HOME}/qortal/lists/"
    fi
    if [ -d "${LATEST_BACKUP}/data" ]; then
        echo -e "\n ${GREEN}...moving data folder from backup...${NC}"
        mv "${LATEST_BACKUP}/data" "${HOME}/qortal/"
    fi 
    if [ -d "${LATEST_BACKUP}/apikey.txt" ]; then
        echo -e "\n...copying apikey.txt to new installation dir..."
        rsync -raPz "${LATEST_BACKUP}/apikey.txt" "${HOME}/qortal/apikey.txt"
    fi 
    echo -e "\n ${GREEN} ✅ Backup minting accounts, trade states, follow/block lists, and data (if in default location) restored from ${LATEST_BACKUP} ${NC}"
    echo -e "\n ${YELLOW} Checking for 'dataPath' setting in ${LATEST_BACKUP}/settings.json... ${NC}"
    if command -v jq >/dev/null 2>&1; then
        if jq -e 'has("dataPath")' "${LATEST_BACKUP}/settings.json" >/dev/null 2>&1; then
            echo -e "\n ✅ dataPath found in backup settings."
            DATA_PATH=$(jq -r '.dataPath' "${LATEST_BACKUP}/settings.json")
            echo -e "\n 📁 dataPath: $DATA_PATH"
            echo -e "\n 🔁 Putting dataPath into new settings.json..."
            
            # Apply to the new settings safely
            jq --arg path "$DATA_PATH" '.dataPath = $path' \
                "${HOME}/qortal/settings.json" > "${HOME}/qortal/settings.tmp" && \
                mv "${HOME}/qortal/settings.tmp" "${HOME}/qortal/settings.json"
        else
            echo -e "\n ❌ dataPath not found in settings.json (data likely default, already restored). Proceeding..."
            DATA_PATH=""
        fi
    else
        echo -e "${RED}⚠️ jq not installed. Cannot extract dataPath safely.${NC}"
        echo -e "${YELLOW}If you used a custom data path, you'll need to manually restore it into settings.json.${NC}"
        DATA_PATH=""
    fi
    echo -e "\n${YELLOW} Data should have been restored, however, please verify this if it matters to you. QDN data can usually be re-obtained from Qortal, but if you are the only publisher of the data, may not be able to be, just FYI..."
fi

echo -e "\n${GREEN}🎉 Qortal setup complete! You can now start Qortal Core and Qortal Hub.${NC}"
echo -e "\n${YELLOW}🛠️  Would you like to install Qortal Automation scripts by crowetic?${NC}"
echo -e "${CYAN}This will:\n - Ensure Qortal is always running\n - Stay within 1500 blocks of the network\n - Auto-update Core + potentially settings\n - Recover from common issues\n - Configure autostart or cron${NC}"
echo -e "${YELLOW}Install automation now? (y/N) — auto-skip in 20 seconds...${NC}"
INSTALL_AUTOMATION=true  # default fallback

echo -n "➡️  Your choice (y/N): "
if read -t 20 -r INSTALL_AUTOFIX; then
    if [[ "$INSTALL_AUTOFIX" =~ ^[Yy]$ ]]; then
        INSTALL_AUTOMATION=true
    else
        INSTALL_AUTOMATION=false
    fi
else
    echo -e "\n${YELLOW}⏳ Timeout reached. Installing automation by default${NC}"
    INSTALL_AUTOMATION=true
fi

if [[ "$INSTALL_AUTOMATION" = true ]]; then
    echo -e "${CYAN}About to run automation... Press Ctrl+C now to cancel (20s delay)...${NC}"
    sleep 5
    echo -e "\n 15 seconds left to cancel automation..."
    sleep 5 
    echo -e "\n 10 seconds left to cancel automation..."
    sleep 5
    echo -e "\n push cntrl+c within 5 seconds or automation will continue..."
    sleep 1 
    echo -e "---4..."
    sleep 1 
    echo -e "...3..."
    sleep 1 
    echo -e "...2..."
    sleep 1 
    echo -e "...1..."
    sleep 1 
    echo -e "\n automation continuing!"
    echo -e "\n ${CYAN}📥 Downloading auto-fix-qortal.sh...${NC}"
    curl -L -o "$HOME/auto-fix-qortal.sh" https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
    chmod +x "$HOME/auto-fix-qortal.sh"
    echo -e "\n ${GREEN}✅ Automation script downloaded.✅ ${NC}"
    echo -e "\n ${CYAN}🚀 Running auto-fix-qortal.sh...${NC}"
    "$HOME/auto-fix-qortal.sh"
else
    echo -e "${YELLOW}Skipping automation setup. You can install it later by running:${NC}"
    echo -e "\n ${GREEN}curl -L -o ~/auto-fix-qortal.sh https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh && chmod +x ~/auto-fix-qortal.sh && cd && ./auto-fix-qortal.sh${NC}"
fi


#!/bin/bash
set -e
trap 'echo -e "\n${RED}❌ Setup cancelled by user. Exiting...${NC}"; exit 1' INT

# Color Codes
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

render_gradient_string() {
    local input="$1"
    local regex='#([0-9a-fA-F]{6})(.)'
    while [[ $input =~ $regex ]]; do
        color="${BASH_REMATCH[1]}"
        char="${BASH_REMATCH[2]}"
        r=$((16#${color:0:2}))
        g=$((16#${color:2:2}))
        b=$((16#${color:4:2}))
        printf "\e[38;2;%d;%d;%dm%s" "$r" "$g" "$b" "$char"
        input=${input#*"${char}"}
    done
    echo -e "\e[0m"
}

rainbowize_ascii() {
    local text="$1"
    local freq=0.15
    local i=0
    local output=""
    local pi=3.14159265

    while IFS= read -r line; do
        for (( j=0; j<${#line}; j++ )); do
            char="${line:$j:1}"
            if [[ "$char" == " " ]]; then
                output+="$char"
                continue
            fi
            r=$(awk -v i=$i -v f=$freq -v pi=$pi 'BEGIN { printf("%02x", 127 * (sin(f*i + 0) + 1)) }')
            g=$(awk -v i=$i -v f=$freq -v pi=$pi 'BEGIN { printf("%02x", 127 * (sin(f*i + 2*pi/3) + 1)) }')
            b=$(awk -v i=$i -v f=$freq -v pi=$pi 'BEGIN { printf("%02x", 127 * (sin(f*i + 4*pi/3) + 1)) }')
            output+="#${r}${g}${b}${char}"
            ((i++))
        done
        output+=$'\n'
    done <<< "$text"

    echo "$output"
}

ascii_block='
Qortal Universal Linux Install Script
By: crowetic
'

rainbowized=$(rainbowize_ascii "$ascii_block")
render_gradient_string "$rainbowized"

BACKUP_EXECUTED=false
QORTAL_CORE_GOOD=false


# Detect Distro
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
else
    echo -e "${RED}❌ Cannot detect Linux distribution. Please install dependencies manually.${NC}"
    exit 1
fi

echo -e "${YELLOW}📋 Detected distro: ${DISTRO} ${VERSION}${NC}"

# Install Required Packages
echo -e "${CYAN}🔧 Installing dependencies...${NC}"
case "$DISTRO" in
    ubuntu|debian)
        sudo apt update
        sudo apt install -y openjdk-17-jre curl unzip libfuse2 jq zlib1g-dev imagemagick
        ;;
    fedora)
        sudo dnf install -y java-17-openjdk curl unzip fuse jq zlib-devel ImageMagick
        ;;
    arch)
        sudo pacman -Sy --noconfirm jre17-openjdk curl unzip fuse2 jq zlib imagemagick
        ;;
    alpine)
        sudo apk add --no-cache openjdk17 curl unzip fuse jq zlib-dev imagemagick
        ;;
    *)
        echo -e "${RED}⚠️ Unsupported distro: ${DISTRO}. Please install openjdk-17, curl, unzip, jq, zlib1g-dev and fuse manually.${NC}"
        ;;
esac

# Download and Install Qortal Core
echo -e "${CYAN}⬇️ Downloading Qortal Core...${NC}"
cd "$HOME"
if [ -d "$HOME/qortal" ]; then
    if pgrep -f "qortal.jar" > /dev/null && curl -s "http://localhost:12391/admin/status" | grep -q "height"; then
        STATUS_JSON=$(curl -s http://localhost:12391/admin/status)

        IS_SYNCING=$(echo "$STATUS_JSON" | jq -r '.isSynchronizing')
        SYNC_PERCENT=$(echo "$STATUS_JSON" | jq -r '.syncPercent')

        echo "🛰️  Syncing: $IS_SYNCING"
        echo "📊 Sync Percent: $SYNC_PERCENT"
    fi

    if [[ "$IS_SYNCING" == "false" || "$SYNC_PERCENT" == "100" ]]; then
        echo "✅ Qortal Core is fully synchronized. No Backup needed..."
        BACKUP_EXECUTED=false
        QORTAL_CORE_GOOD=true
    else
        echo "⚠️ Qortal Core is not fully synced. Proceeding with update/start/etc."
    
        if pgrep -f "qortal.jar" > /dev/null && curl -s "http://localhost:12391/admin/status" | grep -q "height"; then
            if [ -f "${HOME}/qortal/stop.sh" ]; then
                "${HOME}/qortal/stop.sh"
            else
                curl -X POST "http://localhost:12391/admin/stop" -H  "X-API-KEY: $(cat ${HOME}/qortal/apikey.txt)"
            fi
        fi
        mkdir -p "$HOME/backups"
        echo -e "${YELLOW}⚠️ Existing 'qortal' folder found. Backing it up...${NC}"
        mv "$HOME/qortal" "$HOME/backups/qortal-$(date +%s)"
        BACKUP_EXECUTED=true
        curl -LO https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
        unzip qortal.zip
        rm qortal.zip
        chmod +x "$HOME/qortal/"*.sh
    fi
fi

if [ "$QORTAL_CORE_GOOD" == "false" ]; then
    if [ -d "${HOME}/qortal" ]; then
        echo "${YELLOW} INITIAL BACKUP DIDN'T DETECT FAILED QORTAL, SECONDARY BACKUP CHECK DID, BACKING UP QORTAL FOR LATER RESTORE...AND FORCE-KILLING JAVA...${NC}"
        killall -9 java
        mkdir -p "$HOME/backups"
        echo -e "${YELLOW}⚠️ Existing 'qortal' folder found. Backing it up...${NC}"
        mv "$HOME/qortal" "$HOME/backups/qortal-$(date +%s)"
        BACKUP_EXECUTED=true
    fi

    curl -LO https://github.com/Qortal/qortal/releases/latest/download/qortal.zip
    unzip qortal.zip
    rm qortal.zip
    chmod +x "$HOME/qortal/"*.sh
fi

# Download Architecture-specific Qortal Hub
echo -e "\n ${CYAN}Checking for Desktop Environment..."
if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
    echo -e "\n ${YELLOW} Setting up Qortal Icon Theme..."
    curl -LO https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/create-icon-theme.sh
    chmod +x create-icon-theme.sh
    ./create-icon-theme.sh
    echo -e "\n ${GREEN} DESKTOP ENVIRONMENT FOUND, INSTALLING QORTAL HUB..."

    ARCH=$(uname -m)
    echo -e "\n ${CYAN}🔍 Detected architecture: $ARCH${NC}"
    cd "$HOME/qortal"
    if [ "$ARCH" = "aarch64" ]; then
        echo -e "ARM64 NEEDED. Making required modifications to url..."
        HUB_URL="https://github.com/Qortal/Qortal-Hub/releases/latest/download/Qortal-Hub-arm64/AppImage"
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
    fi

    echo -e "${GREEN}✅ Qortal Core + Hub downloaded and ready!${NC}"

    # Optional: Install Desktop Launchers if desktop detected
    if command -v xdg-desktop-menu >/dev/null 2>&1; then
        echo -e "${CYAN}🖥️  Setting up desktop launchers...${NC}"
        mkdir -p "$HOME/.local/share/applications"

        cat > "$HOME/.local/share/applications/qortal-hub.desktop" <<EOL
[Desktop Entry]
Name=Qortal Hub
Comment=Launch Qortal Hub
Exec=$HOME/qortal/Qortal-Hub$SANDBOX_FLAG
Icon=qortal-hub
Terminal=false
Type=Application
Categories=Utility;
EOL

        echo -e "\n ${GREEN}✅ Desktop launcher created at ~/.local/share/applications/qortal-hub.desktop${NC}"
        if [ -d "${HOME}/Desktop" ]
            cp "$HOME/.local/share/applications/qortal-hub.desktop" "${HOME}/Desktop/"
        fi
    else
        echo -e "\n ${YELLOW}ℹ️ No desktop environment detected or missing xdg tools. Skipping applications menu launcher setup.${NC}"        
        echo -e "\n ${CYAN} Checking for Desktop folder..."
        if [ -d "${HOME}/Desktop" ]; then
            echo -e "Desktop folder found, creating desktop launcher..."
            cat > "${HOME}/Desktop/qortal-hub.desktop" <<EOL
[Desktop Entry]
Name=Qortal Hub
Comment=Launch Qortal Hub
Exec=$HOME/qortal/Qortal-Hub$SANDBOX_FLAG
Icon=qortal-hub
Terminal=false
Type=Application
Categories=Utility;
EOL
        else 
            echo -e "${RED} Display found, but no Desktop folder found? Skipping Launcher creation..."
        fi
    fi

fi

if [ "$BACKUP_EXECUTED" = true ]; then
    echo -e "\n ${GREEN} BACKUP DETECTED! Restoring backed-up qortal folder content... ${NC}"
    LATEST_BACKUP=$(ls -td "${HOME}"/backups/qortal-* | head -n 1)
    if [ -d "${LATEST_BACKUP}/qortal-backup" ]; then
        echo -e "\n Copying qortal-backup folder to new installation directory..."
        rsync -raPz "${LATEST_BACKUP}/qortal-backup" "${HOME}/qortal/qortal-backup"
    fi
    if [ -d "${LATEST_BACKUP}/lists" ]; then
        echo -e "\n Copying follow and block lists to new installation directory..."
        rsync -raPz "${LATEST_BACKUP}/lists" "${HOME}/qortal/lists"
    fi
    if [ -d "${LATEST_BACKUP}/data" ]; then
        echo -e "\n...moving data folder from backup..."
        mv "${LATEST_BACKUP}/data" "${HOME}/qortal/data"
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


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
NC='\033[0m' # No Color

RASPI_32_DETECTED=false
RASPI_64_DETECTED=false
UPDATED_SETTINGS=false
NEW_UBUNTU_VERSION=false

# Function to update the script initially if needed
initial_update() {
    if [ ! -f "${HOME}/auto_fix_updated" ]; then
        echo "${YELLOW}Checking for the latest version of the script...${NC}\n"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
        chmod +x "${HOME}/auto-fix-qortal.sh"
        echo "${GREEN}Script updated. Restarting...${NC}\n"
        touch "${HOME}/auto_fix_updated"
        ./auto-fix-qortal.sh
    else
        check_internet
    fi
}

check_internet() {
    echo "${CYAN}....................................................................${NC}"
    echo "${CYAN}THIS SCRIPT IS MEANT TO RUN AUTOMATICALLY, PLEASE ALLOW IT TO COMPLETELY FINISH AND DO NOT CLOSE IT EARLY!${NC}"
    echo "${CYAN}CLOSING IT EARLY WILL PREVENT IT FROM DOING ITS JOB, AND ENSURING QORTAL IS UPDATED, AND SYNCHRONIZED.${NC}"
    echo "${CYAN}PLEASE BE PATIENT AND ALLOW SCRIPT TO RUN. THANK YOU! -crowetic${NC}"
    echo "${CYAN}....................................................................${NC}"
    sleep 5
    echo "${YELLOW}Checking internet connection...${NC}"
    INTERNET_STATUS="UNKNOWN"
    TIMESTAMP=$(date +%s)

    # Function to test curl access
    test_connectivity() {
        local URL=$1
        curl -s --head --max-time 5 "$URL" | grep -q "200 OK"
    }

    # Try ping first (requires CAP_NET_RAW or setuid on ping)
    if ping -c 1 -W 0.7 8.8.4.4 > /dev/null 2>&1; then
        INTERNET_STATUS="UP"
        echo "${GREEN}Ping successful to 8.8.4.4${NC}"
    else
        echo "${YELLOW}Ping failed, falling back to Qortal domain tests...${NC}"

        if test_connectivity "https://qortal.org"; then
            INTERNET_STATUS="UP"
            echo "${GREEN}Internet access confirmed via qortal.org${NC}"
        elif test_connectivity "https://api.qortal.org"; then
            INTERNET_STATUS="UP"
            echo "${GREEN}Internet access confirmed via api.qortal.org${NC}"
        elif test_connectivity "https://ext-node.qortal.link"; then
            INTERNET_STATUS="UP"
            echo "${GREEN}Internet access confirmed via ext-node.qortal.link${NC}"
        else
            INTERNET_STATUS="DOWN"
        fi
    fi

    if [ "$INTERNET_STATUS" = "UP" ]; then
        echo "${BLUE}Internet connection is UP, continuing...${NC}\n   $(date +%Y-%m-%dT%H:%M:%S%Z) $(( $(date +%s) - $TIMESTAMP ))"
        rm -rf "${HOME}/Desktop/check-qortal-status.sh"
        cd || exit 1
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh && mv check-qortal-status.sh "${HOME}/qortal" && chmod +x "${HOME}/qortal/check-qortal-status.sh"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh && chmod +x start-qortal.sh
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh && chmod +x refresh-qortal.sh
        check_for_raspi
    else
        echo "${RED}Internet Connection is DOWN, please fix connection and restart device.${NC}\n$(date +%Y-%m-%dT%H:%M:%S%Z) $(( $(date +%s) - $TIMESTAMP ))"
        sleep 30
        exit 1
    fi
}


check_for_raspi() {
    if command -v raspi-config >/dev/null 2>&1; then
        echo "${YELLOW}Raspberry Pi machine detected, checking for 32bit or 64bit...${NC}\n"
        
        if [ "$(uname -m | grep 'armv7l')" != "" ]; then
            echo "${WHITE}32bit ARM detected, using ARM 32bit compatible modified start script${NC}\n"
            RASPI_32_DETECTED=true
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-modified-memory-args.sh
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron
            crontab auto-fix-cron
            chmod +x start-modified-memory-args.sh
            mv start-modified-memory-args.sh "${HOME}/qortal/start.sh"
            check_qortal
        else
            echo "${WHITE}64bit ARM detected, proceeding accordingly...${NC}\n"
            RASPI_64_DETECTED=true
            check_memory
        fi
    else
        echo "${YELLOW}Not a Raspberry Pi machine, checking for Ubuntu 24+...${NC}\n"
        if command -v lsb_release >/dev/null 2>&1; then
            UBUNTU_VER=$(lsb_release -rs | cut -d. -f1)
        else
            UBUNTU_VER=$(grep -oP '^VERSION_ID="\K[0-9]+' /etc/os-release)
        fi
        if [ "$UBUNTU_VER" -ge 24 ]; then
            echo "${GREEN} NEWER Ubuntu Version Found, using crontab-based Qortal start ${NC}\n"
            NEW_UBUNTU_VERSION=true
        fi
        check_memory
    fi
}

check_memory() {
    totalm=$(free -m | awk '/^Mem:/{print $2}')
    echo "${YELLOW}Checking system RAM ... $totalm MB System RAM ... Configuring system for optimal RAM settings...${NC}\n"

    if [ "$totalm" -le 6000 ]; then
        echo "${WHITE}Machine has less than 6GB of RAM, downloading correct start script...${NC}\n"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/4GB-start.sh && mv 4GB-start.sh "${HOME}/qortal/start.sh" && chmod +x "${HOME}/qortal/start.sh"
    elif [ "$totalm" -ge 6001 ] && [ "$totalm" -le 16000 ]; then
        echo "${WHITE}Machine has between 6GB and 16GB of RAM, downloading correct start script...${NC}\n"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-6001-to-16000m.sh && mv start-6001-to-16000m.sh "${HOME}/qortal/start.sh" && chmod +x "${HOME}/qortal/start.sh"
    else
        echo "${WHITE}Machine has more than 16GB of RAM, using high-RAM start script...${NC}\n"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-high-RAM.sh && mv start-high-RAM.sh "${HOME}/qortal/start.sh" && chmod +x "${HOME}/qortal/start.sh"
    fi

    check_qortal
}

check_qortal() {
    echo "${YELLOW}Checking qortal version (local vs remote)...${NC}\n"

    core_running=$(curl -s localhost:12391/admin/status)
    if [ -z "$core_running" ]; then 
    
        echo "${CYAN} NODE DOES NOT SEEM TO BE RUNNING? CHECKING IF NODE IS BOOTSTRAPPING...${NC}\n"
        
        if tail -n 20 "${HOME}/qortal/qortal.log" | grep -Ei 'bootstrap|bootstrapping' > /dev/null; then
            echo "${RED}Node seems to be bootstrapping, updating script and exiting...${NC}\n"
            update_script
        fi
        
        echo "${RED}CORE DOES NOT SEEM TO BE RUNNING NOR BOOTSTRAPPING..., WAITING 2 MORE MINUTES IN CASE NODE IS SLOW AND STILL STARTING...${NC}\n"
        sleep 120
    fi

    LOCAL_VERSION=$(curl -s localhost:12391/admin/info | grep -oP '"buildVersion":"qortal-\K[^-]*' | sed 's/-.*//' | tr -d '.')
    REMOTE_VERSION=$(curl -s "https://api.github.com/repos/qortal/qortal/releases/latest" | grep -oP '"tag_name": "v\K[^"]*' | tr -d '.')

    if [ -n "$LOCAL_VERSION" ] && [ -n "$REMOTE_VERSION" ]; then
        if [ "$LOCAL_VERSION" -ge "$REMOTE_VERSION" ]; then
            echo "${GREEN}Local version is >= remote version, no qortal updates needed... continuing...${NC}\n"
            check_for_GUI  
        else
            check_hash_update_qortal
        fi
    else
        # If version checks fail, fallback to hash checking
        check_hash_update_qortal
    fi
}

check_hash_update_qortal() {
    echo "${RED}API-based version check failed and/or jar is outdated. Proceeding to HASH CHECK...${NC}\n"
    cd "${HOME}/qortal" || exit 1
    md5sum qortal.jar > "local.md5"
    cd || exit 1
    echo "${CYAN}Grabbing newest core release jar to check hash...${NC}\n"
    curl -L -O https://github.com/qortal/qortal/releases/latest/download/qortal.jar
    md5sum qortal.jar > "remote.md5"

    LOCAL=$(cat "${HOME}/qortal/local.md5")
    REMOTE=$(cat "${HOME}/remote.md5")

    if [ "$LOCAL" = "$REMOTE" ]; then
        echo "${CYAN}Hash check: Qortal core is up-to-date, checking environment...${NC}\n"
        check_for_GUI
        exit 1
    else
        echo "${RED}Hash check confirmed outdated qortal core.${NC}${YELLOW} Updating and bootstrapping...${NC}\n"
        cd "${HOME}/qortal" || exit 1
        killall -9 java
        sleep 3
        rm -rf db log.t* qortal.log run.log run.pid qortal.jar
        cp "${HOME}/qortal.jar" "${HOME}/qortal"
        rm "${HOME}/qortal.jar"
        rm "${HOME}/remote.md5" local.md5
        potentially_update_settings
        ./start.sh
        cd || exit 1
        check_for_GUI
    fi
}

check_for_GUI() {
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] || [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo "${CYAN}Machine has GUI, setting up auto-fix-visible for GUI-based machines...${NC}\n"
        if [ "${RASPI_32_DETECTED}" = true ] || [ "${RASPI_64_DETECTED}" = true ]; then
            echo "${YELLOW}Pi machine with GUI, skipping autostart GUI setup, setting cron jobs instead...${NC}\n"
            setup_raspi_cron
        else
            echo "${YELLOW}Setting up auto-fix-visible on GUI-based system...${NC}\n"
            sleep 2
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-GUI-cron
            crontab auto-fix-GUI-cron
            rm -rf auto-fix-GUI-cron
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal-GUI.desktop
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.desktop
            mkdir -p "${HOME}/.config/autostart"
            cp auto-fix-qortal-GUI.desktop "${HOME}/.config/autostart"
            cp start-qortal.desktop "${HOME}/.config/autostart"
            rm -rf "${HOME}/auto-fix-qortal-GUI.desktop" "${HOME}/start-qortal.desktop"
            echo "${YELLOW}Auto-fix-qortal.sh will run in a pop-up terminal 7 min after startup.${NC}\n"
            echo "${CYAN}Continuing to verify node height...${NC}\n"
            check_height
        fi
    else
        echo "${YELLOW}Non-GUI system detected, configuring cron then checking node height...${NC}\n"
        setup_raspi_cron
    fi
}

setup_raspi_cron() {
    echo "${YELLOW}Setting up cron jobs for Raspberry Pi or headless machines...${NC}\n"

    mkdir -p "${HOME}/backups/cron-backups"
    crontab -l > "${HOME}/backups/cron-backups/crontab-backup-$(date +%Y%m%d%H%M%S)"

	echo "${YELLOW}Checking if autostart desktop shortcut exists to avoid double-launch...${NC}\n"

	if find "${HOME}/.config/autostart" -maxdepth 1 -name "start-qortal*.desktop" | grep -q .; then
        echo "${RED}Autostart desktop entry found! Adding automatic run every 3 days for auto-fix script in cron...${NC}\n"
        # rm -rf "${HOME}/.config/autostart/start-qortal*.desktop" "${HOME}/.config/autostart/auto-fix-qortal*.desktop"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-GUI-cron
        crontab auto-fix-GUI-cron
        rm -f auto-fix-GUI-cron
        # curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/auto-fix-cron 
        # crontab auto-fix-cron
        # rm -f auto-fix-cron
        check_height
	fi

    echo "${BLUE}No autostart entries found. Setting up full headless cron...${NC}\n"
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/auto-fix-cron 
    crontab auto-fix-cron
    rm -f auto-fix-cron
    check_height
}


check_height() {
    local_height=$(curl -sS "http://localhost:12391/blocks/height")

    if [ -f auto_fix_last_height.txt ]; then
        previous_local_height=$(cat auto_fix_last_height.txt)
        if [ -n "$previous_local_height" ]; then
            if [ "$local_height" = "$previous_local_height" ]; then
                echo "${RED}Local height unchanged since last run, waiting 3 minutes to re-check...${NC}\n"
                sleep 188
                checked_height=$(curl -s "http://localhost:12391/blocks/height")
                sleep 2
                if [ "$checked_height" = "$previous_local_height" ]; then
                    echo "${RED}Block height still unchanged... final sanity check in 10 seconds..${NC}\n"
                    sleep 10
                    new_check_again=$(curl -sS "http://localhost:12391/blocks/height")
                    echo "new height = $new_check_again | previously checked height = $previous_local_height"
                    if [ "$new_check_again" = "$previous_local_height" ]; then
                        echo "${RED}Block height still unchanged... forcing bootstrap...${NC}\n"
                        force_bootstrap
                    fi
                fi
            fi
        fi
    fi

    if [ -z "$local_height" ]; then
        echo "${RED}Local API call for block height returned empty. Is Qortal running?${NC}\n"
        no_local_height
    else
        echo "$local_height" > auto_fix_last_height.txt
        remote_height_checks
    fi
}

no_local_height() {
    echo "${WHITE}Checking if node is bootstrapping or not...${NC}\n"

    if [ -f "${HOME}/qortal/qortal.log" ]; then
        if tail -n 30 "${HOME}/qortal/qortal.log" | grep -Ei 'bootstrap|bootstrapping' > /dev/null; then
            echo "${RED}Node seems to be bootstrapping, updating script and exiting...${NC}\n"
            update_script
        fi
    else
        # Check for old log files
        old_log_found=false
        for log_file in "${HOME}/qortal/log.t"*; do
            if [ -f "$log_file" ]; then
                old_log_found=true
                echo "${YELLOW}Old log method found, backing up old logs and updating logging method...${NC}\n"
                mkdir -p "${HOME}/qortal/backup/logs"
                mv "${HOME}/qortal/log.t"* "${HOME}/qortal/backup/logs"
                mv "${HOME}/qortal/log4j2.properties" "${HOME}/qortal/backup/logs"
                curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/log4j2.properties
                mv log4j2.properties "${HOME}/qortal"
                echo -e "${RED}Stopping Qortal to apply new logging method...${NC}\n"
                cd "${HOME}/qortal" || exit 1
                ./stop.sh 
                cd || exit 1
                break
            fi
        done

        if ! $old_log_found; then
            echo "No old log files found."
        fi
    fi

    echo "${GREEN}Starting Qortal Core and sleeping 20 min to let it start fully, PLEASE WAIT...${NC}\n"
    potentially_update_settings
    cd "${HOME}/qortal" || exit 1
    ./start.sh
    sleep 1220
    cd || exit 1
    echo "${GREEN}Checking if Qortal started correctly...${NC}\n"
    local_height_check=$(curl -sS "http://localhost:12391/blocks/height")

    if [ -n "$local_height_check" ]; then
        echo "${GREEN}Local height is ${CYAN}${local_height_check}${NC}"
        echo "${GREEN}Node is good, re-checking height and continuing...${NC}\n"
        check_height
    else 
        echo "${RED}Starting Qortal Core FAILED. Please consider restarting the computer and waiting 30 minutes.${NC}\n"
        update_script
    fi
}

remote_height_checks() {
    height_api_qortal_org=$(curl -sS --connect-timeout 10 "https://api.qortal.org/blocks/height")
    height_qortal_link=$(curl -sS --connect-timeout 10 "https://qortal.link/blocks/height")
    local_height=$(curl -sS --connect-timeout 10 "http://localhost:12391/blocks/height")

    if [ -z "$height_api_qortal_org" ] || [ -z "$height_qortal_link" ]; then
        echo "${RED}Failed to fetch data from remote nodes. Skipping remote checks and updating script.${NC}\n"
        update_script
        return
    fi

    if [ "$height_api_qortal_org" -ge $((local_height - 1500)) ] && [ "$height_api_qortal_org" -le $((local_height + 1500)) ]; then
        echo "${YELLOW}Local height (${CYAN}${local_height}${YELLOW}) is within 1500 blocks of api.qortal.org (${GREEN}${height_api_qortal_org}${YELLOW}).${NC}"
        echo "${GREEN}api.qortal.org height checks PASSED, updating script...${NC}"
        update_script
    else
        echo "${RED}Local node is outside 1500 block range of api.qortal.org, checking qortal.link...${NC}"
        if [ "$height_qortal_link" -ge $((local_height - 1500)) ] && [ "$height_qortal_link" -le $((local_height + 1500)) ]; then
            echo "${YELLOW}Local height (${CYAN}${local_height}${YELLOW}) is within 1500 blocks of qortal.link (${GREEN}${height_qortal_link}${YELLOW}).${NC}"
            echo "${GREEN}qortal.link height checks PASSED, updating script...${NC}"
            update_script
        else
            echo "${RED}Second remote check FAILED... assuming need for bootstrap...${NC}\n"
            force_bootstrap
        fi
    fi
}

force_bootstrap() {
    echo "${RED}ISSUES DETECTED...Forcing bootstrap...${NC}\n"
    cd "${HOME}/qortal" || exit 1
    killall -9 java
    sleep 3
    rm -rf db log.t* qortal.log run.log run.pid *.gz
    sleep 5
    ./start.sh
    cd || exit 1
    update_script
}
    

potentially_update_settings() {
    echo "${GREEN}Validating settings.json...${NC}"
    cd "${HOME}/qortal" || exit 1

    SETTINGS_FILE="settings.json"
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_FOLDER="${HOME}/qortal/qortal-backup/auto-fix-settings-backup"
    BACKUP_FILE="backup-settings-${TIMESTAMP}.json"

    mkdir -p "${BACKUP_FOLDER}"

    # Step 1: Backup settings.json
    cp "${SETTINGS_FILE}" "${BACKUP_FOLDER}/${BACKUP_FILE}"

    # Step 2: Validate with jq
    is_valid_json=false
    if command -v jq &>/dev/null; then
        echo "${YELLOW}Using jq to validate JSON...${NC}"
        if [ -s "${SETTINGS_FILE}" ]; then
            if jq empty "${SETTINGS_FILE}" 2>/dev/null; then
                is_valid_json=true
                echo "${GREEN}settings.json is valid JSON.${NC}"
            fi
        fi
    else
        echo "${RED}jq not found. Skipping JSON validation.${NC}"
    fi

    # Step 3: If invalid, try to fix
    if [ "${is_valid_json}" != true ]; then
        echo "${RED}settings.json is invalid or validation skipped. Attempting fix...${NC}"

        echo "${YELLOW}Trying to restore from backup: ${BACKUP_FILE}${NC}"
        cp "${BACKUP_FOLDER}/${BACKUP_FILE}" "${SETTINGS_FILE}"

        if command -v jq &>/dev/null && jq empty "${SETTINGS_FILE}" 2>/dev/null; then
            echo "${GREEN}Backup restored successfully and is valid.${NC}"
        else
            echo "${RED}Backup also invalid. Downloading default settings.json...${NC}"
            curl -L -o "${SETTINGS_FILE}" "https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/settings.json"

            if command -v jq &>/dev/null && jq empty "${SETTINGS_FILE}" 2>/dev/null; then
                echo "${GREEN}Default settings.json downloaded and is valid.${NC}"
            else
                echo "${RED}Failed to recover a valid settings.json. Manual intervention required.${NC}"
                return 1
            fi
        fi
    fi

    # Step 4: Rotate backups (keep 2 newest)
    echo "${YELLOW}Rotating old backups (keeping only 2)...${NC}"
    cd "${BACKUP_FOLDER}" || exit 1
    backup_count=$(ls -1 backup-settings-*.json 2>/dev/null | wc -l)
    to_delete=$((backup_count - 2))
    if [ "$to_delete" -gt 0 ]; then
        for old_backup in $(ls -1tr backup-settings-*.json | head -n "$to_delete"); do
            echo "Deleting old backup: $old_backup"
            rm -f "$old_backup"
        done
    else
        echo "${BLUE}No old backups to delete.${NC}"
    fi

    echo "${GREEN}Settings file is now valid. Proceeding...${NC}"
    return 0
}


update_script() {
    echo "${YELLOW}Updating script to newest version and backing up old one...${NC}\n"
    mkdir -p "${HOME}/qortal/new-scripts/backups"
    cp "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" "${HOME}/qortal/new-scripts/backups" 2>/dev/null
    rm -rf "${HOME}/qortal/new-scripts/auto-fix-qortal.sh"
    cp "${HOME}/auto-fix-qortal.sh" "${HOME}/qortal/new-scripts/backups/original.sh"
    cd "${HOME}/qortal/new-scripts" || exit 1
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
    chmod +x auto-fix-qortal.sh
    cd || exit 1
    cp "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" "${HOME}/auto-fix-qortal.sh"
    chmod +x auto-fix-qortal.sh
    rm -rf "${HOME}/auto_fix_updated"
    echo "${YELLOW}Checking for any settings changes required...${NC}"
    sleep 2
    potentially_update_settings
    rm -rf "${HOME}/qortal.jar" "${HOME}/run.pid" "${HOME}/run.log" "${HOME}/remote.md5" "${HOME}/qortal/local.md5"
    rm -rf ${HOME}/backups/backup-settings*
    echo "${YELLOW}Auto-fix script run complete.${NC}\n"
    sleep 5
    exit
}

initial_update

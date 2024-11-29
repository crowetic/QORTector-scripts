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

PI_32_DETECTED=false
PI_64_DETECTED=false
UPDATED_SETTINGS=false

# Function to update the script
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
    echo "${YELLOW} Checking internet connection ${NC}\n"

    INTERNET_STATUS="UNKNOWN"
    TIMESTAMP=$(date +%s)

    ping -c 1 -W 0.7 8.8.4.4 > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        if [ "$INTERNET_STATUS" != "UP" ]; then
            echo "${BLUE}Internet connection is UP, continuing${NC}\n   $(date +%Y-%m-%dT%H:%M:%S%Z) $(( $(date +%s) - $TIMESTAMP ))"
            INTERNET_STATUS="UP"
            rm -rf "${HOME}/Desktop/check-qortal-status.sh"
            cd
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/check-qortal-status.sh && mv check-qortal-status.sh "${HOME}/qortal" && chmod +x "${HOME}/qortal/check-qortal-status.sh"
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal.sh && chmod +x start-qortal.sh
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/refresh-qortal.sh && chmod +x refresh-qortal.sh
            check_for_pi
        fi
    else
        if [ "$INTERNET_STATUS" = "UP" ]; then
            echo "${RED}Internet Connection is DOWN, please fix connection and restart device, script will re-run automatically after 7 min.${NC}\n $(date +%Y-%m-%dT%H:%M:%S%Z) $(( $(date +%s) - $TIMESTAMP ))"
            INTERNET_STATUS="DOWN"
            sleep 30
            exit 1
        fi
    fi
}

check_for_pi() {
    if command -v raspi-config >/dev/null 2>&1; then
        echo "${YELLOW} Raspberry Pi machine detected, checking for 32bit or 64bit pi...${NC}\n"
        
        if [ "$(uname -m | grep 'armv7l')" != "" ]; then
            echo "${WHITE} 32bit ARM detected, using ARM 32bit compatible modified start script${NC}\n"
            PI_32_DETECTED=true
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-modified-memory-args.sh
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-cron
            crontab auto-fix-cron
            chmod +x start-modified-memory-args.sh
            mv start-modified-memory-args.sh "${HOME}/qortal/start.sh"
            check_qortal
        else
            echo "${WHITE} 64bit ARM detected, proceeding accordingly...${NC}\n"
            PI_64_DETECTED=true
            check_memory
            
        fi
        
    else
        echo "${YELLOW} Not a Raspberry pi machine, continuing...${NC}\n"
        check_memory
    fi
}

check_memory() {
    totalm=$(free -m | awk '/^Mem:/{print $2}')
    echo "${YELLOW} Checking system RAM ... $totalm System RAM ... Configuring system for optimal RAM settings...${NC}\n"

    if [ "$totalm" -le 6000 ]; then
        echo "${WHITE} Machine has less than 6GB of RAM, Downloading correct start script for your configuration...${NC}\n"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/4GB-start.sh && mv 4GB-start.sh "${HOME}/qortal/start.sh" && chmod +x "${HOME}/qortal/start.sh"
    elif [ "$totalm" -ge 6001 ] && [ "$totalm" -le 16000 ]; then
        echo "${WHITE} Machine has between 6GB and 16GB of RAM, Downloading correct start script for your configuration...${NC}\n"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-6001-to-16000m.sh && mv start-6001-to-16000m.sh "${HOME}/qortal/start.sh" && chmod +x "${HOME}/qortal/start.sh"
    else
        echo "${WHITE} Machine has more than 16GB of RAM, using high-RAM start script and continuing...${NC}\n"
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-high-RAM.sh && mv start-high-RAM.sh "${HOME}/qortal/start.sh" && chmod +x "${HOME}/qortal/start.sh"
    fi

    check_qortal
}

check_qortal() {
    echo "${YELLOW} Checking the version of qortal on local machine VS the version on github... ${NC}\n"

    core_running=$(curl -s localhost:12391/admin/status)
    if [ -z ${core_running} ]; then 
        echo "${RED} CORE DOES NOT SEEM TO BE RUNNING, WAITING 1 MINUTE IN CASE IT IS STILL STARTING UP... ${NC}\n"
        sleep 60
    fi

    LOCAL_VERSION=$(curl -s localhost:12391/admin/info | grep -oP '"buildVersion":"qortal-\K[^-]*' | sed 's/-.*//' | tr -d '.')
    REMOTE_VERSION=$(curl -s "https://api.github.com/repos/qortal/qortal/releases/latest" | grep -oP '"tag_name": "v\K[^"]*' | tr -d '.')

    if [ "$LOCAL_VERSION" -ge "$REMOTE_VERSION" ]; then
        echo "${GREEN} Local version is higher than or equal to the remote version, no qortal updates needed... continuing...${NC}\n"
        check_for_GUI  
    else
        check_hash_update_qortal
    fi
}

check_peer_count() {
    echo "${YELLOW} Checking peer count... ${NC}\n"

    # Check if jq is installed
    if command -v jq >/dev/null 2>&1; then
        # Use jq to parse the number of connections from admin/status call
        peer_count=$(curl -s localhost:12391/admin/status | jq '.numberOfConnections')
    else
        # Use curl and line count if jq is not installed
        peer_data=$(curl -s localhost:12391/peers)
        line_count=$(echo "$peer_data" | wc -l)
        
        if [ "$line_count" -gt 20 ]; then
            peer_count=20  # Set to a reasonable value indicating peers are present
        else
            peer_count=0
        fi
    fi

    if [ "$peer_count" -lt 3 ]; then
        echo "${YELLOW} Peer count is low, waiting 10 seconds and trying again...${NC}\n"
        sleep 10

        # Repeat the check after waiting
        if command -v jq >/dev/null 2>&1; then
            peer_count=$(curl -s localhost:12391/admin/status | jq '.numberOfConnections')
        else
            peer_data=$(curl -s localhost:12391/peers)
            line_count=$(echo "$peer_data" | wc -l)

            if [ "$line_count" -gt 20 ]; then
                peer_count=20
            else
                peer_count=0
            fi
        fi

        if [ "$peer_count" -lt 3 ]; then
            echo "${RED} Peer count continues to be low (${peer_count}), checking for 0 peers...${NC}${YELLOW}\n"
            sleep 5

            # Final check
            if command -v jq >/dev/null 2>&1; then
                peer_count=$(curl -s localhost:12391/admin/status | jq '.numberOfConnections')
            else
                peer_data=$(curl -s localhost:12391/peers)
                line_count=$(echo "$peer_data" | wc -l)

                if [ "$line_count" -gt 20 ]; then
                    peer_count=20
                else
                    peer_count=0
                fi
            fi

            if [ "$peer_count" -eq 0 ]; then
                echo "${RED} Peer count is 0, executing settings modifications, blocking Chinese peers, and applying iptables-based rate limits...${NC}\n"
                zero_peer_settings_mod
            fi
        fi
    fi
    
    check_for_GUI 
}


zero_peer_settings_mod() {
    echo "${YELLOW} this should not be seen... skipping${NC}\n"
    check_for_GUI
    # Define backup file name
    BACKUP_FILE="${HOME}/backups/qortal-settings/settings-$(date +%Y%m%d%H%M%S).json"

    # Create backup folder if not exists and backup settings.json
    mkdir -p "${HOME}/backups/qortal-settings"
    cp "${HOME}/qortal/settings.json" "$BACKUP_FILE"

    # If jq is installed, use jq to modify settings.json
    if command -v jq >/dev/null 2>&1; then
        echo "${YELLOW} Using jq to modify settings.json...${NC}\n"
        
        # Modify or add necessary settings
        jq '.allowConnectionsWithOlderPeerVersions = false | .minPeerVersion = "4.6.0"' "${HOME}/qortal/settings.json" > tmp.$$.json && mv tmp.$$.json "${HOME}/qortal/settings.json"

        # Validate the modified JSON
        if ! jq empty "${HOME}/qortal/settings.json" >/dev/null 2>&1; then
            echo "${RED} Error: settings.json is invalid after modifications. Restoring backup... ${NC}\n"
            cp "$BACKUP_FILE" "${HOME}/qortal/settings.json"
            return 1
        fi
    else
        # If jq is not available, fallback to using sed and other text processing
        echo "${YELLOW} jq is not installed, using sed for settings modifications...${NC}\n"

        # Ensure settings.json modifications with sed
        if ! grep -q '"allowConnectionsWithOlderPeerVersions"' "${HOME}/qortal/settings.json"; then
            sed -i '/^{/a \  "allowConnectionsWithOlderPeerVersions": false,' "${HOME}/qortal/settings.json"
        else
            sed -i 's/"allowConnectionsWithOlderPeerVersions":.*/"allowConnectionsWithOlderPeerVersions": false,/' "${HOME}/qortal/settings.json"
        fi

        if ! grep -q '"minPeerVersion"' "${HOME}/qortal/settings.json"; then
            sed -i '/^{/a \  "minPeerVersion": "4.6.0",' "${HOME}/qortal/settings.json"
        else
            sed -i 's/"minPeerVersion":.*/"minPeerVersion": "4.6.0",/' "${HOME}/qortal/settings.json"
        fi

        # Validate JSON structure
        if ! grep -q '}' "${HOME}/qortal/settings.json"; then
            echo "}" >> "${HOME}/qortal/settings.json"
        fi

        # Ensure the last line does not end with a comma
        sed -i ':a;N;$!ba;s/,\n}/\n}/' "${HOME}/qortal/settings.json"
    fi

    # Restart Qortal and verify
    block_china
    cd qortal
    ./stop.sh
    sleep 45
    ./start.sh
    cd 

    # Verify if Qortal started correctly
    sleep 240
    core_status=$(curl -s localhost:12391/admin/status)
    if [ -z "$core_status" ]; then
        echo "${RED} Qortal did not start correctly, retrying...${NC}\n"
        sleep 120
        core_status=$(curl -s localhost:12391/admin/status)
        if [ -z "$core_status" ]; then
            echo "${RED} Qortal still did not start correctly, restoring previous settings...${NC}\n"
            cp "$BACKUP_FILE" "${HOME}/qortal/settings.json"
            bash "${HOME}/qortal/stop.sh"
            sleep 30
            killall -9 java
            bash "${HOME}/qortal/start.sh"
        fi
    fi
    check_for_GUI
}


block_china() {
    echo "${YELLOW} no longer doing this... shouldn't be seeing this...${NC}\n"
}

check_hash_update_qortal() {
    echo "${RED}API-call-based version checking FAILED${NC}${YELLOW}. ${NC}${CYAN}Proceeding to HASH CHECK${NC}${YELLOW}, checking hash of qortal.jar on local machine VS newest released qortal.jar on github and updating your qortal.jar if needed... ${NC}\n"
    cd "${HOME}/qortal"
    md5sum qortal.jar > "local.md5"
    cd
    echo "${CYAN} Grabbing newest released jar to check hash... ${NC}\n"
    curl -L -O https://github.com/qortal/qortal/releases/latest/download/qortal.jar
    md5sum qortal.jar > "remote.md5"

    LOCAL=$(cat "${HOME}/qortal/local.md5")
    REMOTE=$(cat "${HOME}/remote.md5")

    if [ "$LOCAL" = "$REMOTE" ]; then
        echo "${CYAN} Hash check says your Qortal core is UP-TO-DATE, checking environment... ${NC}\n"
        check_for_GUI
        exit 1
    else
        echo "${RED} Hash check confirmed your qortal core is OUTDATED, ${NC}${YELLOW}updating, bootstrapping, and starting qortal...then checking environment and updating scripts... ${NC}\n"
        cd "${HOME}/qortal"
        killall -9 java
        sleep 3
        rm -rf db log.t* qortal.log run.log run.pid qortal.jar
        cp "${HOME}/qortal.jar" "${HOME}/qortal"
        rm "${HOME}/qortal.jar"
        rm "${HOME}/remote.md5" local.md5
        potentially_update_settings
        ./start.sh
        cd 
        
        check_for_GUI
    fi
}

check_for_GUI() {
    if [ -n "$DISPLAY" ]; then
        echo "${CYAN} Machine is logged in via GUI, setting up auto-fix-visible for GUI-based machines... ${NC}\n"
        if [ "${PI_32_DETECTED}" = true ] || [ "${PI_64_DETECTED}" = true ]; then
            echo "${YELLOW} Pi machine detected with GUI, skipping autostart setup for GUI and setting cron jobs instead...${NC}\n"
            setup_pi_cron
        else
            echo "${YELLOW} Setting up auto-fix-visible on GUI-based system... first, creating new crontab entry without auto-fix-startup... ${NC}\n"
            sleep 2
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-GUI-cron
            crontab auto-fix-GUI-cron
            rm -rf auto-fix-GUI-cron
            echo "${YELLOW} Setting up new ${NC}\n ${WHITE} 'auto-fix-qortal-GUI.desktop' ${NC}\n ${YELLOW} file for GUI-based machines to run 7 min after startup in a visual fashion. Entry in 'startup' will be called ${NC}\n ${WHITE} 'auto-fix-visible' ${NC}\n"
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal-GUI.desktop
            mkdir -p "${HOME}/.config/autostart"
            cp auto-fix-qortal-GUI.desktop "${HOME}/.config/autostart"
            rm -rf "${HOME}/auto-fix-qortal-GUI.desktop"
            echo "${YELLOW} Your machine will now run 'auto-fix-qortal.sh' script in a pop-up terminal, 7 MIN AFTER YOU REBOOT your machine. The normal 'background' process for auto-fix-qortal will continue as normal.${NC}\n"
            echo "${CYAN} continuing to verify node height...${NC}\n"

            check_height
        fi
    else
        echo "${YELLOW} Non-GUI system detected, skipping 'auto-fix-visible' setup... ${NC}${CYAN}configuring cron then checking node height... ${NC}\n"
        setup_pi_cron
    fi
}

setup_pi_cron() {
    echo "${YELLOW} Setting up cron jobs for Raspberry Pi or headless machines... ${NC}\n"
    mkdir -p "${HOME}/backups/cron-backups"
    crontab -l > "${HOME}/backups/cron-backups/crontab-backup-$(date +%Y%m%d%H%M%S)"

    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/auto-fix-cron 
    crontab auto-fix-cron
    rm -rf auto-fix-cron
    # Check if the cron entries already exist, if not add them
    #crontab -l | grep -q "@reboot sleep 6 && ~/start-qortal.sh" || (crontab -l ; echo "@reboot sleep 6 && ~/start-qortal.sh") | crontab -
    #crontab -l | grep -q "@reboot sleep 420 && ~/auto-fix-qortal.sh" || (crontab -l ; echo "@reboot sleep 420 && ~/auto-fix-qortal.sh") | crontab -
    #crontab -l | grep -q "1 1 */3 * * ~/auto-fix-qortal.sh" || (crontab -l ; echo "1 1 */3 * * ~/auto-fix-qortal.sh") | crontab -
    check_height
}

check_height() {
    local_height=$(curl -sS "http://localhost:12391/blocks/height")

    if [ -f auto_fix_last_height.txt ]; then
        previous_local_height=$(cat auto_fix_last_height.txt)
        if [ -n ${previous_local_height} ]; then
            if [ "${local_height}" = "${previous_local_height}" ]; then
                echo "${RED} local height has not changed since previous script run... waiting 3 minutes and checking height again, if height still hasn't changed, forcing bootstrap... ${NC}\n"
                sleep 188
                checked_height=$(curl "localhost:12391/blocks/height")
                sleep 2
                if [ "${checked_height}" = "${previous_local_height}" ]; then
                    echo "${RED} block height still has not changed... forcing bootstrap... ${NC}\n"
                    force_bootstrap
                fi
            fi
        fi
    fi

    if [ -z ${local_height} ]; then
        echo "${RED} local API call for block height returned empty, IS YOUR QORTAL CORE RUNNING? ${NC}\n"
                echo "${RED} if this doesn't work, then the script encountered an issue that it isn't fully equipped to handle, it may fix it upon a restart, TRY RESTARTING THE COMPUTER and WAITING 30 MINUTES... ${NC}\n"
        no_local_height
    else
        echo ${local_height} > auto_fix_last_height.txt
    fi

    remote_height_checks
}

no_local_height() {
    # height checks failed, is qortal running? 
    # make another action here...
    echo "${WHITE} Checking if node is bootstrapping or not...${NC}\n"

    # Check if the main log file exists
    if [ -f "${HOME}/qortal/qortal.log" ]; then
        if tail -n 5 "${HOME}/qortal/qortal.log" | grep -E -i 'bootstrap|bootstrapping' > /dev/null; then
            echo "${RED} NODE SEEMS TO BE BOOTSTRAPPING, UPDATING SCRIPT AND EXITING, NEXT RUN WILL FIND/FIX ANY ISSUES ${NC}\n"
            update_script
        fi
    else
        echo "Checking for old log method..."
        old_log_found=false

        # Check for old log files and process them
        for log_file in "${HOME}/qortal/log.t*"; do
            if [ -f "$log_file" ]; then
                old_log_found=true
                echo "${YELLOW}Old log method found, backing up old logs and updating logging method...${NC}\n"
                mkdir -p "${HOME}/qortal/backup/logs"
                # Move old log files to the backup directory
                mv "${HOME}/qortal/log.t*" "${HOME}/qortal/backup/logs"
                mv "${HOME}/qortal/log4j2.properties" "${HOME}/qortal/backup/logs"
                # Download the new log4j2.properties file
                curl -L -O https://raw.githubusercontent.com/Qortal/qortal/master/log4j2.properties
                # Move the new log4j2.properties file to the qortal directory
                mv log4j2.properties "${HOME}/qortal"
                echo -e "${RED}Stopping Qortal to apply new logging method...${NC}\n"
                # Stop Qortal to apply changes
                cd "${HOME}/qortal"
                ./stop.sh 
                cd 
                break
            fi
        done

        if ! $old_log_found; then
            echo "No old log files found."
        fi
    fi

    echo "${GREEN} Starting Qortal Core and sleeping for 2.5 min to let it startup fully, PLEASE WAIT... ${NC}\n"
    potentially_update_settings
    cd "${HOME}/qortal"
    ./start.sh 
    sleep 166
    cd 
    echo "${GREEN} Checking if Qortal started correctly... ${NC}\n"
    local_height_check=$(curl -sS "http://localhost:12391/blocks/height")
    node_works=$(curl -sS "http://localhost:12391/admin/status")

    if [ -n "$local_height_check" ]; then
        echo "${GREEN} local height is ${NC}${CYAN} ${local_height_check}${NC}\n"
        echo "${GREEN} node is GOOD, re-trying height check and continuing...${NC}\n"
        check_height
    else 
        echo "${RED} starting Qortal Core FAILED... script will exit now until future updates add additional features...sorry the script couldn't resolve your issues! It will update automatically if you have it configured to run automatically! ${NC}${CYAN} It is possible that the script will fix the issue IF YOU RESTART YOUR COMPUTER AND WAIT 15 MINUTES...${NC}\n"
        update_script
    fi
}

remote_height_checks() {
    height_api_qortal_org=$(curl -sS --connect-timeout 10 "https://api.qortal.org/blocks/height")
    height_qortal_link=$(curl -sS --connect-timeout 10 "https://qortal.link/blocks/height")
    local_height=$(curl -sS --connect-timeout 10 "http://localhost:12391/blocks/height")

    if [ -z "$height_api_qortal_org" ] || [ -z "$height_qortal_link" ]; then
        echo "${RED}Failed to fetch data from one or more remote URLs. Skipping remote node checks and updating script ${NC}\n"
        update_script
    fi

    if [ "$height_api_qortal_org" -ge $((local_height - 1500)) ] && [ "$height_api_qortal_org" -le $((local_height + 1500)) ]; then
        echo "${YELLOW}Local height ${NC}(${CYAN}${local_height}${NC})${YELLOW} is within 1500 block range of api.qortal.org node height ${NC}(${GREEN}${height_api_qortal_org}${NC})."
        echo "${GREEN}api.qortal.org height checks PASSED updating script...${NC}"
        update_script
    else
        echo "${RED}Node is outside the 1500 block range of api.qortal.org, checking another node to be sure...${NC}"
        if [ "$height_qortal_link" -ge $((local_height - 1500)) ] && [ "$height_qortal_link" -le $((local_height + 1500)) ]; then
            echo "${YELLOW}Local height ${NC}(${CYAN}${local_height}${NC})${YELLOW} is within 1500 block range of qortal.link node height ${NC}(${GREEN}${height_qortal_link}${NC})."
            echo "${GREEN}qortal.link height checks PASSED updating script...${NC}"
            update_script
        else
            echo "${RED}SECOND remote node check FAILED... ${NC}${YELLOW}assuming local node needs bootstrapping... bootstrapping in 5 seconds...${NC}\n"
            force_bootstrap
            #update_script
        fi
    fi
}

force_bootstrap() {
    echo "${RED} height check found issues, forcing bootstrap... ${NC}\n"
    cd "${HOME}/qortal"
    killall -9 java
    sleep 3
    rm -rf db log.t* qortal.log run.log run.pid
    sleep 5
    ./start.sh
    cd 
    update_script
}

potentially_update_settings() {
    echo "${GREEN}Backing up settings to a timestamped backup file...${NC}"
    echo "${YELLOW}Changing to qortal directory...${NC}"
    cd "${HOME}/qortal"
    if [ ${SETTINGS_UPDATED} ]; then
    	echo "${YELLOW} Settings already updated this run, no need to attempt again...${NC}"
    	return
    fi
    
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    BACKUP_FILE="backup-settings-${TIMESTAMP}.json"
    cp settings.json "${BACKUP_FILE}"

    SETTINGS_FILE="settings.json"

    echo "${YELLOW}Checking for${NC} ${GREEN}archivingPause${NC} ${YELLOW}setting...${NC}"
    if grep -q '"archivingPause"' "${SETTINGS_FILE}"; then
        echo "${BLUE}archivingPause exists...${NC}${GREEN} removing it...${NC}"
        if command -v jq &> /dev/null; then
            echo "${GREEN}jq exists,${NC}${YELLOW} using jq to modify setting...${NC}"
            jq 'del(.archivingPause)' "${SETTINGS_FILE}" > "settings.tmp"
            if [ $? -eq 0 ]; then
                mv "settings.tmp" "${SETTINGS_FILE}"
                SETTINGS_UPDATED=true
            else
                echo "${RED}jq edit failed, restoring backup...${NC}"
                mv "${BACKUP_FILE}" "${SETTINGS_FILE}"
                return 1
            fi
        else
            echo "${BLUE}jq doesn't exist, modifying with sed...${NC}"
            sed -i '/"archivingPause"[[:space:]]*:/d' "${SETTINGS_FILE}"
            if [ $? -ne 0 ]; then
                echo "${RED}sed edit failed, restoring backup...${NC}"
                mv "${BACKUP_FILE}" "${SETTINGS_FILE}"
                return 1
            fi
            SETTINGS_UPDATED=true
        fi
    else
        echo "${BLUE}archivingPause does not exist, no changes needed...${NC}"
    fi

    echo "${GREEN}Settings modification complete.${NC}"
    cd "${HOME}"
    return 0
}



update_script() {
    echo "${YELLOW}Updating script to newest version and backing up old one...${NC}\n"
    mkdir -p "${HOME}/qortal/new-scripts/backups"
    cp "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" "${HOME}/qortal/new-scripts/backups"
    rm -rf "${HOME}/qortal/new-scripts/auto-fix-qortal.sh"
    cp "${HOME}/auto-fix-qortal.sh" "${HOME}/qortal/new-scripts/backups/original.sh"
    cd "${HOME}/qortal/new-scripts"
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
    chmod +x auto-fix-qortal.sh
    cd
    cp "${HOME}/qortal/new-scripts/auto-fix-qortal.sh" "${HOME}/auto-fix-qortal.sh"
    chmod +x auto-fix-qortal.sh
    rm -rf "${HOME}/auto_fix_updated"
    echo "${YELLOW} Auto-fix script run complete.${NC}\n"
    sleep 5 
    potentially_update_settings
    exit
}

initial_update


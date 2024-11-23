#!/bin/bash

QORTAL_RUNNING=$(curl -sS --connect-timeout 10 "localhost:12391/admin/status")
GUI_START="~/.config/autostart/start-qortal.desktop"

if [ -f "${GUI_START}" ]; then
    echo "Qortal is set up to start via GUI, waiting 2 minutes for Qortal to start..."
    sleep 120
    echo "Checking if Qortal is running..."
    QORTAL_RUNNING=$(curl -sS --connect-timeout 10 "localhost:12391/admin/status")
    if [ -n "${QORTAL_RUNNING}" ]; then
        echo "Qortal is already running...not starting Qortal..."
        exit
    else
        echo "Qortal did not start after 2 minutes...waiting another 90 seconds..."
        sleep 90
        echo "Attempting to start Qortal again..."
        bash ~/qortal/start.sh 
        echo "Waiting 120 seconds..."
        sleep 120
        QORTAL_RUNNING=$(curl -sS --connect-timeout 10 "localhost:12391/admin/status")
        if [ -n "${QORTAL_RUNNING}" ]; then 
            echo "Qortal running, exiting..."
            exit
        else 
            echo "Qortal is still not running... checking for auto-fix-visible GUI..."
            if [ -f ~/.config/autostart/auto-fix-visible* ]; then
                echo "auto-fix-visible exists, waiting for auto-fix script to run..."
                exit 1
            else 
                echo "auto-fix-visible doesn't exist... running auto-fix script manually..."
                curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
                chmod +x auto-fix-qortal.sh
                echo "Executing auto-fix-qortal.sh..."
                ./auto-fix-qortal.sh
                exit
            fi
        fi
    fi 
    
else 
    echo "Qortal is not set up to start via GUI...Checking if Qortal is running after a 90-second wait..."
    sleep 90
    QORTAL_RUNNING=$(curl -sS --connect-timeout 10 "localhost:12391/admin/status")
    if [ -z "${QORTAL_RUNNING}" ]; then
        echo "Qortal is not running..."
        echo "Attempting to start Qortal..."
        bash ~/qortal/start.sh 
        echo "Start script has executed, awaiting Qortal start..."
        sleep 90
        echo "Checking if Qortal is running..."
        QORTAL_RUNNING=$(curl -sS --connect-timeout 10 "localhost:12391/admin/status")
        if [ -n "${QORTAL_RUNNING}" ]; then
            echo "Qortal has started successfully! Exiting script..."
            exit
        else
            echo "Qortal did not start...force-killing Java and starting again..."
            killall -9 java
            bash ~/qortal/start.sh
            echo "Qortal start script has been executed..."
            if crontab -l | grep -q '#.*auto-fix-qortal.sh'; then
                echo "'auto-fix-qortal.sh' is commented out in crontab. Manually executing auto-fix script..."
                echo "Grabbing the newest version of auto-fix script..."
                cd 
                curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
                chmod +x auto-fix-qortal.sh
                echo "Executing auto-fix-qortal.sh..."
                ./auto-fix-qortal.sh
                exit
            elif crontab -l | grep -q '[^#]*auto-fix-qortal.sh'; then
                echo "'auto-fix-qortal.sh' is active in crontab...auto-fix script should run automatically within 7 min from reboot..."
                echo "Checking if machine has just booted..."
                UPTIME=$(awk '{print int($1)}' /proc/uptime)
                if [ "${UPTIME}" -ge 420 ]; then
                    echo "Machine has been online longer than 7 min, assuming auto-fix script would have run if it were supposed to..."
                    echo "Running auto-fix script manually..."
                    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
                    chmod +x auto-fix-qortal.sh
                    echo "Executing auto-fix-qortal.sh..."
                    ./auto-fix-qortal.sh
                    exit
                 else
                    echo "Machine has been online less than 7 min, allowing auto-fix script to run on its own..."
                    exit
                 fi
            else
                echo "'auto-fix-qortal.sh' does not exist in crontab."
                echo "Assuming it was removed accidentally..."
                echo "Running auto-fix script manually, and setting it up to run automatically..."
                curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
                chmod +x auto-fix-qortal.sh
                echo "Executing auto-fix-qortal.sh..."
                ./auto-fix-qortal.sh
                exit
            fi
        fi
    else
        echo "Qortal is running, exiting script..."
        exit 
    fi
fi


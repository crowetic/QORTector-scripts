#!/bin/bash

# Check if Qortal is running
QORTAL_RUNNING=$(pgrep -f 'java.*qortal' > /dev/null && echo 1 || echo 0)
GUI_START="${HOME}/.config/autostart/start-qortal.desktop"

if [[ -f "$GUI_START" ]]; then
    echo "Qortal is set to start via GUI. Checking if it is running..."

    if [[ "$QORTAL_RUNNING" -eq 1 ]]; then
        echo "Qortal is already running. Checking if it's responding..."
        sleep 60
        QORTAL_RESPONDING=$(curl -sS --connect-timeout 10 "localhost:12391/admin/status")

        if [[ -n "$QORTAL_RESPONDING" ]]; then
            echo "Qortal is running and responding. Exiting..."
            exit 0
        else
            echo "Qortal is running but not responding. Restarting..."
            killall -9 java
            sleep 5
        fi
    fi

    echo "Qortal is not running. Starting Qortal..."
    cd "${HOME}/qortal" || exit
    ./start.sh
    echo "Waiting 120 seconds..."
    sleep 120

    QORTAL_RUNNING=$(pgrep -f 'java.*qortal' > /dev/null && echo 1 || echo 0)
    QORTAL_RESPONDING=$(curl -sS --connect-timeout 10 "localhost:12391/admin/status")

    if [[ "$QORTAL_RUNNING" -eq 1 ]]; then 
        echo "Qortal started successfully. Verifying response after 60 seconds..."
        sleep 60
        if [[ -n "$QORTAL_RESPONDING" ]]; then
            echo "Qortal is responding! All good! Exiting..."
            exit 0
        fi
    fi

    echo "Qortal is still not running. Checking for auto-fix-visible script..."
    if [[ -f "${HOME}/.config/autostart/auto-fix-visible*" ]]; then
        echo "Auto-fix script exists. Waiting for it to run..."
        exit 1
    else 
        echo "Auto-fix script not found. Downloading and executing manually..."
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
        chmod +x auto-fix-qortal.sh
        ./auto-fix-qortal.sh
        exit 0
    fi
else 
    echo "Qortal is not set to start via GUI. Checking if it is running..."
    
    if [[ "$QORTAL_RUNNING" -eq 1 ]]; then
        echo "Qortal is running. Checking response after 60 seconds..."
        sleep 60
        QORTAL_RESPONDING=$(curl -sS --connect-timeout 10 "localhost:12391/admin/status")

        if [[ -n "$QORTAL_RESPONDING" ]]; then
            echo "Qortal is responding. Exiting..."
            exit 0
        else
            echo "Qortal is running but unresponsive. Restarting..."
            killall -9 java
            sleep 5
        fi
    fi

    echo "Qortal is not running. Attempting to start..."
    cd "${HOME}/qortal" || exit
    ./start.sh
    echo "Start script executed. Waiting 90 seconds..."
    sleep 90

    QORTAL_RUNNING=$(pgrep -f 'java.*qortal' > /dev/null && echo 1 || echo 0)
    QORTAL_RESPONDING=$(curl -sS --connect-timeout 10 "localhost:12391/admin/status")

    if [[ "$QORTAL_RUNNING" -eq 1 ]]; then
        echo "Qortal started successfully. Checking response..."
        if [[ -n "$QORTAL_RESPONDING" ]]; then
            echo "Qortal is running and responding! Exiting..."
            exit 0
        fi
    fi

    echo "Qortal did not start. Killing Java processes and retrying..."
    killall -9 java
    cd "${HOME}/qortal"
    ./start.sh

    echo "Checking crontab for auto-fix script..."
    if crontab -l | grep -q '#.*auto-fix-qortal.sh'; then
        echo "Auto-fix script is commented out. Running manually..."
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
        chmod +x auto-fix-qortal.sh
        ./auto-fix-qortal.sh
        exit 0
    elif crontab -l | grep -q '[^#]*auto-fix-qortal.sh'; then
        echo "Auto-fix script is in crontab. Checking machine uptime..."
        UPTIME=$(awk '{print int($1)}' /proc/uptime)

        if [[ "$UPTIME" -ge 420 ]]; then
            echo "Machine has been online for over 7 minutes. Running auto-fix manually..."
            curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
            chmod +x auto-fix-qortal.sh
            ./auto-fix-qortal.sh
            exit 0
        else
            echo "Machine has been online less than 7 minutes. Allowing auto-fix script to run automatically..."
            exit 0
        fi
    else
        echo "Auto-fix script not found in crontab. Running manually and setting up auto-run..."
        curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/auto-fix-qortal.sh
        chmod +x auto-fix-qortal.sh
        ./auto-fix-qortal.sh
        exit 0
    fi
fi


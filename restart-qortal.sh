#!/bin/bash

DIR="/home/pi/qortal"
SESSION_NAME="qortal.wallet"
START_SCRIPT="./start.sh"
LOGFILE="qortal.wallet.log"


# Shutdown any existing session by sending control-C
#screen -S ${SESSION_NAME} -X stuff '^C' 1>/dev/null 2>&1
cd ${DIR} && ./stop.sh && sleep 10 && killall -9 java
#screen -XS qortal.wallet quit

# Wait for any existing session to exit
#while screen -S ${SESSION_NAME} -Q info 1>/dev/null 2>&1; do
sleep 10
#done

# Start new session
cd ${DIR}
#mv -f ${LOGFILE} ${LOGFILE}.old 1>/dev/null 2>&1
#screen -d -S ${SESSION_NAME} -m /home/qort/qortal/start.sh  -L ${LOGFILE}
./start.sh


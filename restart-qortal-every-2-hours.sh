#!/bin/bash

# Path to the Qortal folder
QORTAL_DIR=~/qortal

while true; do
  # Navigate to Qortal directory
  cd "$QORTAL_DIR" || exit

  # Stop Qortal core
  ./stop.sh

  # Wait for 45 seconds
  sleep 45

  # Kill all Java processes
  killall -9 java

  # Remove blockchain lock file
  rm -rf "$QORTAL_DIR/db/blockchain.lck"

  # Start Qortal core
  ./start.sh

  # Wait for 2 hours before restarting again, while tailing the log file
  sleep 2h &
  tail -f "$QORTAL_DIR/qortal.log"

  # Kill the tail process after sleep is done
  kill $!
done


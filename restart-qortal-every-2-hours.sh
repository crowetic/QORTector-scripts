#!/bin/bash

# Path to the Qortal folder
QORTAL_DIR=~/qortal

# Check if screen is installed
if command -v screen &> /dev/null; then
  echo "Screen is installed, running script in a screen session..."
  SCRIPT_NAME="restart-qortal-every-2-hours.sh"
  cp "$0" "$QORTAL_DIR/$SCRIPT_NAME"
  screen -S qortal_restart -dm bash "$QORTAL_DIR/$SCRIPT_NAME"
  exit 0
else
  echo "Screen is not installed, running script normally..."
fi

while true; do
  # Navigate to Qortal directory
  cd "$QORTAL_DIR" || exit

  # Stop Qortal core
  ./stop.sh &> stop_output.log &
  stop_pid=$!

  # Wait for 30 seconds
  sleep 30

  # Check if stop script succeeded
  if ! grep -q "Qortal ended gracefully" stop_output.log; then
    # Stop script did not complete successfully, kill Java process
    echo "Stop script did not complete successfully, force killing Java..."
    killall -9 java

    # Remove blockchain lock file
    rm -rf "$QORTAL_DIR/db/blockchain.lck"
  else
    echo "Qortal stopped gracefully."
  fi

  # Ensure stop process completes
  wait $stop_pid

  # Start Qortal core
  ./start.sh

  # Wait for 2 hours while logging output --- CHANGE THE NUMBER OF HOURS HERE. 
  sleep 2h &
  sleep_pid=$!
  tail -f "$QORTAL_DIR/qortal.log" &
  tail_pid=$!

  # Wait for the sleep to finish, then kill the tail process
  wait $sleep_pid
  kill $tail_pid
done


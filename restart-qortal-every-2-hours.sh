#!/bin/bash

# Path to the Qortal folder
QORTAL_DIR=~/qortal

while true; do
  # Navigate to Qortal directory
  cd "$QORTAL_DIR" || exit

  # Stop Qortal core
  ./stop.sh &> stop_output.log

  # Wait for 30 seconds
  sleep 30

  # Check if stop script succeeded
  if ! grep -q "Qortal ended gracefully" stop_output.log; then
    # Stop script did not complete successfully, kill Java process
    echo "Stop script did not complete successfully, force killing Java..."
    killall -9 java

    # Remove blockchain lock file
    rm -rf "$QORTAL_DIR/db/blockchain.lck"
  fi

  # Start Qortal core
  ./start.sh

  # Wait for 2 hours while logging output
  sleep 2h &
  sleep_pid=$!
  tail -f "$QORTAL_DIR/qortal.log" &
  tail_pid=$!

  # Wait for the sleep to finish, then kill the tail process
  wait $sleep_pid
  kill $tail_pid
done


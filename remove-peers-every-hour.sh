#!/bin/bash

# Path to the Qortal folder
QORTAL_DIR=~/qortal

while true; do
  # Navigate to Qortal directory
  cd "$QORTAL_DIR" || exit

  # Delete known peers
  ./qort DELETE peers/known

  # Re-add known peers
  ./qort peers home.crowetic.com:22392
  ./qort peers node.qortal.org:12392
  ./qort peers node2.qortal.org:12392
  ./qort peers node3.qortal.org:12392
  ./qort peers node4.qortal.org:12392

  # Tail the log file while sleeping for 1 hour
  sleep 1h &
  tail -f "$QORTAL_DIR/qortal.log"

  # Kill the tail process after sleep is done
  kill $!
done


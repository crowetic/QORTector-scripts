#!/bin/bash

# Path to the Qortal folder
QORTAL_DIR=~/qortal
LOG_FILE="$QORTAL_DIR/peer_monitor_log.txt"
PEER_THRESHOLD=5
CONSECUTIVE_CHECKS=2
CHECK_INTERVAL=300 # 5 minutes in seconds

# Logging function
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if running in screen
if [ -z "$RUNNING_IN_SCREEN" ]; then
  # Check if screen is installed
  if command -v screen &> /dev/null; then
    log "Screen is installed, running script in a screen session..."
    export RUNNING_IN_SCREEN=1
    screen -S qortal_peer_monitor -dm bash -c "RUNNING_IN_SCREEN=1 $(realpath "$0")"
    if [ $? -eq 0 ]; then
      log "Script successfully started in screen session 'qortal_peer_monitor'."
    else
      log "Failed to start script in screen session."
    fi
    exit 0
  else
    log "Screen is not installed, running script normally..."
  fi
fi

# Function to get number of connections
get_number_of_connections() {
  local result=$(curl -s localhost:12391/admin/status)

  if command -v jq &> /dev/null; then
    log "jq is installed, using jq to parse response."
    local connections=$(echo "$result" | jq -r '.numberOfConnections')
  else
    log "jq not installed, executing sed backup method."
    local connections=$(echo "$result" | sed -n 's/.*"numberOfConnections":\([0-9]*\).*/\1/p')
  fi

  log "Number of connections: $connections"
  echo "$connections"
}


# Main monitoring loop
consecutive_fail_or_low_count=0

while true; do
  log "Checking number of connections..."
  num_connections=$(get_number_of_connections)

  if [ -z "$num_connections" ]; then
    log "Failed to obtain number of connections."
    ((consecutive_fail_or_low_count++))
    log "Failed to obtain connections. Consecutive checks: $consecutive_fail_or_low_count"
  else
    log "Number of connections: $num_connections"
    if [ "$num_connections" -lt "$PEER_THRESHOLD" ]; then
      ((consecutive_fail_or_low_count++))
      log "Peer count below threshold ($PEER_THRESHOLD). Consecutive checks: $consecutive_fail_or_low_count"
    else
      consecutive_fail_or_low_count=0
    fi
  fi

  if [ "$consecutive_fail_or_low_count" -ge "$CONSECUTIVE_CHECKS" ]; then
    log "Peer count below threshold for $CONSECUTIVE_CHECKS consecutive checks, initiating restart..."

    # Navigate to Qortal directory
    log "Navigating to Qortal directory..."
    cd "$QORTAL_DIR" || { log "Failed to navigate to Qortal directory."; exit 1; }

    # Stop Qortal core
    log "Stopping Qortal core..."
    ./stop.sh &> stop_output.log &
    stop_pid=$!

    # Wait for 30 seconds
    sleep 45

    # Check if stop script succeeded
    if ! grep -q "Qortal ended gracefully" stop_output.log; then
      log "Stop script did not complete successfully, force killing Java..."
      killall -9 java

      # Remove blockchain lock file
      log "Removing blockchain lock file..."
      rm -rf "$QORTAL_DIR/db/blockchain.lck"
    else
      log "Qortal stopped gracefully."
    fi

    # Ensure stop process completes
    log "Waiting for stop process to complete..."
    wait $stop_pid

    # Start Qortal core
    log "Starting Qortal core..."
    ./start.sh

    # Reset consecutive low count
    consecutive_fail_or_low_count=0
  fi

  # Wait for the next check
  log "Waiting for $CHECK_INTERVAL seconds before next check..."
  sleep $CHECK_INTERVAL
done


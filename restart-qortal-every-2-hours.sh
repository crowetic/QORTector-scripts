#!/bin/bash

# Path to the Qortal folder
QORTAL_DIR=~/qortal
LOG_FILE="$QORTAL_DIR/restart_log.txt"

# Logging function
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Check if screen is installed
if command -v screen &> /dev/null; then
  log "Screen is installed, creating wrapper and running script in a screen session..."

  # Wrapper script name and path
  WRAPPER_SCRIPT="$QORTAL_DIR/start_qortal_wrapper.sh"

  # Create a wrapper script to start the main script
  echo "#!/bin/bash" > "$WRAPPER_SCRIPT"
  echo "bash $(realpath "$0")" >> "$WRAPPER_SCRIPT"
  chmod +x "$WRAPPER_SCRIPT"

  # Run the wrapper script in screen
  screen -S qortal_restart -dm bash -c "cd $QORTAL_DIR && ./start_qortal_wrapper.sh"
  if [ $? -eq 0 ]; then
    log "Wrapper script successfully started in screen session 'qortal_restart'."
  else
    log "Failed to start wrapper script in screen session."
  fi
  exit 0
else
  log "Screen is not installed, running script normally..."
fi

while true; do
  # Navigate to Qortal directory
  log "Navigating to Qortal directory..."
  cd "$QORTAL_DIR" || { log "Failed to navigate to Qortal directory."; exit 1; }

  # Stop Qortal core
  log "Stopping Qortal core..."
  ./stop.sh &> stop_output.log &
  stop_pid=$!

  # Wait for 30 seconds
  sleep 30

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

  # Wait for 2 hours while logging output
  log "Waiting for 2 hours before restarting..."
  sleep 2h &
  sleep_pid=$!
  tail -f "$QORTAL_DIR/qortal.log" &
  tail_pid=$!

  # Wait for the sleep to finish, then kill the tail process
  wait $sleep_pid
  log "2-hour wait complete, killing tail process..."
  kill $tail_pid
done


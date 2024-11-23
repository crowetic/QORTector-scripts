#!/bin/bash

# Usage: ./auto-restart-qortal.sh [restart_interval_hours]

# Check if restart interval is provided
if [ -z "$1" ]; then
  RESTART_INTERVAL_HOURS=6
  log "restart interval is set to: '$RESTART_INTERVAL_HOURS hours'"
  echo "No restart interval provided. Using default: $RESTART_INTERVAL_HOURS hours"
else
  RESTART_INTERVAL_HOURS=$1
fi

QORTAL_DIR="$HOME/qortal" # Default path to Qortal directory
LOG_FILE="$QORTAL_DIR/auto_restart_log.txt"

# Check if screen exists
if command -v screen &> /dev/null; then
  USE_SCREEN=true
else
  USE_SCREEN=false
fi

# Log function
log() {
  if [ -n "$LOG_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
  fi
}

# Function to restart Qortal
restart_qortal() {
  log "Restarting Qortal..."
  cd "$QORTAL_DIR" || {
    log "Failed to change directory to $QORTAL_DIR"
    exit 1
  }
  ./stop.sh
  sleep 60
  ./start.sh
  log "Qortal restarted."
}

# Main loop function
main_loop() {
  log "Restart interval set to: $RESTART_INTERVAL_HOURS hours"
  while true; do
    restart_qortal
    sleep $((RESTART_INTERVAL_HOURS * 3600))  # Convert hours to seconds and wait
  done
}

# Run the script in a screen session if available
if [ "$USE_SCREEN" = true ]; then
  if screen -list | grep -q "auto_restart_monitor"; then
    log "Screen session 'auto_restart_monitor' already exists. Attaching to existing session."
    screen -x auto_restart_monitor
  else
    screen -dmS auto_restart_monitor bash -c "$(declare -f log restart_qortal main_loop); RESTART_INTERVAL_HOURS=$RESTART_INTERVAL_HOURS; QORTAL_DIR=$QORTAL_DIR; LOG_FILE=$LOG_FILE; main_loop"
    log "Started in a new screen session."
  fi
else
  log "Screen not found. Running in the current session."
  main_loop
fi


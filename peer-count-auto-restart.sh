#!/bin/bash

# Usage: ./peer-count-auto-restart.sh [acceptable_number_of_peers]

# Check if acceptable peer count is provided
if [ -z "$1" ]; then
  ACCEPTABLE_PEERS=10
  log "acceptable number of peers is set to: '$ACCEPTABLE_PEERS'"
  echo "No acceptable peer count provided. Using default: $ACCEPTABLE_PEERS"
else
  ACCEPTABLE_PEERS=$1
fi

QORTAL_DIR="$HOME/qortal" # Default path to Qortal directory
LOG_FILE="$QORTAL_DIR/peer_count_restart_log.txt"

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

# Function to get number of connections
get_number_of_connections() {
  local response=$(curl -s localhost:12391/admin/status)

  if command -v jq &> /dev/null; then
    echo "$response" | jq '.numberOfConnections'
  else
    echo "$response" | sed -n 's/.*"numberOfConnections":\([0-9]*\).*/\1/p'
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
  sleep 25
  ./start.sh
  log "Qortal restarted."
}

# Main loop function
main_loop() {
  log "Sleeping 3 minutes until first peer check..."
  log "Number of acceptable peers set: $ACCEPTABLE_PEERS"
  sleep 180  # Wait for 3 minutes before starting checks
  while true; do
    number_of_connections=$(get_number_of_connections)

    if [ -z "$number_of_connections" ]; then
      log "Failed to retrieve number of connections."
    elif [[ "$number_of_connections" =~ ^[0-9]+$ ]] && [ "$number_of_connections" -lt "$ACCEPTABLE_PEERS" ]; then
      log "Number of connections ($number_of_connections) is below acceptable threshold ($ACCEPTABLE_PEERS). Restarting Qortal..."
      restart_qortal
    else
      log "Number of connections: ($number_of_connections) - is acceptable. No restarting needed..."
      log "Set peer count: $ACCEPTABLE_PEERS"
    fi

    sleep 300  # Wait for 5 minutes before next check
  done
}

# Run the script in a screen session if available
if [ "$USE_SCREEN" = true ]; then
  if screen -list | grep -q "peer_count_monitor"; then
    log "Screen session 'peer_count_monitor' already exists. Attaching to existing session."
    log "Acceptable peer count set: $ACCEPTABLE_PEERS"
    screen -x peer_count_monitor
  else
    screen -dmS peer_count_monitor bash -c "$(declare -f log get_number_of_connections restart_qortal main_loop); ACCEPTABLE_PEERS=$ACCEPTABLE_PEERS; QORTAL_DIR=$QORTAL_DIR; LOG_FILE=$LOG_FILE; main_loop"
 main_loop"
    log "Started in a new screen session."
    log "Acceptable peer count set: $ACCEPTABLE_PEERS"
  fi
else
  log "Screen not found. Running in the current session."
  log "Acceptable peer count set: $ACCEPTABLE_PEERS"
  main_loop
fi


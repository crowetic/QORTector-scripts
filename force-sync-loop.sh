#!/bin/bash

API_KEY=$(cat ~/qortal/apikey.txt)

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [1|2] <node>"
    exit 1
fi

OPTION=$1
NODE=$2

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

case $OPTION in
    1)
        while true; do
            log "Deleting known peers"
            ./qort DELETE peers/known
            sleep 3

            log "Adding peer: $NODE"
            ./qort peers "$NODE"
            sleep 3

            for i in {1..15}; do
                log "Forcing sync with: $NODE (attempt $i)"
                ./qort admin/forcesync "$NODE"
                RESPONSE=$(curl -s -X POST localhost:12391/admin/forcesync -H "X-API-KEY:$API_KEY" -d "$NODE")
                if [[ "$RESPONSE" == *"true"* ]]; then
                    log "Sync successful, sleeping for 1 hour"
                    sleep 3600
                    break
                fi
                sleep 3
            done
        done
        ;;
    2)
        while true; do
            log "Deleting known peers via curl"
            curl -X DELETE localhost:12391/peers/known -H "X-API-KEY:$API_KEY"
            sleep 3

            log "Adding peer via curl: $NODE"
            curl -X POST localhost:12391/peers -H "X-API-KEY:$API_KEY" -d "$NODE"
            sleep 3

            for i in {1..15}; do
                log "Forcing sync via curl with: $NODE (attempt $i)"
                curl -X POST localhost:12391/admin/forcesync -H "X-API-KEY:$API_KEY" -d "$NODE"
                RESPONSE=$?
                if [[ "$RESPONSE" == *"true"* ]]; then
                    log "Sync successful, sleeping for 1 hour"
                    sleep 3600
                    break
                fi
                sleep 3
            done
        done
        ;;
    *)
        echo "Invalid option. Use 1 for qort script method or 2 for curl method."
        exit 1
        ;;
esac


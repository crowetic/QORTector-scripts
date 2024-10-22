#!/bin/bash

API_KEY=$(cat ~/qortal/apikey.txt)

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 [1|2] <node>"
    exit 1
fi

OPTION=$1
NODE=$2

case $OPTION in
    1)
        while true; do
            ./qort DELETE peers/known
            sleep 3
            ./qort peers "$NODE"
            sleep 3
            for i in {1..7}; do
                ./qort admin/forcesync "$NODE"
                sleep 3
            done
        done
        ;;
    2)
        while true; do
            curl -X DELETE localhost:12391/peers/known -H "X-API-KEY:$API_KEY"
            sleep 1
            curl -X POST localhost:12391/peers -H "X-API-KEY:$API_KEY" -d "$NODE"
            sleep 1
            for i in {1..7}; do
                curl -X POST localhost:12391/admin/forcesync -H "X-API-KEY:$API_KEY" -d "$NODE"
                sleep 1
            done
        done
        ;;
    *)
        echo "Invalid option. Use 1 for qort script method or 2 for curl method."
        exit 1
        ;;
esac


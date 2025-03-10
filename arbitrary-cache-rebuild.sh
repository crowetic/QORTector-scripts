#!/bin/bash

# Read API key, removing any trailing newline
API_KEY=$(cat "${HOME}/qortal/apikey.txt" | tr -d '\n')

# Send the request
curl -X POST localhost:12391/arbitrary/resources/cache/rebuild -H "X-API-KEY: ${API_KEY}"

# Append argument to file only if provided
if [ -n "$1" ]; then
  echo "$1" >> arbitraryCacheComplete.txt
fi

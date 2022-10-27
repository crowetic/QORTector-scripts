#!/bin/sh
cd
cd qortal
killall -9 java
sleep 5
rm -R db
rm start.sh
rm qortal.jar
rm log.t*
curl -L -O https://github.com/qortal/qortal/releases/latest/download/qortal.jar
curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-modified-memory-args.sh
mv start-modified-memory-args.sh start.sh
chmod +x start.sh
./start.sh

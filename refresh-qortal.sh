#!/bin/sh
cd
cd qortal
./stop.sh
sleep 5
rm -R db
rm qortal.jar
rm log.t*
wget https://github.com/qortal/qortal/releases/latest/download/qortal.jar
./start.sh

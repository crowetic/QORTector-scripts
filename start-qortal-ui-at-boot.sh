#!/bin/sh
cd UI/qortal-ui
#screen -d -S Qortal-UI -m yarn run server -L UI-start.log
screen -d -S Qortal-UI -m yarn run server 
echo Qortal UI should have started 

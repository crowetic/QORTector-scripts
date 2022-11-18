#!/bin/sh

cd ~/qortal

./qort admin/status

sleep 10

tail -f log.t*

sleep 600

exit 1

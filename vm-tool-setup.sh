#!/bin/bash
sudo apt update 
sudo apt -y upgrade 
sudo apt install -y qemu-guest-agent util-linux haveged 
sudo fstrim -av 
sudo systemctl enable --now qemu-guest-agent

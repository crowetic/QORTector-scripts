#!/bin/bash

set -euo pipefail

echo "=== [1/5] Updating system and installing tools ==="
sudo apt update
sudo apt -y upgrade
sudo apt install -y qemu-guest-agent util-linux haveged ethtool

echo "=== [2/5] Enabling qemu-guest-agent ==="
sudo systemctl enable --now qemu-guest-agent

echo "=== [3/5] Trimming filesystems ==="
sudo fstrim -av || true

echo "=== [4/5] Detecting VM network interfaces ==="
NIC_LIST=()
for nic in /sys/class/net/*; do
    nicname=$(basename "$nic")
    if [[ "$nicname" != "lo" && "$nicname" != vmbr* && "$nicname" != tap* && "$nicname" != veth* && "$nicname" != docker* ]]; then
        NIC_LIST+=("$nicname")
    fi
done

if [[ ${#NIC_LIST[@]} -eq 0 ]]; then
    echo "⚠️ No usable NICs detected. Exiting."
    exit 1
fi

echo "VM NICs detected: ${NIC_LIST[*]}"

echo "=== [5/5] Creating persistent systemd service to disable offloads ==="
SERVICE_FILE="/etc/systemd/system/disable-vm-nic-offloads.service"

{
    echo "[Unit]"
    echo "Description=Disable all VM NIC offloads at boot"
    echo "After=network.target"
    echo ""
    echo "[Service]"
    echo "Type=oneshot"
    for nic in "${NIC_LIST[@]}"; do
        echo "ExecStart=/usr/sbin/ethtool -K $nic tx off rx off tso off gso off gro off"
        echo "ExecStart=/sbin/ip link set $nic txqueuelen 10000"
    done
    echo "RemainAfterExit=yes"
    echo ""
    echo "[Install]"
    echo "WantedBy=multi-user.target"
} | sudo tee "$SERVICE_FILE" > /dev/null

echo "=== Enabling and starting NIC offload disable service ==="
sudo systemctl daemon-reload
sudo systemctl enable --now disable-vm-nic-offloads.service

echo "=== ✅ VM NIC setup complete ==="
for nic in "${NIC_LIST[@]}"; do
    echo "--- $nic ---"
    ethtool -k "$nic" | grep -E 'segmentation|offload|scatter|checksum'
    ip link show "$nic" | grep txqueuelen
done

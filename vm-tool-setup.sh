#!/bin/bash

set -euo pipefail

echo "=== [1/5] Updating system and installing tools ==="
sudo apt update
sudo apt -y upgrade
sudo apt install -y qemu-guest-agent util-linux haveged ethtool lshw dmidecode

echo "=== [2/5] Enabling qemu-guest-agent ==="
sudo systemctl enable --now qemu-guest-agent

echo "=== [3/5] Trimming filesystems ==="
sudo fstrim -av || true

echo "=== [4/5] Detecting VM NICs ==="
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

echo "=== [5/5] Creating systemd service with conditional logic ==="
SERVICE_FILE="/etc/systemd/system/conditional-nic-offload.service"

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Disable NIC offloads only if KVM + Broadcom detected
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c '
HYPERVISOR=\$(systemd-detect-virt)
BROADCOM_FOUND=\$(lspci | grep -i "broadcom" || true)
if [[ "\$HYPERVISOR" == "kvm" && -n "\$BROADCOM_FOUND" ]]; then
  echo "✅ Broadcom NIC on KVM detected — applying NIC tuning";
$(for nic in "${NIC_LIST[@]}"; do
    echo "/usr/sbin/ethtool -K $nic tx off rx off tso off gso off gro off;"
    echo "/sbin/ip link set $nic txqueuelen 10000;"
done)
else
  echo "❌ Skipping NIC tuning — not KVM with Broadcom NIC"
fi
'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

echo "=== Reloading systemd and enabling service ==="
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now conditional-nic-offload.service

echo "=== ✅ VM NIC conditional optimization complete ==="
for nic in "${NIC_LIST[@]}"; do
    echo "--- $nic ---"
    ethtool -k "$nic" | grep -E 'segmentation|offload|scatter|checksum' || true
    ip link show "$nic" | grep txqueuelen || true
done

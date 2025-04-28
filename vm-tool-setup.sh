#!/bin/bash

set -euo pipefail

echo "=== [1/5] Installing essentials and disabling pro notifications==="
sudo pro config set apt_news=false
sudo apt update
sudo apt -y upgrade
sudo apt install -y qemu-guest-agent util-linux haveged ethtool lshw dmidecode

echo "=== [2/5] Enabling qemu-guest-agent ==="
sudo systemctl enable --now qemu-guest-agent

echo "=== [3/5] Trimming filesystems ==="
sudo fstrim -av || true

# echo "=== [4/5] Creating conditional NIC tuning script ==="
# TUNER_SCRIPT="/usr/local/sbin/conditional-nic-tuning.sh"

# sudo tee "$TUNER_SCRIPT" > /dev/null <<'EOSCRIPT'
# #!/bin/bash
# set -euo pipefail

# HYPERVISOR=$(systemd-detect-virt)
# BROADCOM_FOUND=$(lspci | grep -i "broadcom" || true)

# if [[ "$HYPERVISOR" == "kvm" && -n "$BROADCOM_FOUND" ]]; then
#   echo "✅ Broadcom NIC on KVM detected — applying NIC tuning"

#   for nic in /sys/class/net/*; do
#     name=$(basename "$nic")
#     [[ "$name" =~ ^(lo|vmbr|tap|veth|docker) ]] && continue

#     echo "→ Tuning $name"
#     /usr/sbin/ethtool -K "$name" tx off rx off tso off gso off gro off || true
#     /sbin/ip link set "$name" txqueuelen 10000 || true
#   done
# else
#   echo "❌ Skipping NIC tuning — not KVM with Broadcom NIC"
# fi
# EOSCRIPT

# sudo chmod +x "$TUNER_SCRIPT"

# echo "=== [5/5] Creating systemd service file ==="
# SERVICE_FILE="/etc/systemd/system/conditional-nic-offload.service"

# sudo tee "$SERVICE_FILE" > /dev/null <<EOF
# [Unit]
# Description=Disable NIC offloads only if KVM + Broadcom detected
# After=network-online.target
# Wants=network-online.target

# [Service]
# Type=oneshot
# ExecStart=$TUNER_SCRIPT
# RemainAfterExit=yes

# [Install]
# WantedBy=multi-user.target
# EOF

echo "=== Reloading systemd and enabling service ==="
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now conditional-nic-offload.service

echo "=== ✅ VM NIC conditional optimization complete ==="

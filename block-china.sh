#!/bin/bash

# List of Chinese IP ranges
declare -a ip_ranges=(
    "36.0.0.0/8"
    "39.0.0.0/8"
    "42.0.0.0/8"
    "58.0.0.0/8"
    "59.0.0.0/8"
    "60.0.0.0/8"
    "61.0.0.0/8"
    "101.0.0.0/8"
    "103.0.0.0/8"
    "106.0.0.0/8"
    "110.0.0.0/8"
    "111.0.0.0/8"
    "112.0.0.0/8"
    "113.0.0.0/8"
    "114.0.0.0/8"
    "115.0.0.0/8"
    "116.0.0.0/8"
    "117.0.0.0/8"
    "118.0.0.0/8"
    "119.0.0.0/8"
    "120.0.0.0/8"
    "121.0.0.0/8"
    "122.0.0.0/8"
    "123.0.0.0/8"
    "124.0.0.0/8"
    "125.0.0.0/8"
    "202.0.0.0/8"
    "203.0.0.0/8"
)

# Loop through the IP ranges and add iptables rules to block inbound and outbound traffic
for ip_range in "${ip_ranges[@]}"
do
    # Block inbound traffic
    sudo iptables -A INPUT -s $ip_range -j DROP
    echo "Blocked inbound traffic from IP range: $ip_range"

    # Block outbound traffic
    sudo iptables -A OUTPUT -d $ip_range -j DROP
    echo "Blocked outbound traffic to IP range: $ip_range"
done

# Add connection limit rule on port 12392
sudo iptables -A INPUT -p tcp --syn --dport 12392:12392 -m connlimit --connlimit-above 15 --connlimit-mask 32 -j REJECT --reject-with tcp-reset
echo "Connection limit rule added on port 12392"


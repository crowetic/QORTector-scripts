#!/bin/bash

# This script automates the setup of Qortal with nginx proxy, SSL configuration, and other system settings.

# Define functions for installing packages and handling user input
install_packages() {
    sudo apt update 
    sudo apt install -y nginx certbot python3-certbot-nginx curl git default-jdk
}

setup_qortal() {
    # Clone Qortal repository and run the setup script
    curl -L -O https://raw.githubusercontent.com/crowetic/QORTector-scripts/refs/heads/main/generic-linux-setup.sh
    chmod +x generic-linux-setup.sh
    ./generic-linux-setup.sh
}

configure_nginx() {
    read -p "Enter the domain name for nginx configuration: " DOMAIN
    read -p "Do you have an existing SSL certificate? (yes/no): " SSL_CERT_CHOICE
    if [[ $SSL_CERT_CHOICE == "yes" ]]; then
        read -p "Enter the SSL certificate path: " CERT_PATH
        read -p "Enter the SSL certificate key path: " CERT_KEY_PATH
    else
        echo "Setting up SSL certificate using Certbot. Ensure ports 80 and 443 are open."
        sudo certbot --nginx -d "$DOMAIN"
        CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
        CERT_KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
    fi

    LAN_IP=$(hostname -I | awk '{print $1}')

    # Backup existing nginx config files
    cd
    mkdir -p nginx-config-backup
    sudo rsync -raPz /etc/nginx/sites-enabled/* nginx-config-backup/
    sudo rm -rf /etc/nginx/sites-enabled/*

    # Create nginx configuration
    cat <<EOF > "qortal-gateway-node"
server {
    server_name $DOMAIN;
    ssl_certificate $CERT_PATH;
    ssl_certificate_key $CERT_KEY_PATH;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://$LAN_IP:8080;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Enable nginx configuration and restart nginx
    cd
    sudo cp qortal-gateway-node /etc/nginx/sites-available
    mkdir -p backups
    mv -f qortal-gateway-node backups/"qortal-gateway-node-nginx-config"
    sudo ln -s /etc/nginx/sites-available/qortal-gateway-node /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl restart nginx
}

configure_qortal_settings() {
    # Check if Qortal core is running
    QORTAL_RUNNING=false
    if curl -s localhost:12391/admin/status > /dev/null; then
        QORTAL_RUNNING=true
        echo "Qortal core is currently running. It will be restarted after settings modification."
    fi
    # Modify settings.json in ~/qortal directory
    SETTINGS_PATH="$HOME/qortal/settings.json"
    if [[ -f $SETTINGS_PATH ]]; then
      mkdir -p backups && cp $SETTINGS_PATH backups/"qortal-settings-json-rename-to-settings.json-if-required"
    fi
    cat <<EOF > $SETTINGS_PATH
{
  "gatewayEnabled": true,
  "gatewayPort": 8080,
  "maxPeers": 333,
  "maxNetworkThreadPoolSize": 2200,
  "repositoryConnectionPoolSize": 4620,
  "allowConnectionsWithOlderPeerVersions": false,
  "minPeerVersion": "4.6.0",
  "maxThreadsPerMessageType": [
        { "messageType": "ARBITRARY_DATA_FILE", "limit": 25 },
        { "messageType": "GET_ARBITRARY_DATA_FILE", "limit": 25 },
        { "messageType": "ARBITRARY_DATA", "limit": 25 },
        { "messageType": "GET_ARBITRARY_DATA", "limit": 25 },
        { "messageType": "ARBITRARY_DATA_FILE_LIST", "limit": 25 },
        { "messageType": "GET_ARBITRARY_DATA_FILE_LIST", "limit": 25 },
        { "messageType": "ARBITRARY_SIGNATURES", "limit": 25 },
        { "messageType": "ARBITRARY_METADATA", "limit": 25 },
        { "messageType": "GET_ARBITRARY_METADATA", "limit": 25 },
        { "messageType": "GET_TRANSACTION", "limit": 25 },
        { "messageType": "TRANSACTION_SIGNATURES", "limit": 25 },
        { "messageType": "TRADE_PRESENCES", "limit": 25 }
  ],
  "builtDataExpiryInterval": "5 * 24 * 60 * 60 * 1000L",
  "minOutbountPeers": 32,
  "maxDataPeers": 22,
  "maxDataPeerConnectionTime": "8*60",
  "slowQueryThreshold": "8000",
  "apiLoggingEnabled": true,
  "blockCacheSize": 220,
  "apiRestricted": true,
  "listenAddress": "0.0.0.0",
  "apiWhitelistEnabled": false,
  "minBlockchainPeers": 3
}
EOF

# Restart Qortal core if it was running before settings modification
    if [[ $QORTAL_RUNNING == true ]]; then
        echo "Restarting Qortal core...Please wait...will take ~30 seconds..."
        cd ~/qortal
        ./stop.sh && sleep 25 && ./start.sh
        cd
    fi
}

setup_cron() {
    read -p "Do you want to start Qortal on boot? (yes/no): " START_ON_BOOT
    if [[ $START_ON_BOOT == "yes" ]]; then
        (crontab -l ; echo "@reboot ~/QORTector-scripts/start-qortal.sh") | crontab -
    fi
}

# Main execution
install_packages
setup_qortal
configure_nginx
configure_qortal_settings
setup_cron

echo "Setup complete!"
exit 0


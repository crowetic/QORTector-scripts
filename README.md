# QORTector-scripts

simple scripts for various needs on the raspberry pi 4 for use with Qortal.

##*notice* - these scripts are NOT for 'Brooklyn R' kernel for the QORTector devices at this point. You CAN use the 'update-qortal-ui.sh' script AND the 'Start-Qortal-UI-Electron.sh' scripts to build/update the Qortal UI from source, and start it using the Electron 'wrapper', but you CANNOT use the other scripts as they are meant for DEFAULT operating systems for the Pi 4, like Ubuntu 64, and Raspbian. Running any of the other scripts on the Brooklyn kernel, will cause issues and are unnecessary anyway, as the Brooklyn kernel already has all the base level dependencies installed.

## to start - install default OS of your choice for raspberry pi 4 - these scripts are tested and working with raspbian and ubuntu 64 for the Raspberry Pi 4.

1. Setup your base OS - raspbian or ubuntu 64 (other .deb builds should also work.)

2. Download all scripts to your home folder.

```wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/Start-Qortal-UI-Electron.sh
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/default-pi4-ubuntu-qortal-setup.sh
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/install-raspi-config.sh
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal-at-boot.sh
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/start-qortal-ui-at-boot.sh
wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/update-qortal-ui.sh
```

### 3. make all scripts executable

```chmod +x *.sh```

### 4. run 'default-pi4-ubuntu-qortal-setup.sh' (./default*.sh) - this will install the base level packages you need for Qortal, as well as the Qortal Core.

```./default*.sh```

### 5. run 'update-qortal-ui.sh' (./update*.sh) - this will clone+build the Qortal UI from source.

```./update*.sh```

### 6. use crontab to setup a cron to start the Qortal Core at boot (crontab -e) add line (@reboot ./start-qortal-at-boot.sh)

```crontab -e```

add following line in cron

```@reboot ./start-qortal-at-boot.sh```

### 7. use 'Start-Qortal-UI-Electron.sh' to start Qortal UI with Electron wrapper (as an independent application) - Run this script whenever you want to start the UI - placing this script on the desktop is a good idea. Click 'run' when you double-click the script with the GUI.

### 8. install 'raspi-config' with 'install-raspi-config.sh' (./install*.sh)

```./install*.sh```

#### 9. ((OPTIONAL)) - if you prefer to start the Qortal UI as a server that can be accessed by other systems on the network, or SSH tunneled to use locally along with the core, you can use 'start-qortal-ui-at-boot.sh' in cron to start the UI server automatically at boot.

#### 10. update Qortal UI - you can run 'update-qortal-ui.sh' again to re-clone and build the UI from source again for version updates.

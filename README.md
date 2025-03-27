# crowetic's QORTector-scripts

## All scripts related to Qortal and linux (some Mac compatible) by crowetic.

# Primary Scripts / Functions

### 'rebuilt-machine.sh' 
The rebuilt machine script is a FULL LINUX (Ubuntu based and potentially Debian although as-of-yet untested on Debian) SETUP SCRIPT. 
- This script sets up linux
- This script sets up Qortal
- Qortal-UI (legacy UI) 
- Qortal HUB (with launchers in the menu) 
- Custom Qortal icon theme to be able to use 'qortal' 'qortal-ui' 'qortal-hub' 'qortal-menu-button' through 'qortal-menu-button-4' and more.
- Qortal Core installation 
- Full Qortal autoamtion 
- Full Qortal integration 
















**This used to be a location for scripts solely related to the raspberry pi** - this is **no longer the case**. 

This is now a location for multiple different **automation scripts** written by crowetic. They are focused on **automating Qortal** in multiple ways. 

Most important script is probably **auto-fix-qortal.sh** - This script is utilized to **automatically update the Qortal core and more, even if auto-update doesn't work for some reason.** The idea behind this script is that it will **keep your Qortal Core updated no matter what happens. With either a system reboot or automatically on a schedule.** Initial schedule is **every 5 days at 1:01 AM**. 

This script will be getting constant improvements to be more in-depth, and **check for more potential scenarios** where issues may arise, and resolve them automatically as well.

As of **May 24th 2023** the script has been **updated** to include **a new feature that automatically sets the RAM for the JVM on linux-based machines.** This feature was built so that no matter how much RAM your systme has, the Qortal Core will be **given optimal RAM settings** and will **run correctly in any scenario**. (This is the HOPE, anyway... there are always anomalies...)

The **auto-fix-script also updates itself**, so if you have **installed the script in the past** you **do NOT have to continaully come back and check for new versions, the script does that for you every time it is run.** (If you do not want the script to do this, you can simply remove the cron entry that runs it automatically on a schedule, but it is not recommended to remove this unless you know what you're doing and plan to manage your node yourself.)

**Another feature** is being added now as well, not certain if it will be completed as of this writing or not at this point, however... The **new feature will check for a GUI-based machine, then modify the auto-fix script so that it runs in a VISIBLE fashion.** This is to address concerns over potentially not SEEING that the script is RUNNING, and rebooting machines during the process, thus causing issues with the Qortal installation.

This feature will **modify existing auto-fix machines automatically** when the script runs on its schedule, and if all goes well, there should be no manual intervention necessary in any regard. Once this modification DOES go live, the auto-fix script will be VISIBLE when it is run upon system startup, and users can follow what the script is doing with the output it displays in the terminal. This will also make it so that if the script DOES have to 'fix' the Qortal Core, it will do THAT in a visible fashion as well, allowing the user to SEE the bootstrap process with the normal Qortal 'splash screen'.

As time goes on the plan is to also make this script check that the node is within x number of blocks from the chain tip, then if it is not, resolve that scenario as well.

## Many other scripts / tools

There are many other scripts and tools in this repo, most of which are not fully labeled. Explanations of each will be published as time goes on, so that they become more useful to others outside of Crowetic Hardware Development team.












-----------------------------------------------keeping old readme for reference---------------------------------stuff below this line is outdated and no longer used in most cases------------------------


# QORTector-scripts

**The following readme is a little outdated, but the information can still be useful** - This repository has since been updated to include multiple other types of scripts as well as ones meant for the Raspberry Pi 4. Now includes scripts for default machines running Ubuntu, to apply some of the customizations used on CHD rebuilt laptops, and more. Further scripts will continue to be added with information regarding each as time goes on.

I will leave the information below as it is still useful for people wishing to know how to manually build the raspberry pi installation from a default Ubuntu 64 install, and setup the UI to build from source, however most of the things in the information below are no longer used nor necessary. Qortal has evolved significantly since the initial writing of this information and first versions of the scripts.

The newest scripts are updated continually and will be utilized for a while, eventually the repo itself will move to QDN.

### *notice* - these scripts are NOT for 'Brooklyn R' kernel for the QORTector devices at this point. You CAN use the 'update-qortal-ui.sh' script AND the 'Start-Qortal-UI-Electron.sh' scripts to build/update the Qortal UI from source, and start it using the Electron 'wrapper', but you CANNOT use the other scripts as they are meant for DEFAULT operating systems for the Pi 4, like Ubuntu 64, and Raspbian. Running any of the other scripts on the Brooklyn kernel, will cause issues and are unnecessary anyway, as the Brooklyn kernel already has all the base level dependencies installed.

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

**to add Start script to desktop**

```cd Desktop```

```wget https://raw.githubusercontent.com/crowetic/QORTector-scripts/main/Start-Qortal-UI-Electron.sh```

```chmod Start*.sh && cd```

**once the script is on the desktop and chmodded, you can double-click from within the OS GUI, and click 'run' on the pop-up message, and the UI will run.**

### 8. install 'raspi-config' with 'install-raspi-config.sh' (./install*.sh)

```./install*.sh```

#### 9. ((OPTIONAL)) - if you prefer to start the Qortal UI as a server that can be accessed by other systems on the network, or SSH tunneled to use locally along with the core, you can use 'start-qortal-ui-at-boot.sh' in cron to start the UI server automatically at boot.

#### 10. update Qortal UI - you can run 'update-qortal-ui.sh' again to re-clone and build the UI from source again for version updates.

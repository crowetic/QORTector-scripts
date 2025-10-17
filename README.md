# QORTector-scripts

## All scripts related to Qortal and linux (some Mac compatible) by crowetic.
Visit https://crowetic.com for more information on crowetic and CHD.

# Primary Scripts / Functions

### 'Qortal-Setup-Linux.sh' 
This script is built to automatically **INSTALL and CONFIGURE BOTH the QORTAL CORE AND QORTAL HUB on ANY linux machine**. The script is also available on 'install-linux.qortal.org' but the primary repo that it comes from is here. The clone version on the qortal repo (https://github.com/Qortal/QORTector-scripts) is the one that automatically updates the install-linux link above. 

- Automatically detects the linux version running
- Installs necessary dependencies (and some additional helpful packages) - Java, unzip, jq, etc.
- Installs Qortal Core (and makes a backup if an existing version is found), it also restores the data path location and other important settings found if a backup takes place. 
- Installs Qortal Hub
- Installs Qortal Icon theme (a beautiful icon theme that allows use of 'qortal' 'qortal-hub' 'qortal-menu-button' as icons in linux desktop environments)
- Creates launchers for Qortal Hub and Qortal Core
- Offers the user the option to setup the auto-fix-qortal.sh script to automate ensuring Qortal is always updated and synchronized within 1500 blocks of the network height (based upon calls to a redundant set of public nodes run by CHD - https://crowetic.com )

This script is definitely the simplest way to install Qortal on any linux computer. 

Run this script in the recommended fashion with the command below... 
`bash <(curl -fsSL https://install-linux.qortal.org || wget -qO- https://install-linux.qortal.org)`


### 'rebuilt-machine.sh' 
This script is built to run on Ubuntu and Ubuntu-based Linux distros (PoP-OS, ZorinOS, etc.) It configures and installs all software recommended by default by CHD (https://crowetic.com), and configures a customized version of the **cinnamon desktop environment**. This script is meant to be run on a NEW installation of Ubuntu or supported distros. 

- Configures Ubuntu Distro and required/recommended default packages.
- Configures and sets up Qortal Core
- Qortal HUB (with launchers in the menu) 
- Custom Qortal icon theme to be able to use 'qortal' 'qortal-ui' 'qortal-hub' 'qortal-menu-button' through 'qortal-menu-button-4' and more.
- Qortal Core installation 
- Full Qortal autoamtion 
- Full Qortal integration 


### 'auto-fix-qortal.sh' 
**auto-fix-qortal.sh** - This script is utilized to **automatically update the Qortal core and more, even if auto-update doesn't work for some reason.** The idea behind this script is that it will **keep your Qortal Core updated no matter what happens. With either a system reboot or automatically on a schedule.** Initial schedule is **every 3 days at 1:01 AM**. 

This script will be getting constant improvements to be more in-depth, and **check for more potential scenarios** where issues may arise, and resolve them automatically as well.

As of **May 24th 2023** the script has been **updated** to include **a new feature that automatically sets the RAM for the JVM on linux-based machines.** This feature was built so that no matter how much RAM your systme has, the Qortal Core will be **given optimal RAM settings** and will **run correctly in any scenario**. (This is the HOPE, anyway... there are always anomalies...)

The **auto-fix-script also updates itself**, so if you have **installed the script in the past** you **do NOT have to continaully come back and check for new versions, the script does that for you every time it is run.** (If you do not want the script to do this, you can simply remove the cron entry that runs it automatically on a schedule, but it is not recommended to remove this unless you know what you're doing and plan to manage your node yourself.)

The script **will check for a GUI-based machine, then modify the auto-fix script so that it runs in a VISIBLE fashion.** This is to address concerns over potentially not SEEING that the script is RUNNING, and rebooting machines during the process, thus causing issues with the Qortal installation.

This feature will **modify existing auto-fix machines automatically** when the script runs on its schedule, and if all goes well, there should be no manual intervention necessary in any regard. Once this modification DOES go live, the auto-fix script will be VISIBLE when it is run upon system startup, and users can follow what the script is doing with the output it displays in the terminal. This will also make it so that if the script DOES have to 'fix' the Qortal Core, it will do THAT in a visible fashion as well, allowing the user to SEE the bootstrap process with the normal Qortal 'splash screen'.

As time goes on the plan is to also make this script check that the node is within x number of blocks from the chain tip, then if it is not, resolve that scenario as well.

## Many other scripts / tools

There are many other scripts and tools in this repo, most of which are not fully labeled. Explanations of each will be published as time goes on, so that they become more useful to others outside of Crowetic Hardware Development team.










#### This repo is no longer solely about ARM-based systems, and is able to be utilized on multiple systems. 
**This used to be a location for scripts solely related to the raspberry pi** - this is **no longer the case**. 




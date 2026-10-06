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
- Offers the user the option to setup the auto-fix-qortal.sh script to automate ensuring Qortal is always updated and synchronized within 2500 blocks of the network height (based upon calls to a redundant set of public nodes run by CHD - https://crowetic.com )

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

#### How it works (decision flow)
1. **Self-update** validates Bash syntax, required functions and script revision. Older scripts cannot overwrite this version.
2. **Check connectivity**, refresh helper scripts, and install a syntax-checked JVM start script for the platform and RAM size.
3. **Version check** uses GitHub release metadata, its latest-release redirect, then the releases list (excluding drafts and prereleases). Version components are compared correctly. Unknown release metadata preserves an existing jar.
4. **Jar update** compares file contents, validates the downloaded archive, stops the specific Core process and retains `qortal.jar.previous`. Updating the jar preserves the database.
5. **Settings merge** retains custom settings and backs up changes. Missing `jq`, failed downloads, or failed merges preserve existing settings.
6. **Height recovery** uses `api.qortal.org` as the primary reference and queries `qortal.link` only if the primary request fails or returns an invalid height. Bootstrapping triggers when the selected reference is **more than 2,500 blocks ahead**, with a fresh confirmation before shutdown. A confirmed height stall at any height can also trigger bootstrap, after two timed rechecks and a final confirmation. Unknown heights and active bootstraps do not trigger database replacement.
7. **Database backup** stops Core, copies and verifies `qortal/db`, then removes it from Core's path. Backup failure aborts recovery. Core must remain running with a responsive height API or active bootstrap evidence for 30 seconds before its recovery copies are deleted. Failed startup restores the original database, including when a partial new database was created. Script-owned recovery copies retained after failure are cleaned on a later confirmed successful start. Custom repository paths require manual recovery.

#### Schedule / triggers
- Cron: `@reboot sleep 399` and `1 1 */3 * *` (every third day of the month at 1:01 AM).
- Cron updates preserve unrelated jobs and environment settings.
- `flock` permits one auto-fix instance at a time. Core starts with the lock descriptor closed so later runs remain possible.

#### Prerequisites
- Linux `/proc`, Bash, `curl`, `flock`, `timeout`, `jq` (installation attempted if missing), and `unzip` or the JDK `jar` tool.
- Qortal Core in `${HOME}/qortal`, with its HTTP API listening on `localhost:12391` by default.
- Enough free disk space for a full database backup. Shutdown failure or insufficient backup space aborts database recovery.

#### Tunables (env-overridable)
- `AUTO_FIX_MAX_BLOCKS_BEHIND=2500`, `AUTO_FIX_API_BASE=http://localhost:12391`.
- `HEIGHT_STALL_WAIT_SECONDS=300`, `HEIGHT_STALL_RECHECKS=2`: two timed rechecks after an unchanged height across runs.
- `CORE_START_WAIT_SECONDS=2100` is the maximum startup verification time, with polling and progress messages; confirmed startup returns early. `CORE_STOP_WAIT_SECONDS=120`, `FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS=30` (sustained startup evidence before backup cleanup).
- `ACTIVE_LOG_MAX_AGE_SECONDS=900`. Full database recovery copies are temporary, rather than retained indefinitely.
- `SMALL_BACKUPS_TO_KEEP=10` keeps 10 recent timestamped settings, script, cron and logging configuration backups per category, plus the protected latest-good settings backup. Unrelated/manual files are preserved.
- `AUTO_FIX_SELF_UPDATE=0` disables script self-updates for a test run; settings and helper refreshes still run.

For remote testing, copy this version to `${HOME}/auto-fix-qortal.sh` and run as the Core user:

```bash
AUTO_FIX_SELF_UPDATE=0 bash "$HOME/auto-fix-qortal.sh" 2>&1 | tee "$HOME/auto-fix-test.log"
```

This performs real maintenance and may bootstrap if the confirmed lag exceeds 2,500 blocks. Isolated local regression checks use `python3 -m unittest discover -s tests -v` and require `jq`, `unzip`, and `flock`; they do not contact the network or operate a live Core.

#### Disabling the schedule
Remove the cron entries: `crontab -e` and delete the `auto-fix-qortal.sh` lines, or run the script manually (`bash ${HOME}/auto-fix-qortal.sh`) without the cron triggers. The `@reboot` entry runs it ~6.5 minutes after every boot.

As of **May 24th 2023** the script has been **updated** to include **a new feature that automatically sets the RAM for the JVM on linux-based machines.** This feature was built so that no matter how much RAM your systme has, the Qortal Core will be **given optimal RAM settings** and will **run correctly in any scenario**. (This is the HOPE, anyway... there are always anomalies...)

The **auto-fix-script also updates itself**, so if you have **installed the script in the past** you **do NOT have to continaully come back and check for new versions, the script does that for you every time it is run.** (If you do not want the script to do this, you can simply remove the cron entry that runs it automatically on a schedule, but it is not recommended to remove this unless you know what you're doing and plan to manage your node yourself.)

The script **will check for a GUI-based machine, then modify the auto-fix script so that it runs in a VISIBLE fashion.** This is to address concerns over potentially not SEEING that the script is RUNNING, and rebooting machines during the process, thus causing issues with the Qortal installation.

This feature will **modify existing auto-fix machines automatically** when the script runs on its schedule, and if all goes well, there should be no manual intervention necessary in any regard. Once this modification DOES go live, the auto-fix script will be VISIBLE when it is run upon system startup, and users can follow what the script is doing with the output it displays in the terminal. This will also make it so that if the script DOES have to 'fix' the Qortal Core, it will do THAT in a visible fashion as well, allowing the user to SEE the bootstrap process with the normal Qortal 'splash screen'.

As time goes on the plan is to also make this script check that the node is within x number of blocks from the chain tip, then if it is not, resolve that scenario as well.

## Many other scripts / tools

There are many other scripts and tools in this repo, most of which are not fully labeled. Explanations of each will be published as time goes on, so that they become more useful to others outside of Crowetic Hardware Development team.










#### This repo is no longer solely about ARM-based systems, and is able to be utilized on multiple systems. 
**This used to be a location for scripts solely related to the raspberry pi** - this is **no longer the case**. 



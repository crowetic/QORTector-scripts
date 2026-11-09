# QORTector-scripts

Linux installation, desktop integration, Core recovery, and VM storage-maintenance
scripts maintained by [crowetic / Crowetic Hardware Development](https://crowetic.com).
The repository supports desktop and headless workflows on x86 and ARM; individual
scripts have different platform requirements. Older Raspberry Pi and Mac helpers
remain available, but the scripts below are the main starting points.

## Choose a script

Run user-level commands from the repository root as the intended desktop/Core
user. Qortal installations and preferences are stored under that user's home.
Installers request `sudo` for system changes; VM maintenance runs as root.

| Task | Script | What it changes |
| --- | --- | --- |
| Install Qortal Core and Hub | [`Qortal-Setup-Linux.sh`](Qortal-Setup-Linux.sh) | Dependencies, `~/qortal`, `~/qortal-hub`, icons, launchers, optional automation |
| Prepare or repair a Linux machine | [`rebuilt-machine.sh`](rebuilt-machine.sh) | Missing packages, Cinnamon desktop when applicable, preserved Qortal installs and additive automation |
| Repair missing Qortal icons | [`create-icon-theme-uni.sh`](create-icon-theme-uni.sh) | User icon theme and standard `hicolor` fallback |
| Apply Cinnamon menu/desktop settings | [`apply-cinnamon-settings.sh`](apply-cinnamon-settings.sh) | Installed menu instances and selected desktop preferences |
| Keep an existing Core updated and recover synchronization | [`auto-fix-qortal.sh`](auto-fix-qortal.sh) | Core jar, settings, start scripts, schedules, and guarded database recovery |
| Start an installed Core | [`start-qortal-core.sh`](start-qortal-core.sh) | Launches `start.sh` from `${QORTAL_DIR:-$HOME/qortal}`, forwarding arguments |
| Maintain a Linux Docker VM's storage | [`vm-data-maintenance-v2/install.sh`](vm-data-maintenance-v2/install.sh) | Guest maintenance utility, root-owned config, and systemd timers |
| Watch Proxmox storage capacity | [`proxmox-vm-capacity-watch.sh`](vm-data-maintenance-v2/proxmox-host/proxmox-vm-capacity-watch.sh) | Reports host capacity and VM allocation; separate host service/timer |

## Recent changes

The latest committed changes concentrate on recovery safeguards, disk-space
management, and desktop compatibility:

| Date | Commit | Change |
| --- | --- | --- |
| 2026-10-26 | `0611ee9` | Reworked universal icon installation for Ubuntu 26: declared theme directories, seven Qortal icons in `hicolor`, validated artwork downloads, ImageMagick 6/7 support, and isolated regression tests. |
| 2026-10-15 | `cd2ee74` | Renamed the new NuQloud VM utility to **VM Data Maintenance v2**; added its installer, config validation, legacy-name migration, failure reporting, and tests. |
| 2026-10-14 | `7086b8b` | Introduced the VM guest maintenance suite and a separate Proxmox capacity watcher. |
| 2026-10-14 | `8e9a308` | Bounded small auto-fix backups by count, including startup/exit cleanup during offline or failed runs. |
| 2026-10-06 | `383f57d` | Hardened Core updates and bootstrap recovery with verified downloads/backups, targeted process shutdown, concurrency locking, height confirmation, rollback, and managed cron entries. |

The rebuild now supports apt, pacman and dnf, preserves configured machines by
default, and provides explicit update, desktop-default, upgrade and dry-run flags.
The earlier Cinnamon/schema and launcher improvements are included in `main`.

## Install Qortal Core and Hub

```bash
bash ./Qortal-Setup-Linux.sh
```

The installer detects Debian/Ubuntu, RHEL, Arch, SUSE, and Alpine package-manager
families. It attempts Java 21 with Java 17 fallbacks and installs tools including
`curl`, `wget`, `unzip`, `jq`, `rsync`, and ImageMagick. Package availability and
Hub compatibility still depend on the distribution and architecture.

Core goes into `~/qortal`; Hub goes into `~/qortal-hub`. The Hub download selects
ARM64 for `aarch64`/`arm64`, otherwise the standard AppImage. The script also
creates menu entries and user launchers. Over SSH or without a GUI, it skips the
Hub test launch but still downloads Hub and creates its desktop assets. When
FUSE2 is unavailable, the current launcher retains `APPIMAGE_EXTRACT_AND_RUN=1`.

An existing responsive, synchronized Core is retained. Otherwise, the installer
moves the existing installation to `~/backups/qortal-<epoch>` before installing
Core again. It restores selected content such as minting/trade backups, lists,
default-location data, API key, and `dataPath`; verify custom settings and data
afterward. For routine maintenance of an existing node, use auto-fix below.

At the end, the installer offers automation and can run it immediately.
**A 20-second prompt timeout currently installs automation**, despite the prompt's
“auto-skip” wording. Answer `n` to decline, or explicitly skip that step:

```bash
QSL_INSTALL_AUTOMATION=0 bash ./Qortal-Setup-Linux.sh
```

The hosted installation entry point is also available:

```bash
bash <(curl -fsSL https://install-linux.qortal.org || wget -qO- https://install-linux.qortal.org)
```

That command executes the hosted script, which may differ from this checkout.

## Prepare or repair a Linux machine

`rebuilt-machine.sh` supports Debian/Ubuntu derivatives with `apt-get`, Arch and
Manjaro with `pacman`, and Fedora with `dnf`. It reads `ID` and `ID_LIKE` from
`/etc/os-release` and maps package names for Python, Java, FUSE2, Cinnamon, cron,
GLib and other tools. Unknown distributions warn and try an available supported
manager; distributions without one of these three managers need manual setup.
Unavailable optional packages are skipped with warnings. Yaru packages are
skipped on Arch/Fedora; icons inherit an installed theme and `hicolor` instead.
Cinnamon uses the regular Arch/Fedora repositories; no COPR or AUR repository is
enabled automatically. Package availability still depends on enabled repositories.

Run as the intended desktop/Core user, without `sudo`. Start with a preview:

```bash
bash ./rebuilt-machine.sh --help
bash ./rebuilt-machine.sh --dry-run
bash ./rebuilt-machine.sh
```

The default run fills missing packages, applications, desktop assets and
schedules. Fresh desktop installs also receive the Qortal wallpaper, icon theme,
and **Qortal OS** menu label/logo. Configured desktops retain their preferences.
The script **does not upgrade the system, replace existing Core/Hub, or reboot**.
Existing Core directories are retained even
when stopped, syncing, inaccessible, or incomplete; incomplete installations warn
for manual repair. User settings, helper scripts, launchers, disabled autostarts,
matching Pictures files and existing theme directories are preserved. Desktop
mode still installs Cinnamon and optional desktop apps on a fresh machine.

| Flag | Equivalent environment variable | Default / behavior |
| --- | --- | --- |
| `--dry-run` | `REBUILT_MACHINE_DRY_RUN=1` | Preview only; no sudo, downloads, child scripts, files or state changes. |
| `--update-core` | `REBUILT_MACHINE_UPDATE_CORE=1` | Download and validate the release; replace only a changed jar in an existing **stopped** Core. Preserve settings, database, keys, lists, data and custom scripts; back up the old jar. |
| `--update-hub` | `REBUILT_MACHINE_UPDATE_HUB=1` | Check the release tag and recorded binary SHA-256; skip the binary download when current. Otherwise validate/download, compare, and back up before replacement. Untracked AppImages need one download for comparison. |
| `--upgrade-packages` | `REBUILT_MACHINE_UPGRADE=1` | Opt in to `apt-get upgrade`, `pacman -Syu`, or `dnf upgrade`. |
| `--apply-defaults` | `REBUILT_MACHINE_APPLY_DEFAULTS=1` | Export dconf before changing desktop preferences, session selection, themes, menu and application defaults. Defer session settings to Cinnamon login when necessary. |
| `--force-artwork` | `REBUILT_MACHINE_FORCE_ARTWORK=1` | Back up and replace repository artwork, icon files and themes. Configured desktops retain preference selections unless `--apply-defaults` is also used. |
| — | `REBUILT_MACHINE_HEADLESS=auto` | Detect sessions/installed session files; `1` forces server mode and `0` forces desktop mode. |
| — | `REBUILT_MACHINE_REBOOT=1` | Opt in to reboot after success and a 30-second cancellation delay; default is `0`. |
| — | `REBUILT_MACHINE_PKG_RETRIES=3` | Total install attempts per missing package; accepts a positive integer. Wait 2 seconds, then 4 seconds between the default three attempts. |

Package installation retries use the existing package mappings and preserve
installed packages. APT receives command-local `APT::Get::Retry` and
`Acquire::Retries` defaults matching the attempt count, preserving either value
when already configured; `Acquire::Retries` controls APT's download retries.
Pacman transactions are retried in the script (there is no `--retry` flag), and
DNF receives `--setopt=retries=<count>`. This option is deprecated in DNF5;
the script's loop provides transaction retries on both DNF versions.
Package managers may also retry downloads
internally, so an attempt can take longer than a single connection timeout.
Their existing timeout settings are retained; no system configuration is changed.

After the last failure, noncritical packages such as ImageMagick warn with the
package name and a manual retry command, and setup continues with later packages.
If ImageMagick is missing, icon generation is skipped with a manual retry hint.
Required tools (`git`, `curl`, `jq`, `unzip`, `ca-certificates`, `rsync`, `python3`,
and `util-linux`) still stop setup after exhausting retries. Alternative-package
checks try the next candidate after an install failure; Java and desktop-mode
Cinnamon remain required. `--dry-run` previews each install once without querying
package state or APT configuration, invoking sudo, or sleeping.

Boolean variables accept only `0` or `1`. To get the repository's desktop look on
a fresh install, run `bash ./rebuilt-machine.sh`. To reapply branding and all
repository preferences on an existing desktop, use `--apply-defaults`. To update an
existing Core, first stop it using `bash ~/qortal/stop.sh`; the rebuild refuses a
jar update while this installation's JVM is running. Start it afterward with
`bash ~/start-qortal-core.sh`. Ordinary reruns never stop or restart Core.
The rebuild shares the maintenance lock with auto-fix.

Installed package alternatives are kept rather than replaced by a preferred
alternative. Fresh rebuilds install only the Java 17 runtime (`openjdk-17-jre`,
`jre17-openjdk`, or `java-17-openjdk`, with the Debian headless variant as a
fallback). An already installed Java 17 or 21 runtime is kept without adding
another version. Existing redundant Java packages are not automatically removed.
Individual apt installs use `--no-upgrade`; installing a missing
package may still require dependency changes. Arch installs use the existing
sync database, never `pacman -Sy`. If it is stale, explicitly opt in to a full
upgrade with `--upgrade-packages`; partial upgrades are unsupported by Arch.
See [Arch system maintenance](https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported).
Cron is enabled on Arch/Fedora only when its package was previously absent;
existing service enablement choices are retained.

Server mode skips Cinnamon and uses boot-time cron entries. It still installs a
missing Hub AppImage on x86_64/ARM64; unsupported Hub architectures warn and keep
Core available. Desktop mode creates missing Core/Hub menu entries and launchers,
retains the AppImage FUSE extraction fallback, and tests only a newly installed
Hub when a GUI is available. The rebuild uses its own preserve-existing install
path; the standalone `Qortal-Setup-Linux.sh` retains its separate behavior above.

After desktop setup, choose **Cinnamon** in the login-screen session selector.
The rebuild does not switch the running desktop. Fresh-install detection happens
before setup writes configuration: it requires no setup state file, no nonempty
`${XDG_CONFIG_HOME:-$HOME/.config}/dconf/user`, no `.dmrc`, and no modern/legacy
Cinnamon menu configuration or user-installed menu applet. Any of these existing
signals preserves preferences unless `--apply-defaults` is requested.

Branding is applied immediately when a display and desktop D-Bus address are
available. Over SSH, or after a failed preference write, it creates
`${XDG_CONFIG_HOME:-$HOME/.config}/autostart/apply-cinnamon-settings.desktop`.
This Cinnamon-only job backs up dconf at login and removes itself only after
successful branding. Preference writes are read back to catch silent dconf commit
failures. A fresh install applies branding only; full application/session/theme
defaults remain opt-in. Server mode (`REBUILT_MACHINE_HEADLESS=1`) skips desktop
setup entirely; use `REBUILT_MACHINE_HEADLESS=0` for desktop provisioning over SSH
when installed session files cannot be detected. An **Apply Cinnamon Settings**
launcher remains available for deliberate customization later.

On machines without custom automation, Core starts at login, with maintenance
seven minutes later; server mode starts Core at boot and maintenance after 399
seconds. Both modes add `1 1 */3 * *` (01:01 on every third day of the month) when
no periodic auto-fix job exists. Existing custom schedules for these scripts take
precedence. Cron entries and existing autostarts are never removed or rewritten,
including when switching modes. Review existing schedules manually if changing
between server and desktop operation.

Helpers beside the rebuild take precedence over network downloads; Gitea is the
fallback source. Existing home helpers are preserved by default; fresh branding
refreshes its branding helper/settings with backups, and explicit `--apply-defaults`
also refreshes its desktop preference/icon helpers so first-login
configuration uses the current safety guards. The rebuild executes its
current icon helper with preservation switches so an older installed copy cannot
reset preferences. Scripts, JSON and archives are validated before use. Artwork
is merged without replacing matching files, then marked with
`~/Pictures/.qortector-artwork-installed` to skip future bundle downloads. Remove
that marker to fill missing artwork again, or use `--force-artwork` to replace it.
`~/.qortector-setup-state.json` records the last successful run, distro, package
manager and backup directory for reference; it does not override file checks.

Before replacing managed content, the rebuild saves old files under
`~/backups/rebuilt-machine-<timestamp>.<suffix>/` and prints the directory. Applying
defaults saves a full `desktop.dconf` export and the previous `.dmrc`; menu and
application helpers save their own backups. Force-artwork saves Pictures and
replaced themes/icons. Required failures stop setup and cancel reboot; optional
failures are listed at completion. Completed package changes remain in place if
a later step fails; this is not a whole-system rollback.

To roll out these changes, pull the updated repository, inspect `--dry-run`, then
run the script as that machine's intended user with the chosen flags. No service
restart is needed merely to update the repository. Verify Core status with
`bash ~/check-qortal-status.sh`, launch Hub manually, and inspect `crontab -l`.
Restore a replaced jar from `<backup>/qortal/qortal.jar` **with Core stopped**, or
restore the backed-up Hub binary at its original path. Restore preference files
to their original locations and use `dconf load / < "$backup/desktop.dconf"` (set `backup` to the printed path) to
restore the exported desktop state. Restore scheduling with
`crontab "$backup/crontab"` if needed. Keep the printed backup path until verified.

## Repair desktop icons and Cinnamon settings

For missing Qortal launcher/menu icons, run the icon helper as your desktop user,
without `sudo`:

```bash
bash ./create-icon-theme-uni.sh
```

It installs `qortal`, `qortal-hub`, `qortal-ui`, and `qortal-menu-button` through
`qortal-menu-button-4` in both `~/.icons/Yaru-blue-qortal` and the user `hicolor`
fallback. It repairs the theme index, inherits installed system artwork, merges
missing source artwork into `~/Pictures` while preserving unrelated files, and
supports ImageMagick 7 (`magick`) and older ImageMagick (`convert`). Dependencies
are `curl`, `unzip`, `rsync`, and ImageMagick. It selects the theme in supported
Cinnamon, GNOME/Unity, XFCE, and KDE sessions; fallback icons remain available
when theme selection fails or no desktop session is detected.

For an existing Cinnamon desktop, follow icon repair with:

```bash
bash ./apply-cinnamon-settings.sh --menu-only
```

Keep `cinnamon-settings.json` beside the helper. It merges preferences with the
installed Cinnamon menu schema for **each enabled menu instance** under
`${XDG_CONFIG_HOME:-$HOME/.config}/cinnamon/spices/menu@cinnamon.org/`. It preserves
new schema entries and existing values where no preference overrides them,
uses a **40-pixel** menu icon, and can migrate legacy `~/.cinnamon/configs/` values.
It does not assume the menu instance is `0` or re-enable a disabled menu applet.
Previous menu settings are backed up under `~/backups/cinnamon-menu/` when used
outside a rebuild.

Running `bash ./apply-cinnamon-settings.sh` without an option also installs icons
and applies desktop theme/wallpaper preferences. `--settings-only` applies those
preferences and menu settings without rerunning icon installation;
`--branding-only` selects the wallpaper, `Yaru-blue-qortal` icon theme, and menu
branding without changing application or window themes. Both wallpaper URI keys
are set where Cinnamon provides `picture-uri-dark`; versions without that key
use `picture-uri` for both appearances. The menu uses the installed
`qortal-menu-button-2` icon and **Qortal OS** text in the menu applet's JSON settings,
not a window-manager button-title key. Desktop modes require a display and D-Bus
session. `--first-login [--branding-only|--settings-only]` is used by the rebuild's
one-time autostart. The companion
[`configure-terminal-and-more.sh`](configure-terminal-and-more.sh) handles
application and terminal preferences during the rebuild.

These repairs do not reinstall Core/Hub. Log out and back in if the panel still
shows cached icons; a full machine reboot is not required.

## Maintain and recover Qortal Core

`auto-fix-qortal.sh` maintains Core at **`$HOME/qortal`** with its HTTP API at
`http://localhost:12391` by default. Run it as the Core user. It requires Linux
`/proc`, Bash, `curl`, `flock`, `timeout`, `jq` (installation attempted if missing),
and `unzip` or the JDK `jar` tool. Database recovery needs enough free space for
a complete verified database copy.

To install the checkout's version and perform real maintenance:

```bash
install -m 0755 ./auto-fix-qortal.sh "$HOME/auto-fix-qortal.sh"
bash "$HOME/auto-fix-qortal.sh"
```

This is an active maintenance command: it can update files, configure schedules,
restart Core, or bootstrap its database. There is **no dry-run mode**. To retain
the installed script version during a diagnostic run:

```bash
AUTO_FIX_SELF_UPDATE=0 bash "$HOME/auto-fix-qortal.sh" 2>&1 | tee "$HOME/auto-fix-test.log"
```

Disabling self-update leaves settings/helper refreshes and other maintenance
enabled. Normal runs update the script itself after checking Bash syntax,
required functions, and revision so an older script cannot replace this version.

### Update and recovery behavior

1. Acquire a single-instance lock, prune excess small backups, check connectivity,
   refresh helpers, and select a syntax-checked JVM start script for RAM/platform.
2. Resolve Core releases using GitHub release metadata, the latest-release
   redirect, then a list excluding drafts/prereleases. Compare version components;
   preserve an existing jar when release metadata is unknown. A retained special
   case selects build `qortal-6.1.2-4ee9441` from the configured override URL when
   the latest release tag is `6.1.2`.
3. Validate a changed jar before replacement, stop this installation's JVM,
   retain `qortal.jar.previous`, and preserve the database during jar updates.
4. Merge settings while retaining custom settings and backing up changes. Missing
   `jq`, bad downloads, failed merges, and unchanged settings preserve the file.
5. Use `api.qortal.org` for reference height, consulting `qortal.link` only if the
   primary request fails or is invalid. A lag **greater than 2,500 blocks** can
   trigger bootstrap after a fresh confirmation. A height unchanged across runs
   requires two timed rechecks and a final stall confirmation. Unknown heights
   and active bootstraps do not justify replacing the database.
6. Before bootstrap, stop Core, copy and verify `qortal/db`, and move the original
   aside. Failed backup/shutdown aborts recovery. Failed startup restores the
   original database, including when a partial new database was created.
7. Remove script-owned recovery copies only after Core stays running with a
   responsive height API or active-bootstrap evidence for 30 seconds. Retained
   copies are reconsidered on a later confirmed successful start. Custom
   repository paths require manual recovery.

`qortal.jar.previous` and `original.sh` are single overwritten rollback files.
Small timestamped settings/script/cron/logging backups retain the newest ten per
managed group, ordered by filename timestamp, plus the protected latest-good
settings target. They have no age expiry. Startup and exit cleanup run under the
lock, including offline/failed runs; manual files and symlinks are protected.
Full database recovery copies follow the startup-confirmation rule above rather
than this count limit. Stop Core before manually restoring any jar or database.

### Configuration and schedules

| Environment variable | Default | Purpose |
| --- | --- | --- |
| `AUTO_FIX_API_BASE` | `http://localhost:12391` | Local Core API |
| `AUTO_FIX_MAX_BLOCKS_BEHIND` | `2500` | Lag must exceed this value to justify recovery |
| `HEIGHT_STALL_WAIT_SECONDS` | `300` | Delay between stall rechecks |
| `HEIGHT_STALL_RECHECKS` | `2` | Number of timed stall rechecks |
| `CORE_START_WAIT_SECONDS` | `2100` | Maximum startup verification time; confirmed startup returns early |
| `CORE_STOP_WAIT_SECONDS` | `120` | Shutdown wait limit |
| `FORCE_BOOTSTRAP_RESTART_WAIT_SECONDS` | `30` | Sustained startup evidence before recovery-copy cleanup |
| `ACTIVE_LOG_MAX_AGE_SECONDS` | `900` | Recency window for bootstrap log evidence |
| `SMALL_BACKUPS_TO_KEEP` | `10` | Count limit per managed small-backup group |
| `AUTO_FIX_SELF_UPDATE` | `1` | Set `0` to disable script self-update only |

The managed schedule is `1 1 */3 * *` (01:01 on every third day of the month).
Headless mode also uses `@reboot sleep 399` and a Core boot launcher; desktop
setups use login autostart where applicable. Cron changes preserve unrelated jobs
and environment settings. Core starts without inheriting the maintenance lock.

Inspect schedules with `crontab -l` and `~/.config/autostart/`. To stop automatic
maintenance, remove the auto-fix cron entries with `crontab -e` and disable its
autostart entry if present. Running auto-fix again can recreate its schedules.
Headless cron output goes to `~/auto-fix-startup.log` and
`~/log-auto-fix-cron.log`.

## Maintain Linux VM storage with v2

[`vm-data-maintenance-v2/`](vm-data-maintenance-v2/) is a separate guest/host
storage utility. It is independent of Core maintenance and NuQloud's per-instance
recreate/deploy maintenance. It does not run Nextcloud `occ` commands or modify
application/database/Redis configuration.

| Location / mode | Schedule | Default action |
| --- | --- | --- |
| Guest: `trim` | Every four hours, up to five minutes randomized delay | `fstrim` on configured mountpoints; `/` by default |
| Guest: `daily` | 02:15 daily, up to ten minutes delay | Filesystem/Docker reports; vacuum archived journals to `10d` / `200M` |
| Guest: `weekly` | Sunday 03:20, up to ten minutes delay | Reports and APT `autoclean`; tmpfiles cleanup and Docker build-cache pruning are opt-in |
| Guest: `report` | Manual | Read-only filesystem and Docker usage reports |
| Proxmox host watcher | Five minutes after boot, then 15 minutes after each run | Capacity status; warning at 75%, critical at 85%; log messages only |

The guest installer requires a running systemd manager. Guest commands use Bash,
Linux utilities including `flock`/`mountpoint`/`fstrim`, and a trusted root-owned
config. Docker reporting is skipped when Docker is unavailable. APT cleanup is
skipped when `apt-get` is unavailable. Guest capacity warnings default to 80%/90%.

Install **inside the guest** without enabling new timers for the first check:

```bash
sudo bash ./vm-data-maintenance-v2/install.sh --no-enable
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode report
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode trim --dry-run
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode daily --dry-run
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode weekly --dry-run
```

Review `/etc/vm-data-maintenance-v2.conf`, including `TRIM_MOUNTS` and
`REPORT_PATHS` for separate Docker/data filesystems. Config files and their
parent directories must be root-owned, not writable by group/others, and free of
symlinks. The config is sourced as Bash; this requirement also applies to dry
runs. New/migrated configs are installed with mode `0600`.

The installer preserves an existing v2 config and verifies all four modes with
dry runs before retiring the older **`nuqloud-vm-maintenance`** guest installation.
It migrates that config if no v2 config exists, or backs it up separately if both
exist. `--no-enable` still installs files and can retire that legacy installation;
it does not disable already-enabled v2 timers. The distinct root-level v1
`vm-data-maintenance` installation is **not** migrated or disabled automatically.
Check its timer before enabling overlapping schedules.

Dry runs preview cleanup commands and execute reports, but do not prove discard
support. After reviewing configuration, perform an actual TRIM and inspect it:

```bash
sudo systemctl start vm-data-maintenance-v2@trim.service
sudo journalctl -u vm-data-maintenance-v2@trim.service --since today --no-pager
sudo systemctl enable --now \
  vm-data-maintenance-v2-trim.timer \
  vm-data-maintenance-v2-daily.timer \
  vm-data-maintenance-v2-weekly.timer
systemctl list-timers --all 'vm-data-maintenance-v2*'
```

Only after confirming the new TRIM schedule works, disable duplicate stock
`fstrim.timer` scheduling if present. Keep normal `logrotate.timer` and
`systemd-tmpfiles-clean.timer` policies enabled. To revert v2 scheduling:

```bash
sudo systemctl disable --now \
  vm-data-maintenance-v2-trim.timer \
  vm-data-maintenance-v2-daily.timer \
  vm-data-maintenance-v2-weekly.timer
sudo systemctl enable --now fstrim.timer
```

V2 does not prune Docker images, containers, or volumes. Optional build-cache
pruning is separate and disabled by default, as is tmpfiles cleanup. It serializes
jobs and reports failed maintenance commands through the service exit status.
TRIM bytes are **discard requests, not measured host space reclaimed**.

The Proxmox watcher must be installed on the **hypervisor**, separately from the
guest. Its service defaults to `/var/lib/vz` and VM `108`; change those environment
values for your host. It reports allocated VM image space and capacity thresholds
through output/journald; connect external monitoring to receive notifications.
It performs no reclamation. For host installation, complete configuration,
migration details, and verification, see the
[VM Data Maintenance v2 README](vm-data-maintenance-v2/README.md).

## Older utilities

The root-level [`setup-vm-data-maintenance.sh`](setup-vm-data-maintenance.sh),
[`vm-data-maintenance.sh`](vm-data-maintenance.sh), and
[`vm-data-maintenance.conf`](vm-data-maintenance.conf) are the **v1** utility.
It installs `/usr/local/sbin/vm-data-maintenance` and a daily
`vm-data-maintenance.timer`. Its policy includes broader log/temp/package cleanup,
explicit extra deletion targets, and optional Docker system pruning. Its config
and dry-run handling differ from v2; do not reuse its commands or config for v2.

Other retained tools include Raspberry Pi/Titan setup scripts, RAM-specific Core
start scripts, earlier UI installers, scheduled restart/peer helpers, WireGuard
helpers, and HSQLDB tools. Review their assumptions before use; they are not all
part of the current installer or maintenance path. In particular,
`auto-fix-qortal-oldVersion.sh` and the older icon helpers are historical
alternatives to the versions documented above.

## Local verification

Run the isolated regression suite from the repository root:

```bash
python3 -m unittest discover -s tests -v
```

Tests use temporary homes, fixtures, and mocked network/system/desktop commands;
they do not install software, maintain a live Core, or run real VM cleanup.
Coverage includes auto-fix recovery/backups, icon installation, rebuild/Cinnamon
behavior, and v2 guest configuration/installer migration. Install `bash`, `jq`,
`unzip`, `rsync`, and `flock` for the relevant suites. Some optional checks require
JDK `jar`, `desktop-file-validate`, or Python GIO bindings and may be skipped.
These checks do not replace validation on the target desktop or virtual storage.

For an individual suite, select its file, for example:

```bash
python3 -m unittest discover -s tests -p 'test_rebuilt_machine.py' -v
python3 -m unittest discover -s tests -p 'test_qortal_icons.py' -v
python3 -m unittest discover -s tests -p 'test_vm_data_maintenance_v2.py' -v
```

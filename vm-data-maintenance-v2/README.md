# VM Data Maintenance v2

This utility is **independent** of NuQloud's existing per-instance maintenance performed during instance recreate/deploy. It does **not** execute `occ`, inspect tenant/customer data, modify Redis/database configuration, manage Nextcloud file retention, or invoke instance management scripts. It is for maintenance of the Linux Docker VM and, optionally, capacity monitoring on the Proxmox hypervisor.

## Operational model

| Where | Schedule | Job | Default changes |
| --- | --- | --- | --- |
| **Inside VM** | Every 4 hours | `trim` | `fstrim -v /` |
| **Inside VM** | Daily | `daily` | Vacuum **archived** systemd journals to configured age/size, and report filesystem/Docker usage |
| **Inside VM** | Weekly | `weekly` | APT `autoclean` (no autoremove), report usage; optional systemd-tmpfiles and Docker **build cache** cleanup disabled by default |
| **On Proxmox host** | Every 15 minutes | capacity watcher | Log warnings for `/var/lib/vz` at 75% and critical at 85%; report VM 108 QCOW2 allocated footprint |

The watcher logs warnings with `logger`/journald **only**. It does **not** send email, webhooks, or push notifications until you connect an alerting system. It must run on the **hypervisor**, as guest storage metrics cannot see allocated QCOW2 space.

`fstrim` reports bytes **submitted for discard**, not host storage freed. Measure host usage with `df -h /var/lib/vz` and `du -sh /var/lib/vz/images/108` to validate reclamation.

## Install within Docker guest (for example VM 108)

Copy `vm-data-maintenance-v2/` to the VM. For the first test, install without enabling the new timers:

```bash
cd vm-data-maintenance-v2
sudo bash ./install.sh --no-enable
```

The installer creates `/usr/local/sbin/vm-data-maintenance-v2.sh`, `/etc/vm-data-maintenance-v2.conf` and the matching systemd units. It preserves an existing v2 config. If only `/etc/nuqloud-vm-maintenance.conf` exists, it migrates that config; if both configs exist, it preserves the old one as a root-only `vm-data-maintenance-v2.conf.pre-migration.*` backup. New/migrated configs are root-owned mode `0600`.

Before removing the legacy installation, the installer verifies all four modes with `--dry-run`. Only after those checks pass does it disable the three old `nuqloud-vm-maintenance-*.timer` units, stop the old guest service instances and remove the old script, config and units. A failed verification leaves the legacy files and schedules in place. The Proxmox watcher and stock `fstrim.timer` are unaffected. Reinstalling without `--no-enable` enables the new timers; `--no-enable` does not disable previously enabled v2 timers.

Review `/etc/vm-data-maintenance-v2.conf`, then test inside the VM:

```bash
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode report
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode trim --dry-run
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode daily --dry-run
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode weekly --dry-run
sudo systemctl start vm-data-maintenance-v2@trim.service
sudo journalctl -u vm-data-maintenance-v2@trim.service --since today --no-pager
```

The installer dry runs preview cleanup commands and run read-only reports; they do not prove that the virtual storage supports discard. Confirm the actual TRIM service succeeds before enabling the schedules:

```bash
sudo systemctl enable --now \
  vm-data-maintenance-v2-trim.timer \
  vm-data-maintenance-v2-daily.timer \
  vm-data-maintenance-v2-weekly.timer

systemctl list-timers 'vm-data-maintenance-v2*'
```

**Only after you confirm the new trim timer is scheduled and executes**, disable the stock weekly `fstrim.timer` to avoid duplicate TRIM runs:

```bash
sudo systemctl disable --now fstrim.timer
```

Do **not** disable the system's regular `logrotate.timer` or `systemd-tmpfiles-clean.timer`: this utility does not replace those policies.

Run an immediate test when you want:

```bash
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode trim
sudo /usr/local/sbin/vm-data-maintenance-v2.sh --mode report
journalctl -u 'vm-data-maintenance-v2@trim.service' --since '1 day ago' --no-pager
```

Note: `systemctl list-timers` shows timer *unit* names; to see a specific timer's previous execution inspect `systemctl list-timers --all vm-data-maintenance-v2-trim.timer` and `journalctl -u 'vm-data-maintenance-v2@trim.service'`.

## Guest configuration

The config must exist, be root-owned, and have no group/other write permission. Its parent directories must also be root-owned and non-writable by other users; symlinks are rejected. Use `/etc/vm-data-maintenance-v2.conf`, including for dry runs, rather than a config in `/tmp` or a user-writable directory.

- `TRIM_MOUNTS=( / )` selects actual mountpoints for discard. Every configured mountpoint is checked before any TRIM runs.
- `REPORT_PATHS=( / )` selects filesystem usage report paths. Add a separate Docker/data path such as `/srv` if it resides on another filesystem; Docker metrics omit some bind-mounted data.
- Journal retention accepts positive integer durations with `s`, `m`, `h`, `d` or `w`, and positive sizes in bytes or with `K`, `M`, `G` or `T`. Defaults are `10d` and `200M`.
- Docker build-cache pruning remains disabled by default. Its minimum age accepts a positive integer with `s`, `m` or `h`; default `336h` is 14 days. Tmpfiles cleanup also remains opt-in.
- Guest warning/critical percentages must be integers from 1 to 100 with warning below critical. Warnings appear in the journal; they do not send notifications.

Missing or invalid config prevents maintenance. Failed report or cleanup commands give the service a failed status while the remaining independent checks still run. Concurrent guest modes skip when the private `/run/vm-data-maintenance-v2/maintenance.lock` is held.

## Install watcher on `orus-2` (Proxmox host, separate from the guest)

Copy only `proxmox-host/` to `orus-2`:

```bash
sudo install -m 0755 proxmox-host/proxmox-vm-capacity-watch.sh /usr/local/sbin/proxmox-vm-capacity-watch.sh
sudo install -m 0644 proxmox-host/*.service proxmox-host/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo /usr/local/sbin/proxmox-vm-capacity-watch.sh
sudo systemctl enable --now proxmox-vm-capacity-watch.timer
sudo systemctl list-timers proxmox-vm-capacity-watch.timer
```

The service file is explicitly configured for `MOUNT=/var/lib/vz` and `VMID=108`. Change its environment values if deploying on another host. Capacity warning and critical exit codes will show failed oneshot runs, which is deliberate, but **journald warnings alone are not notifications**; attach an alert channel to your monitoring stack.

## Scope and safety

- **No NuQloud instance lifecycle hooks.** The recreate script remains the only component responsible for its per-instance cleanup.
- **No `occ` operations**, Nextcloud trash/version expiration, previews, direct customer file inspection, SQL queries, or automatic changes to Redis persistence.
- **No** `docker system prune`, `docker image prune`, `docker volume prune`, or deletion of stopped containers. Docker build-cache pruning is a **separate opt-in** setting and can still cost build performance; keep it disabled on active dev hosts unless measured.
- `systemd-tmpfiles --clean` is opt-in; unlike deleting files by age with `find`, it follows configured systemd tmpfiles cleanup policies.
- No `apt autoremove`, forced logrotate, `eval`, or broad `/var/log` deletion.
- The script expects a **trusted, root-owned config file**, since it is sourced as shell. Do not store it in writable user paths.
- `flock` serializes guest jobs to avoid overlapping runs.
- TRIM does **not** guarantee a fixed maximum allocation or compensate for extremely high write churn. Ensure hypervisor alerts and adequate headroom.
- Neither VM nor host script is an application backup, fsck, or integrity check; verify database/app health separately after a storage exhaustion incident.

## Diagnosing large Redis write counters

In your prior diagnostic sample, the WINNR Redis container had about 3.3 TB of cumulative writes; RDB snapshot churn is a strong suspect, but not verified to be the sole source. Any Redis persistence tuning belongs in the **instance's own configuration/recreate workflow**, so it survives later recreation. This host utility intentionally does not attempt it.

## Verification / rollback

Check effective schedules and logs:

```bash
systemctl list-timers --all 'vm-data-maintenance-v2*'
journalctl -u 'vm-data-maintenance-v2@trim.service' --since today --no-pager
```

To revert the guest scheduling:

```bash
sudo systemctl disable --now vm-data-maintenance-v2-trim.timer vm-data-maintenance-v2-daily.timer vm-data-maintenance-v2-weekly.timer
sudo systemctl enable --now fstrim.timer
```

The instance maintenance/recreate mechanism is independent and unaffected.

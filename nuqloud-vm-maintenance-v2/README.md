# NuQloud VM Data Maintenance (VM/host layer, v2)

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

Review the code and config before installation; copy this folder to the VM and run inside it:

```bash
sudo install -m 0755 nuqloud-vm-maintenance.sh /usr/local/sbin/nuqloud-vm-maintenance.sh
sudo install -o root -g root -m 0644 nuqloud-vm-maintenance.conf.example /etc/nuqloud-vm-maintenance.conf
sudo install -m 0644 systemd/* /etc/systemd/system/

sudo /usr/local/sbin/nuqloud-vm-maintenance.sh --mode trim --dry-run
sudo /usr/local/sbin/nuqloud-vm-maintenance.sh --mode daily --dry-run
sudo /usr/local/sbin/nuqloud-vm-maintenance.sh --mode weekly --dry-run

sudo systemctl daemon-reload
sudo systemctl enable --now \
  nuqloud-vm-maintenance-trim.timer \
  nuqloud-vm-maintenance-daily.timer \
  nuqloud-vm-maintenance-weekly.timer

systemctl list-timers 'nuqloud-vm-maintenance*'
```

**Only after you confirm the new trim timer is scheduled and executes**, disable the stock weekly `fstrim.timer` to avoid duplicate TRIM runs:

```bash
sudo systemctl disable --now fstrim.timer
```

Do **not** disable the system's regular `logrotate.timer` or `systemd-tmpfiles-clean.timer`: this utility does not replace those policies.

Run an immediate test when you want:

```bash
sudo /usr/local/sbin/nuqloud-vm-maintenance.sh --mode trim
sudo /usr/local/sbin/nuqloud-vm-maintenance.sh --mode report
journalctl -u 'nuqloud-vm-maintenance@trim.service' --since '1 day ago' --no-pager
```

Note: `systemctl list-timers` shows timer *unit* names; to see a specific timer's previous execution inspect `systemctl list-timers --all nuqloud-vm-maintenance-trim.timer` and `journalctl -u 'nuqloud-vm-maintenance@trim.service'`.

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
systemctl list-timers --all 'nuqloud-vm-maintenance*'
journalctl -u 'nuqloud-vm-maintenance@trim.service' --since today --no-pager
```

To revert the guest scheduling:

```bash
sudo systemctl disable --now nuqloud-vm-maintenance-trim.timer nuqloud-vm-maintenance-daily.timer nuqloud-vm-maintenance-weekly.timer
sudo systemctl enable --now fstrim.timer
```

The instance maintenance/recreate mechanism is independent and unaffected.

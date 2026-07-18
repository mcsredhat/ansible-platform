# Role: restic_backup

Closes the data tier (00-architecture §3.4): nightly **restic** backups of the
WordPress **database dump** + the **shared uploads tree**, with retention, a vaulted
repository key, and a Prometheus success metric. Pairs with `dr.yml` for restore.

## What it does
- Installs **restic** + rsync.
- Writes the repo password to `/etc/restic/repo.pass` (0600, vaulted, `no_log`).
- **Idempotently initialises** the repo (probes `snapshots`, inits only if absent).
- Deploys `/usr/local/bin/restic-backup.sh`, which: dumps the DB (`mysqldump
  --single-transaction`, root via unix socket), `restic backup`s the dump + uploads,
  applies `forget --prune` retention, and writes `restic_backup.prom` (success,
  duration, timestamp) for the node_exporter textfile collector.
- Schedules it via a **systemd timer** (nightly 02:30 + jitter, `Persistent=true`).

## 3-2-1 — read this
The default `restic_repository` is a **local path** so you can validate mechanics
immediately. That is **not** off-host. For real 3-2-1, override it to remote storage:
```yaml
restic_repository: "sftp:backup@192.168.1.5:/srv/restic"   # control node / NAS
# or  s3:http://minio.lab:9000/restic
```
(SFTP needs the deploy key authorised on the backup host for the `backup` user.)

## Monitoring
`restic_backup.prom` is written to `{{ restic_textfile_dir }}`. Once the Phase 5
node_exporter textfile collector is enabled on data1, `restic_backup_success` and the
age of `restic_backup_timestamp_seconds` become alertable (e.g. "no successful backup
in 26h").

## Verify (on data1)
```bash
systemctl list-timers restic-backup.timer
/usr/local/bin/restic-backup.sh ; echo "exit=$?"      # run once by hand
restic -r /srv/restic-repo snapshots
cat /var/lib/node_exporter/textfile_collector/restic_backup.prom
```

## Restore
See `dr.yml` at the repo root — non-destructive restore to staging by default,
explicit `target=live` to re-import.

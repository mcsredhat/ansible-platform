# Role: restic_backup

Closes the data tier (00-architecture §3.4): nightly **restic** backups into **one
repository** under two tags, with per-tag retention, a vaulted repository key, a
hardened systemd unit and per-tag Prometheus metrics. Pairs with `dr.yml` for restore.

| Tag | Contents | Retention |
|---|---|---|
| `platform` | WordPress DB dump (`mysqldump`, root via unix socket) + `/srv/wordpress/uploads` | `restic_retention` (7d / 4w / 6m) |
| `etc` | `/etc` | `restic_etc_retention` (7d / 4w) |

## What it does
- Installs **restic** + rsync.
- Writes the repo password to `/etc/restic/repo.pass` (0600, vaulted, `no_log`).
- Writes `/etc/restic/env` (0600): `RESTIC_REPOSITORY` and `RESTIC_PASSWORD_FILE`
  only, loaded by the unit through `EnvironmentFile=`. No secret lives in it.
- **Idempotently initialises** the repo: probes `restic cat config` (also in
  `--check`, it is read-only) and runs `init` only if that fails. `restic init`
  refuses an existing repo, so a wrong probe can't clobber data.
- Deploys `/usr/local/bin/restic-backup.sh`, which runs:
  1. `platform`: dump to `*.sql.gz.tmp`, `mv` into place, `restic backup`, `forget --tag platform`.
  2. `etc`: `restic backup /etc`, `forget --tag etc`. Runs **even if the platform step failed**.
  3. One `restic prune` for both tags (prune takes an exclusive repo lock).
  4. Writes `restic_backup.prom` (0644) for the node_exporter textfile collector.
- Schedules it via a **systemd timer** (nightly 02:30 + jitter, `Persistent=true`).

## Variables
| Variable | Default | Purpose |
|---|---|---|
| `restic_repository` | `/srv/restic-repo` | Repo path or URL (`dr.yml` reads it) |
| `restic_password_file` | `/etc/restic/repo.pass` | Password file (`dr.yml` reads it) |
| `restic_env_file` | `/etc/restic/env` | Unit `EnvironmentFile=` |
| `restic_repo_is_local` | derived: repo starts with `/` | Picks the network directives below |
| `restic_db_name` / `restic_db_dump_dir` | `wordpress` / `/var/backups/wordpress` | Dump target (`dr.yml` reads both) |
| `restic_paths` | dump dir + uploads | Tag `platform` |
| `restic_etc_paths` | `[/etc]` | Tag `etc` |
| `restic_retention` / `restic_etc_retention` | see table above | `forget` policy per tag |
| `restic_oncalendar` | `*-*-* 02:30:00` | Timer schedule |
| `restic_textfile_dir` | `/var/lib/node_exporter/textfile_collector` | Metric drop dir |

## Hardening
The unit runs as root (unix_socket auth needs uid 0, and `/etc/shadow` is mode 0000),
so it is locked down with sandboxing instead. Each exception exists because
something breaks without it:

| Directive | Exception | Breaks without it |
|---|---|---|
| `ProtectSystem=strict` | `ReadWritePaths=` dump dir, textfile dir, local repo | dump (EROFS), metric write (silent failure), restic packs/locks |
| `PrivateTmp=true` | — | restic writes temp packs to `/tmp`, which `strict` makes read-only |
| `ProtectHome=read-only` (never `yes`) | `CacheDirectory=restic` + `RESTIC_CACHE_DIR=%C/restic` | restic can't create `/root/.cache`, runs uncached |
| `CapabilityBoundingSet=CAP_DAC_READ_SEARCH` | that one capability | reading `/etc/shadow`, `/etc/gshadow`, 0640 uploads → incomplete snapshot |
| `RestrictAddressFamilies=AF_UNIX` | AF_UNIX (+ INET/INET6 for a remote repo) | mysqldump can't reach `/var/lib/mysql/mysql.sock` |
| `PrivateNetwork=true`, `IPAddressDeny=any` | local repo only | a remote repo; path-based unix sockets still work |
| `UMask=0077` | script `chmod 0644` on the `.prom` | node_exporter (non-root) can't read the metric |

Also set: `NoNewPrivileges`, `PrivateDevices`, `ProtectKernel{Tunables,Modules,Logs}`,
`ProtectControlGroups`, `ProtectClock`, `ProtectHostname`, `ProtectProc=invisible`,
`ProcSubset=pid`, `RestrictNamespaces`, `RestrictRealtime`, `RestrictSUIDSGID`,
`LockPersonality`, `MemoryDenyWriteExecute`, `SystemCallArchitectures=native`,
`SystemCallFilter=@system-service`. Not set on purpose: `User=`, `DynamicUser=` and
`PrivateUsers=`, which would break socket auth and the `/etc/shadow` read.

`After=mariadb.service` is ordering only (no `Requires=`), so a missing database never
blocks the `etc` backup. `network-online.target` is only pulled in for a remote repo.
Expected `systemd-analyze security restic-backup.service`: about 2–2.6 "OK" with a
local repo. This is an estimate until it is measured on data1.

SELinux: the script is `bin_t` in `/usr/local/bin`, so the unit runs as
`unconfined_service_t`. No fcontext, boolean or port changes are needed.

## Until MariaDB exists: `platform` fails (expected)
On a data node where the `mariadb` role hasn't run yet, every run reports
`mysqldump: command not found`. Then `platform` = failed, `etc` = ok, the unit
ends `failed`, and `restic_backup_success{tag="platform"} 0` fires
`ResticBackupFailed`. That is accepted. Once `mariadb.yml` and the WordPress/NFS
plays have run, `platform` succeeds with no role change.

## 3-2-1 — read this
The default `restic_repository` is a **local path** so you can validate mechanics
immediately. That is **not** off-host. For real 3-2-1, override it to remote storage:
```yaml
restic_repository: "sftp:backup@control.platform.lab:/srv/restic"   # control node / NAS
# or  s3:http://minio.lab:9000/restic
```
(SFTP needs the deploy key authorised on the backup host for the `backup` user.)
A non-`/` value flips the unit automatically: no `PrivateNetwork`, AF_INET/AF_INET6
allowed, `Wants=`/`After=network-online.target`, no repo in `ReadWritePaths`.

## Monitoring
`restic_backup.prom` (0644) in `restic_textfile_dir`:
- `restic_backup_success{tag="platform"|"etc"}`: 1/0 for the last run.
- `restic_backup_last_success_timestamp_seconds{tag=…}`: carried forward on failure.
  It feeds `ResticBackupStale` (alert-rules.yml.j2). It's absent until a tag first succeeds.
- `restic_backup_duration_seconds`, `restic_backup_timestamp_seconds`: the whole run.

A prune failure fails the unit (visible in the journal) but leaves `success` at 1,
since the snapshots themselves are good.

## Verify (on data1)
The script refuses to run outside the unit (no `RESTIC_*` in the environment), so
start it through systemd, which also applies the hardening:
```bash
systemctl list-timers restic-backup.timer
sudo systemctl start restic-backup.service; systemctl status restic-backup.service --no-pager
sudo journalctl -t restic-backup -n 50 --no-pager
sudo bash -c 'set -a; . /etc/restic/env; restic snapshots --tag platform; restic snapshots --tag etc'
systemd-analyze security restic-backup.service --no-pager | tail -1
cat /var/lib/node_exporter/textfile_collector/restic_backup.prom
```

## Restore
`dr.yml` restores `latest --tag platform`. The tag is required: without it, `latest`
would be the newest snapshot of *any* tag, often `etc`. It restores to staging by
default, and an explicit `target=live` re-imports. A single `/etc` file:
```bash
sudo bash -c 'set -a; . /etc/restic/env; restic restore latest --tag etc --include /etc/hosts --target /var/restore/etc-test'
```

## Migrating from a hand-made unit
The role **overwrites** `/etc/systemd/system/restic-backup.{service,timer}` and
`/etc/restic/env`. Copy them aside before the first apply, and review
`--check --diff`. A previous repo (e.g. `/srv/backup/restic`) and its password
file are left untouched. The new unit can only read that repo. Retire it by hand
after the new repo passes a restore test. Nothing is copied over.

## Testing
`molecule/default/verify.yml` checks the script, the env file (0600, `RESTIC_*`
only), repo init, the adopted unit directives, `ProtectHome` never `yes`, and the
timer. **Status: written, not run yet** (no Podman on control, CI runner down).
The exposure score and the real backup run are verified on data1 only.

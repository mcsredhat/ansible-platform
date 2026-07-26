#!/usr/bin/env bash
# =============================================================================
# restic_backup.sh — CLI equivalent of the `restic_backup` role
# Mirrors: roles/restic_backup/tasks/main.yml — verified against source.
# Run as root. IMPORTANT: a LOCAL repository path is NOT real 3-2-1 backup —
# override to off-host storage in production (sftp: or s3: — see comments).
# =============================================================================

dnf -y install restic rsync

# Off-host targets (uncomment ONE for real 3-2-1; the local path below is only
# for validating the mechanics before you have real off-host storage):
REPO=/srv/restic-repo
# REPO='sftp:backup@192.168.1.5:/srv/restic'     # control node / NAS over SSH
# REPO='s3:http://minio.lab:9000/restic'          # object storage

mkdir -p /etc/restic
echo "CHANGE_ME_STRONG_PASSWORD" > /etc/restic/repo.pass
chmod 0600 /etc/restic/repo.pass
mkdir -p /var/backups/wordpress /var/lib/node_exporter/textfile_collector

export RESTIC_PASSWORD_FILE=/etc/restic/repo.pass

# Idempotent init: PROBE first (a blind `restic init` errors if already initialized)
if ! restic -r "$REPO" snapshots >/dev/null 2>&1; then
  restic -r "$REPO" init
fi

# Backup script (what the systemd timer actually runs): dump the DB, then back
# up the dump + the shared uploads tree together.
cat > /usr/local/bin/restic-backup.sh <<SCRIPT
#!/bin/bash
set -euo pipefail
export RESTIC_PASSWORD_FILE=/etc/restic/repo.pass
mysqldump wordpress -u wp_user -pCHANGE_ME > /var/backups/wordpress/wordpress.sql
restic -r ${REPO} backup /var/backups/wordpress /srv/wordpress/uploads --tag platform
restic -r ${REPO} forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
restic -r ${REPO} check
echo "restic_backup_success 1" > /var/lib/node_exporter/textfile_collector/restic.prom
SCRIPT
chmod 0750 /usr/local/bin/restic-backup.sh

# Scheduled nightly at 02:30 via a proper systemd timer (not cron):
cat > /etc/systemd/system/restic-backup.service <<'UNIT'
[Unit]
Description=Restic platform backup
[Service]
Type=oneshot
ExecStart=/usr/local/bin/restic-backup.sh
UNIT
cat > /etc/systemd/system/restic-backup.timer <<'UNIT'
[Unit]
Description=Nightly restic backup
[Timer]
OnCalendar=*-*-* 02:30:00
RandomizedDelaySec=600
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now restic-backup.timer

# --- Restore ---
restic -r "$REPO" snapshots
restic -r "$REPO" restore latest --target /var/restore

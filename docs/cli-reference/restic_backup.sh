#!/usr/bin/env bash
# =============================================================================
# restic_backup.sh — CLI equivalent of the `restic_backup` role
# Mirrors: roles/restic_backup/tasks/main.yml + templates/ — verified against source.
# Run as root. IMPORTANT: a LOCAL repository path is NOT real 3-2-1 backup —
# override to off-host storage in production (sftp: or s3: — see comments).
# One repository, two tags: "platform" (DB dump + uploads) and "etc" (/etc).
# =============================================================================

dnf -y install restic rsync

# Off-host targets (uncomment ONE for real 3-2-1; the local path below is only
# for validating the mechanics before you have real off-host storage).
# A remote repo also changes the unit: see the comments in the [Unit]/[Service] below.
REPO=/srv/restic-repo
# REPO='sftp:backup@control.platform.lab:/srv/restic'     # control node / NAS over SSH
# REPO='s3:http://minio.lab:9000/restic'          # object storage

install -d -m 0750 /etc/restic
echo "CHANGE_ME_STRONG_PASSWORD" > /etc/restic/repo.pass
chmod 0600 /etc/restic/repo.pass

# EnvironmentFile for the unit: RESTIC_* only, never the password itself
cat > /etc/restic/env <<ENV
RESTIC_REPOSITORY=${REPO}
RESTIC_PASSWORD_FILE=/etc/restic/repo.pass
ENV
chmod 0600 /etc/restic/env

install -d -m 0700 /var/backups/wordpress                     # holds DB dumps
install -d -m 0755 /var/lib/node_exporter/textfile_collector  # node_exporter reads it

export RESTIC_PASSWORD_FILE=/etc/restic/repo.pass

# Idempotent init: PROBE first (`restic init` refuses an existing repo anyway)
if ! restic -r "$REPO" cat config >/dev/null 2>&1; then
  restic -r "$REPO" init
fi

# Backup script (what the systemd unit runs). Quoted heredoc: nothing expands here.
# It needs RESTIC_* from /etc/restic/env, so run it via systemctl, not by hand.
cat > /usr/local/bin/restic-backup.sh <<'SCRIPT'
#!/usr/bin/env bash
set -uo pipefail
: "${RESTIC_REPOSITORY:?run via systemctl start restic-backup.service}"
: "${RESTIC_PASSWORD_FILE:?run via systemctl start restic-backup.service}"
PROM=/var/lib/node_exporter/textfile_collector/restic_backup.prom
DUMP=/var/backups/wordpress/wordpress.sql.gz
START=$(date +%s); platform_rc=0; etc_rc=0; prune_rc=0

# tag platform: dump (root via unix socket) to .tmp, then dump + uploads
if mysqldump --single-transaction --routines --triggers wordpress | gzip > "${DUMP}.tmp"; then
  mv "${DUMP}.tmp" "${DUMP}"
else
  echo "ERROR: mysqldump failed" >&2; rm -f "${DUMP}.tmp"; platform_rc=1
fi
[ "$platform_rc" -eq 0 ] && { restic backup /var/backups/wordpress /srv/wordpress/uploads --tag platform || platform_rc=1; }
[ "$platform_rc" -eq 0 ] && { restic forget --tag platform --group-by host,tags --keep-daily 7 --keep-weekly 4 --keep-monthly 6 || platform_rc=1; }

# tag etc: runs even when the platform step failed
restic backup /etc --tag etc || etc_rc=1
[ "$etc_rc" -eq 0 ] && { restic forget --tag etc --group-by host,tags --keep-daily 7 --keep-weekly 4 || etc_rc=1; }

# one prune for both tags
if [ "$platform_rc" -eq 0 ] || [ "$etc_rc" -eq 0 ]; then restic prune || prune_rc=1; fi
END=$(date +%s)

# Metrics (the role also carries restic_backup_last_success_timestamp_seconds{tag}
# forward on failure; see templates/restic-backup.sh.j2)
ok() { [ "$1" -eq 0 ] && echo 1 || echo 0; }
cat > "${PROM}.tmp" <<METRICS
restic_backup_success{tag="platform"} $(ok "$platform_rc")
restic_backup_success{tag="etc"} $(ok "$etc_rc")
restic_backup_duration_seconds $((END - START))
restic_backup_timestamp_seconds ${END}
METRICS
chmod 0644 "${PROM}.tmp"          # UMask=0077 in the unit; node_exporter must read it
mv "${PROM}.tmp" "${PROM}"
exit $(( platform_rc | etc_rc | prune_rc ))
SCRIPT
chmod 0750 /usr/local/bin/restic-backup.sh

# Hardened unit (local repo). For a remote repo: After=network-online.target
# mariadb.service + Wants=network-online.target, drop PrivateNetwork/IPAddressDeny
# and the repo from ReadWritePaths, add AF_INET AF_INET6.
cat > /etc/systemd/system/restic-backup.service <<UNIT
[Unit]
Description=Platform restic backup (tags: platform, etc)
After=mariadb.service

[Service]
Type=oneshot
EnvironmentFile=/etc/restic/env
Environment=RESTIC_CACHE_DIR=%C/restic
ExecStart=/usr/local/bin/restic-backup.sh
SyslogIdentifier=restic-backup
UMask=0077
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
CacheDirectory=restic
CacheDirectoryMode=0700
NoNewPrivileges=true
CapabilityBoundingSet=CAP_DAC_READ_SEARCH
ProtectSystem=strict
ReadWritePaths=/var/backups/wordpress /var/lib/node_exporter/textfile_collector ${REPO}
ProtectHome=read-only
PrivateTmp=true
PrivateDevices=true
PrivateNetwork=true
IPAddressDeny=any
RestrictAddressFamilies=AF_UNIX
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
ProcSubset=pid
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=true
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
UNIT
cat > /etc/systemd/system/restic-backup.timer <<'UNIT'
[Unit]
Description=Nightly restic backup (tags: platform, etc)
[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
RandomizedDelaySec=300
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now restic-backup.timer

# --- Run once + verify ---
# Until MariaDB is installed, "platform" fails (mysqldump not found) and "etc" succeeds.
systemctl start restic-backup.service
journalctl -t restic-backup -n 50 --no-pager
systemd-analyze security restic-backup.service --no-pager | tail -1

# --- Restore ---
set -a; . /etc/restic/env; set +a
restic snapshots --tag platform
restic snapshots --tag etc
restic restore latest --tag platform --target /var/restore         # what dr.yml does
restic restore latest --tag etc --include /etc/hosts --target /var/restore/etc-test

#!/usr/bin/env bash
# =============================================================================
# mail_backup.sh — CLI equivalent of `mail_backup` (encrypted mail backups)
# Mirrors: roles/mail_backup/tasks/main.yml — verified against source.
# Run as root (mail1).
# =============================================================================

dnf -y install restic
mkdir -p /srv/restic/mail
chmod 0700 /srv/restic/mail
export RESTIC_REPOSITORY=/srv/restic/mail
export RESTIC_PASSWORD='CHANGE_ME'

# Idempotent init — a blind `restic init` errors on an existing repo, so check
# the actual failure reason rather than assuming success:
OUT=$(restic init 2>&1) || true
if echo "$OUT" | grep -q "already exists"; then
  echo "repo already initialized"
elif echo "$OUT" | grep -q "created restic repository"; then
  echo "repo initialized"
else
  echo "$OUT"; exit 1
fi

# Backup script: dump the mail DB (consistent snapshot), back it up alongside
# the maildirs, THEN delete the local dump (don't leave plaintext DB dumps lying around):
cat > /usr/local/bin/mail-backup.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail
export RESTIC_REPOSITORY=/srv/restic/mail
export RESTIC_PASSWORD='CHANGE_ME'
DUMP=/var/backups/mailserver.sql
mkdir -p /var/backups
sudo -u postgres pg_dump mailserver > "$DUMP"
restic backup /var/mail/vhosts "$DUMP" --tag mail --host "$(hostname)"
restic forget --tag mail --keep-daily 7 --keep-weekly 4 --prune
restic check
rm -f "$DUMP"
SCRIPT
chmod 0750 /usr/local/bin/mail-backup.sh

cat > /etc/systemd/system/mail-backup.service <<'UNIT'
[Unit]
Description=Mail backup (maildirs + PostgreSQL dump)
[Service]
Type=oneshot
ExecStart=/usr/local/bin/mail-backup.sh
UNIT
cat > /etc/systemd/system/mail-backup.timer <<'UNIT'
[Unit]
Description=Nightly mail backup
[Timer]
OnCalendar=*-*-* 02:30:00
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now mail-backup.timer

# --- Restore ---
restic snapshots
restic restore latest --target /var/restore
# then: rsync mailboxes back + psql < the restored .sql   (see docs/runbooks/mail-dr.md)

# Runbook: Mail Disaster Recovery (Backup & Restore)

Backups are restic-encrypted (AES-256), taken nightly by `mail_backup`
(mailboxes `/var/mail/vhosts` + a `pg_dump` of the `mailserver` DB).

## Verify backups exist and are healthy
```bash
export RESTIC_REPOSITORY=/srv/restic/mail RESTIC_PASSWORD=<vault>
restic snapshots            # list recovery points
restic check                # verify integrity of the encrypted repo
```

## Restore mailboxes
```bash
# restore the latest snapshot to a staging path, then sync into place
restic restore latest --target /var/restore
rsync -a /var/restore/var/mail/vhosts/ /var/mail/vhosts/
chown -R vmail:vmail /var/mail/vhosts
restorecon -R /var/mail/vhosts        # fix SELinux contexts
```

## Restore the mail database
```bash
# the pg_dump is inside the snapshot at /var/backups/mailserver.sql
restic restore latest --target /var/restore --include /var/backups/mailserver.sql
sudo -u postgres psql -c "DROP DATABASE IF EXISTS mailserver;"
sudo -u postgres psql -c "CREATE DATABASE mailserver OWNER mailuser;"
sudo -u postgres psql -d mailserver < /var/restore/var/backups/mailserver.sql
```

## Full node rebuild (mail1 lost)
1. Provision a fresh RHEL 9 host as mail1 in inventory.
2. `ansible-playbook mail.yml` — rebuilds the entire stack from code.
3. Restore mailboxes + DB from restic (above).
4. Verify: `doveadm auth test <user> <pass>`; send a test with swaks; check webmail.

## Test cadence
Exercise a restore to a scratch path monthly. An untested backup is not a backup.
A restore drill validates both the repo integrity and this procedure.

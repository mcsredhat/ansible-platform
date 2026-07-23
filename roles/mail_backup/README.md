# mail_backup
restic-encrypted nightly backup of the mailboxes (/var/mail/vhosts) and the mail
PostgreSQL database. Local repo in the lab; point mail_backup_repo at S3/B2 for
off-site durability in production. Restore procedure: docs/runbooks/mail-dr.md.

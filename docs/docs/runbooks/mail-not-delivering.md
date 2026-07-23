# Runbook: Mail Not Delivering

## Symptoms
Users report sent mail not arriving; `MailQueueHigh` alert; messages stuck.

## Triage (in order)
1. **Are the services up?**
   `systemctl is-active postfix dovecot rspamd postgresql`
2. **Inspect the queue:**
   `mailq | tail` (or `postqueue -p`). Note the deferral reason per message.
3. **Read the log:**
   `tail -50 /var/log/maillog` — look for `status=deferred`/`bounced` and the reason.

## Common causes & fixes
- **LMTP handoff failing** (`status=deferred ... dovecot-lmtp`): check the socket
  `/var/spool/postfix/private/dovecot-lmtp` exists and Dovecot is up; check SELinux
  AVCs (`ausearch -m avc -ts recent | grep -E 'postfix|dovecot'`).
- **PostgreSQL lookup failing** (`Connect failed to database`): PostgreSQL down, or
  the `dovecot_auth_t -> postgresql` SELinux policy missing (re-run mail_dovecot).
- **Virtual mailbox not found** (`User unknown`): the address isn't in
  `virtual_users`. Verify: `sudo -u postgres psql -d mailserver -c "SELECT email FROM virtual_users;"`
- **Disk full** (`No space left`): `df -h /var/mail`; free space, then `postqueue -f` to flush.

## Recovery
- After fixing the root cause, flush the queue: `postqueue -f`
- Confirm delivery: send a test with `swaks --to user@domain --server 127.0.0.1`
  and check `/var/mail/vhosts/<domain>/<user>/new/`.

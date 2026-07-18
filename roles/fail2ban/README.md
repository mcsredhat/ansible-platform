# Role: fail2ban

Network-layer intrusion banning (00-architecture §4.1). **Complements** the faillock
control from the `hardening` role: faillock locks the *account* after failed logins,
fail2ban bans the *source IP* at firewalld after spotting abuse in service logs.

## What it does
- Installs **fail2ban** + **fail2ban-firewalld** (firewalld/nftables banaction).
- Deploys `/etc/fail2ban/jail.d/10-platform.local` with a `[DEFAULT]` block
  (bantime/findtime/maxretry, `ignoreip` covering loopback + the mgmt subnet) and one
  stanza per enabled jail.
- Enables + starts the service.

## Jails per tier (data-driven via `fail2ban_jails`)
- **All nodes**: `sshd` (journald/`systemd` backend).
- **web + edge**: adds `nginx-http-auth`, `nginx-botsearch` (set in `group_vars`).
- **mail** (Phase 6): will add `postfix`, `dovecot`.

Each jail is a dict — `name`, optional `backend`, `port`, `filter`, `logpath`,
`maxretry` — so extending is a group_vars edit, not a template change.

## Safety note
`ignoreip` includes the management subnet on purpose, so a mistyped login from your
workstation (or the Ansible control node) can't get you banned. In production, narrow
it to just the jump/management hosts.

## Ordering
The nginx jails read `/var/log/nginx/*.log`, so apply this **after** `nginx_common`
is on all web/edge nodes — otherwise those jails fail to start for want of a logfile.

## Verify
```bash
fail2ban-client status               # lists active jails
fail2ban-client status sshd          # banned IPs, found count
firewall-cmd --list-rich-rules       # bans show up here once they trigger
```

# CLI Reference — running the platform by hand (no Ansible)

Each file here is the **command-line equivalent** of one Ansible role — the same
work, done by hand. Use these when there's no Ansible available (a locked-down
client, quick troubleshooting, a one-off task, or explaining a concept in an
interview). Every file has copy-paste commands with comments explaining *what*
and *why*.

> These mirror `roles/<name>/tasks/main.yml`. Placeholders like `CHANGE_ME`,
> IPs, and hostnames match the lab (`platform.lab`, `10.50.1.0/24`) — adapt to
> your environment. Read before you run; several commands change system state.

## How to run a single concern
You don't need the whole platform. Grab the one file you need:

```bash
# e.g. just set up auditing, or just SELinux troubleshooting:
bash audit.sh          # (or copy-paste the sections you want)
less selinux.sh        # reference-read the SELinux toolkit
```

The Ansible equivalent of "run only one concern" is tags, e.g.
`ansible-playbook site.yml --tags audit` or `--tags selinux`.

## Index by category

### Foundation (every node)
| File | Role | What it does |
|------|------|--------------|
| `base.sh` | base | hostname, /etc/hosts, repos, packages, time, firewall, SELinux |
| `hardening.sh` | hardening | SSH, faillock, pwquality, sudo logging, sysctl hardening |
| `tuning.sh` | tuning | tuned profile, THP off, ulimits, performance sysctls |
| `audit.sh` | audit | **auditd + AIDE + OpenSCAP** compliance scanning |
| `selinux.sh` | (cross-cutting) | **SELinux toolkit**: denials, booleans, contexts, ports, policy modules |
| `fail2ban.sh` | fail2ban | brute-force jails (SSH, SMTP/IMAP) |
| `secops.sh` | secops | bridges auditd/AIDE/fail2ban into Prometheus metrics + Loki |

### Data tier (data1)
| File | Role | What it does |
|------|------|--------------|
| `mariadb.sh` | mariadb | WordPress DB, network bind, secure, WP db + user |
| `redis.sh` | redis | cache/session store, auth, maxmemory, harden |
| `nfs_server.sh` | nfs_server | shared uploads export (needs real kernel — not containerizable) |

### Web tier + HA (web1/web2, edge1/edge2)
| File | Role | What it does |
|------|------|--------------|
| `nginx_common.sh` | nginx_common | web-tier nginx baseline + snippets (:8080) |
| `php_fpm.sh` | php_fpm | PHP stream, FPM pool as nginx user, SELinux booleans |
| `nfs_client.sh` | nfs_client | mount the shared uploads on web nodes |
| `wordpress.sh` | wordpress | WP-CLI install, wp-config, Redis object cache |
| `nginx_edge.sh` | nginx_edge | TLS termination + reverse-proxy load balancer |
| `keepalived.sh` | keepalived | **floating VIP (VRRP)** — the HA front door |

### Backups
| File | Role | What it does |
|------|------|--------------|
| `restic_backup.sh` | restic_backup | encrypted, deduplicated, scheduled backups |

### Observability (obs1 + exporters everywhere)
| File | Role | What it does |
|------|------|--------------|
| `prometheus.sh` | prometheus | metrics server, scrape config, alert rules |
| `alertmanager.sh` | alertmanager | routes alerts to email via mail1 |
| `loki.sh` | loki | log aggregation store |
| `promtail.sh` | promtail | log shipper (tails logs → Loki) |
| `grafana.sh` | grafana | dashboards + datasources |
| `node_exporter.sh` | node_exporter | host metrics (:9100) — the exporter pattern template |
| `blackbox_exporter.sh` | blackbox_exporter | black-box probing (the VIP from outside) |
| `nginx_exporter.sh` | nginx_exporter | nginx stub_status metrics |
| `mysqld_exporter.sh` | mysqld_exporter | MariaDB metrics |

### Mail (mail1)
| File | Role | What it does |
|------|------|--------------|
| `mail_postgres.sh` | mail_postgres | dedicated PostgreSQL mailbox backend + schema |
| `mail_postfix.sh` | mail_postfix | the MTA — receive/relay, PG lookups, LMTP, SASL |
| `mail_dovecot.sh` | mail_dovecot | IMAP/POP3 + Maildir delivery + PG auth |
| `mail_rspamd.sh` | mail_rspamd | spam filtering + DKIM signing (milter) |
| `mail_dns.sh` | mail_dns | BIND zone: MX/SPF/DKIM/DMARC/MTA-STS/TLS-RPT |
| `mail_roundcube.sh` | mail_roundcube | webmail (nginx + PHP-FPM + own PG db) |
| `mail_exporter.sh` | mail_exporter | postfix + rspamd metrics into Prometheus |
| `mail_backup.sh` | mail_backup | restic backup of mailboxes + mail database |

### Phase-level (not a single role)
| File | Mirrors | What it does |
|------|---------|--------------|
| `validate.sh` | `validate.yml` | **health-check every tier** in one place (edge/web/data/obs/mail) |
| `ci-checks.sh` | `.gitlab-ci.yml` | run the **CI gates by hand** (yamllint, ansible-lint, syntax, gitleaks, molecule) |

## The recurring patterns (learn once, apply everywhere)

- **Exporters** all follow: download binary → system user → systemd unit →
  firewall port → `curl localhost:PORT/metrics`. `node_exporter.sh` is the template.
- **Validate before reload** for anything that can lock you out: `sshd -t`,
  `nginx -t`, `visudo -cf`, `promtool check config`, `rspamadm configtest`.
- **Firewall by source subnet**, not open-to-world, for internal services
  (MariaDB, Redis) — see the rich-rule examples.
- **SELinux**: prefer a boolean (`setsebool -P ...`); if none fits, build a policy
  module from the denials (`audit2allow`). See `selinux.sh`.
- **Secrets**: every `CHANGE_ME` here is a Vault variable in the Ansible version —
  never hard-code these in real use.

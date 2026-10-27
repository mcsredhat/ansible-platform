# 00 — Ansible Platform: Architecture Blueprint (LOCKED)

A single Ansible monorepo that provisions **two production-grade stacks on RHEL 9 under
enforcing SELinux** — the HA WordPress platform (edge / web / data / obs) and the mail
platform (Postfix / Dovecot / Rspamd / webmail) — built from shared foundation roles so the
base, security, and observability layers are written once and reused by both.

This is the **locked target**. Every later file (`01-base`, `02-mariadb`, …) implements a slice
of this document. Build order is in §9.

---

## 1. Design principles (the "why" you can defend in an interview)

1. **Declarative + idempotent.** No transcribed bash. Interactive steps (`mariadb-secure-installation`, `wp core install`, `restic init`) become idempotent tasks with `creates`/`changed_when` guards.
2. **One variable per invariant.** `webdata_uid: 980`, `vip`, `subnet`, `backend_marker`, `wp_role`, `innodb_buffer_pool_size` — defined once, referenced everywhere. The web1-vs-web2 difference collapses to two `host_vars` lines.
3. **Firewall + SELinux belong to the role that opens the port.** `base` sets the baseline; each service role owns its own port, booleans, and fcontext. No central firewall role that drifts out of sync with what's installed.
4. **Secrets in Ansible Vault**, never plaintext. `vault_`-prefixed variables in `group_vars/all/vault.yml`. Clean future bridge to HashiCorp Vault.
5. **Security is two jobs, not one.** *Preventive* (`hardening`) changes config to shrink attack surface; *detective* (`audit`) observes, proves, and alerts. Both required.
6. **Backups only count when they report and prove themselves.** 3-2-1, monitored into Prometheus, restore-tested on a schedule, with a runnable DR path.
7. **Tested + linted.** Molecule on representative roles, `ansible-lint` + `yamllint` + `pre-commit` + CI on every push.
8. **Validation is code.** The end-to-end demo (TLS, WAF, failover, blue/green, backups) becomes `assert`-based plays, not a manual checklist.

---

## 2. Inventory groups

| Group | Nodes | Role focus |
|---|---|---|
| `edge` | edge1 (.11), edge2 (.12) | nginx WAF/TLS, keepalived VIP (.10) |
| `web`  | web1 (.21), web2 (.22) | nginx backend, php-fpm, WordPress |
| `data` | data1 (.31) (+data2 later) | MariaDB, Redis, NFS, restic |
| `obs`  | obs1 (.41) | Prometheus, Grafana, Alertmanager, Loki |
| `mail` | mail1 (+mail2 later) | Postfix, Dovecot, Rspamd, webmail |
| `all`  | every node | base, hardening, audit, tuning, exporters, promtail |

---

## 3. Role map

### 3.1 Foundation — applied to `all`

| Role | Responsibility | Key modules / collection |
|---|---|---|
| `base` | hostname, /etc/hosts, NIC/IP, chrony, EPEL, repos, firewalld + SELinux **enforcing** baseline | `hostname`, `community.general.nmcli`, `ansible.posix.selinux`, `dnf` |
| `hardening` | **preventive**: sshd hardening (key-only, no root, ciphers/MACs), PAM faillock, pwquality, sudo logging, *security* sysctls, login/umask policy | `ansible.posix.sysctl`, `lineinfile`, `pamd` |
| `audit` | **detective**: auditd + curated CIS/STIG ruleset (`-e 2`), AIDE baseline + scheduled check, OpenSCAP scan → stored HTML report, ship audit/auth logs to Loki, AVC-denial alerting | `template`, `command`/`creates`, `cron`/`systemd` |
| `tuning` | host-level: `tuned-adm` profile, **disable THP**, `limits.conf` / systemd `LimitNOFILE`, *performance* sysctls (separate from security set) | `command`, `template`, `ansible.posix.sysctl` |
| `fail2ban` | shared jails per service (sshd, nginx, postfix, dovecot) | `template`, `service` |
| `certs` | issue + renew TLS (step-ca for lab / certbot), distribute to nodes | `command`/`creates`, `copy` |
| `node_exporter` + `promtail` | metrics + log shipping on every host | `get_url`, `template`, `systemd` |

> **Security note:** SELinux enforcing platform-wide is itself a major control most projects
> skip — `base` sets it, `audit` watches AVC denials and alerts. Preventive + detective, closed loop.

### 3.2 Web / data stack

| Role | Responsibility | Key modules / collection |
|---|---|---|
| `nginx_common` | install + base tuning, shared by edge & backend (DRY) | `dnf`, `template`, handlers |
| `nginx_edge` | TLS termination, ModSecurity + OWASP CRS, rate-limit, h2/h3, upstream, 444 catch-all; **edge-sized** worker/buffer tuning | `template`, `community.general.seport` |
| `keepalived` | VIP + health-check script (nginx-down → priority drop → failover) | `template`, `service` |
| `nginx_backend` | :8080 vhost, `X-Backend` marker (variable), real_ip; backend-sized tuning | `template` |
| `php_fpm` | pool as `nginx` user, socket perms, `pm`/`max_children` sized to RAM + opcache | `lineinfile`, `service` |
| `wordpress` | install-vs-serve logic, wp-config template, **vaulted salts**, wp-cli, Redis object-cache wiring | `command`/`creates`, `template` |
| `mariadb` | bind to subnet, idempotent hardening, DB + grant, replication (primary/replica), `innodb_buffer_pool_size` **as a variable sized to host RAM**, binlog for PITR | `community.mysql.*` |
| `redis` | **shared** object cache (WordPress + Rspamd), bind/requirepass/protected-mode, maxmemory + eviction, THP-aware | `template`, `ansible.posix.firewalld` |
| `haproxy` | L4/L7 LB in front of the MariaDB tier (read/write split, health checks), native Prometheus stats | `template` |
| `nfs_server` / `nfs_client` | UID/GID 980 export + `nofail` mounts, `restorecon` after | `ansible.posix.mount`, `command` |
| `restic_backup` | repo-init guard, backup script, timer, **off-host repo**, **success metric**, **restore-test** | `command`/`creates`, `systemd` |

### 3.3 Mail stack

| Role | Responsibility | Key modules / collection |
|---|---|---|
| `postfix` | MTA, virtual mailboxes (PG/LDAP-backed), TLS, submission/465 | `template`, `community.postgresql` |
| `dovecot` | IMAP/POP, SASL auth, LMTP delivery, maildir | `template` |
| `rspamd` | spam filtering + **DKIM signing/verify**, greylisting, ratelimit (uses `redis`) | `template` |
| `webmail` | SOGo or Roundcube | `template`, `dnf` |
| `mail_records` | generate SPF / DKIM / DMARC + MTA-STS / DANE / BIMI records (output for DNS) | `template` |

### 3.4 Observability — on `obs`

`prometheus`, `grafana`, `alertmanager`, `loki`, plus per-service exporter roles
(`mysqld_exporter`, `redis_exporter`, `php_fpm_exporter`, `nginx_exporter`, `postfix_exporter`;
HAProxy and node/promtail expose their own). **Targets to scrape include the backup-success
metric and AVC-denial alerts** — security and DR surface here, not just CPU/mem.

---

## 4. Security deep-dive

### 4.1 Preventive (`hardening`)
sshd: key-only, `PermitRootLogin no`, hardened ciphers/MACs/kex, idle timeout, `AllowUsers`.
PAM: `faillock` lockout, `pwquality` complexity, `pwhistory`. sudo: full command logging.
Security sysctls: `rp_filter`, `tcp_syncookies`, disable redirects/source-routing,
`kernel.kptr_restrict`, `kernel.dmesg_restrict`. umask/login.defs policy.

### 4.2 Detective (`audit`)
- **auditd** installed *with* a curated CIS/STIG ruleset (watches on `/etc/{passwd,shadow,sudoers}`,
  time changes, privileged exec, module load, mount, network config) and `-e 2` to lock it.
- **AIDE** — baseline DB, scheduled integrity check, emailed/Loki'd report.
- **OpenSCAP** — `oscap` scan against a CIS/STIG profile on a schedule → stored HTML evidence.
  *You prove hardened; you don't claim it.*
- **Off-box log shipping** — audit + auth logs to Loki so a compromised node can't erase its trail.
- **AVC alerting** — SELinux denials → Prometheus → Alertmanager.

### 4.3 Tuning (`tuning` + per-service)
Host: `tuned-adm` profile, **THP disabled** (MariaDB/Redis footgun), `LimitNOFILE` for
nginx/redis/mariadb, performance sysctls (`net.core.somaxconn`, `fs.file-max`, tcp backlog,
`vm.swappiness`, dirty ratios) kept **separate** from the security sysctl set.
Per-service (inside each role): nginx workers/buffers (edge ≠ backend), php-fpm `pm`/children +
opcache, MariaDB buffer pool/connections, Redis maxmemory/eviction, HAProxy maxconn/timeouts.

---

## 5. Backup & DR strategy

The `restic_backup` role is the *mechanism*; this is the *strategy* that makes it defensible.

| Requirement | Implementation |
|---|---|
| **3-2-1 — off-host repo** | restic repo on a second host / MinIO / B2-S3, **not** local `/srv` on data1 |
| **Repo key secured** | restic password from Ansible Vault, not plaintext `/root/.restic-pass` |
| **Coverage** | DB dump (`--single-transaction`) + NFS uploads + **mail maildirs + mail DB + DKIM keys**; configs are IaC in git |
| **DB RPO** | nightly full **+ binary logs** for point-in-time recovery (minutes, not 24h) |
| **Monitoring** | restic exit status → Prometheus metric → Alertmanager (no silent failures) |
| **Restore-test** | scheduled restore to scratch, **assert** dump parses / row counts, alert on failure |
| **DR runbook** | `dr.yml`: Ansible re-provisions the node, restic restores the state — the rebuild path, tested |
| **Retention** | `--keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune` (documented RPO/RTO) |

> The DR story in one line: **"Ansible rebuilds the box, restic restores the state."** Both
> halves are version-controlled and tested.

---

## 6. Secrets (Ansible Vault)

`group_vars/all/vault.yml` (encrypted) holds `vault_mariadb_wp_pw`, `vault_restic_pw`,
`vault_redis_pw`, `vault_wp_salts`, `vault_dkim_key`, etc. Non-vault files reference them via
`mariadb_wp_pw: "{{ vault_mariadb_wp_pw }}"`. Vault password in CI via a secret, locally via
`--vault-password-file` (git-ignored).

---

## 7. Directory layout

```
ansible-platform/
├── ansible.cfg
├── requirements.yml              # collections + galaxy roles
├── site.yml                      # master orchestration (ordered, §9)
├── web.yml  mail.yml  observability.yml
├── validate.yml                  # Demo 1–11 as assert plays
├── dr.yml                        # disaster-recovery rebuild path
├── inventories/
│   └── lab/
│       ├── hosts.yml
│       ├── group_vars/
│       │   ├── all/{main.yml, vault.yml}
│       │   ├── edge.yml web.yml data.yml mail.yml obs.yml
│       └── host_vars/{web1.yml, web2.yml, ...}
├── roles/
│   ├── base/
│   │   ├── defaults/main.yml  tasks/main.yml  handlers/main.yml
│   │   ├── templates/  meta/main.yml
│   │   └── molecule/default/    # converge + verify (reference pattern)
│   └── … (all roles in §3)
├── .ansible-lint  .yamllint  .pre-commit-config.yaml
├── .github/workflows/ci.yml
└── README.md
```

---

## 8. Testing & CI

`molecule` on `base` (the reference scenario every role copies) + at least one service role
(`mariadb`). `ansible-lint` + `yamllint` + `pre-commit` locally; GitHub Actions runs lint +
molecule on push (green badge in README). `requirements.yml` pins `ansible.posix`,
`community.general`, `community.mysql`, `community.postgresql`.

---

## 9. Orchestration order (`site.yml`) & build phases

Dependency chain straight out of the platform:

```
1. all   : base → hardening → tuning → audit → node_exporter → promtail
2. all   : certs
3. data  : mariadb (primary→replica) → redis → nfs_server → haproxy → restic_backup
4. web   : nginx_common → php_fpm → wordpress (web1 install, web2 serve) → nfs_client
5. edge  : nginx_common → nginx_edge → keepalived
6. obs   : prometheus → grafana → alertmanager → loki → exporters
7. mail  : postfix → dovecot → rspamd → webmail → mail_records
8. validate.yml : assert TLS / WAF / failover / blue-green / backup-success
```

`serial` / `run_once` / `delegate_to` enforce ordering; `tags` run any single tier.

**Build phases (the order we'll actually write the roles):**
1. **Scaffold** — `ansible.cfg`, `requirements.yml`, inventory + group/host_vars, `base` role + molecule (reference pattern).
2. **Foundation** — `hardening`, `tuning`, `audit`, `fail2ban`, `certs`, exporters/promtail.
3. **Data tier** — `mariadb`, `redis`, `nfs_server`, `restic_backup` (+ off-host repo, monitoring).
4. **Web tier** — `nginx_common`, `php_fpm`, `wordpress`, `nfs_client`, `nginx_edge`, `keepalived`, `haproxy`.
5. **Observability** — prometheus/grafana/alertmanager/loki + exporters; wire audit + backup metrics.
6. **Mail tier** — postfix/dovecot/rspamd/webmail/mail_records.
7. **Validation & DR** — `validate.yml` asserts, `dr.yml`, CI green.

---

## 10. Key variable catalog (the invariants, defined once)

| Variable | Example | Owned by |
|---|---|---|
| `subnet` | `10.50.1.0/24` | group_vars/all |
| `vip` | `10.50.1.10` | group_vars/all |
| `webdata_uid` / `webdata_gid` | `980` / `980` | group_vars/all |
| `backend_marker` | `web1-blue` / `web2-green` | host_vars |
| `wp_role` | `install` / `serve` | host_vars |
| `innodb_buffer_pool_size` | `{{ (ansible_memtotal_mb*0.5)|int }}M` | data.yml |
| `restic_repo` | off-host URL | data.yml (value vaulted) |
| `tuned_profile` | `throughput-performance` | group_vars/all |

---

*Locked. Next: scaffold (Phase 1) — `ansible.cfg`, `requirements.yml`, inventory, and the
`base` role with its molecule scenario as the pattern every other role follows.*

# Compliance Mapping — ANSSI BP-28 / PGSSI-S / HDS

How this platform's technical controls map to French security frameworks, with
the evidence that demonstrates each. This is a **technical-controls** mapping;
organizational and physical controls are listed under "Out of scope" and are the
responsibility of the hosting organization.

## Frameworks referenced
- **ANSSI BP-28** — *Recommandations de sécurisation d'un système GNU/Linux*. Enforced and measured via the OpenSCAP `anssi_bp28_high` profile.
- **PGSSI-S** — *Politique Générale de Sécurité des Systèmes d'Information de Santé* (health-sector SSI policy). Emphasises access control, traceability, integrity, and demonstrable, ongoing security management.
- **HDS** — *Hébergeur de Données de Santé* certification requirements (health-data hosting). Largely organizational; the technical subset is mapped below.

## Control mapping

| Requirement (theme) | How the platform enforces it | Evidence |
|---|---|---|
| **OS hardening baseline** (ANSSI BP-28) | `hardening` + `audit` roles; SELinux enforcing fleet-wide; ANSSI BP-28 high OpenSCAP profile scanned on a timer | Dated `oscap-*.html` reports in `/var/log/oscap`; `compliance_score_percent` Prometheus metric; `ComplianceScoreLow` alert |
| **Access control / least privilege** (PGSSI-S) | Key-only SSH; scoped service accounts (e.g. mysqld_exporter DB user has only PROCESS/REPLICATION CLIENT/SELECT); sudo logged; no shared accounts | `docs/compliance/access-audit.md`; role source; auditd sudo events in Loki |
| **Secrets management** | All secrets in `ansible-vault` (AES256); no plaintext credentials in the repo; CI enforces this | `secrets-scan` CI stage; encrypted `vault.yml`; `.gitignore` excludes `.vault-pass` |
| **Traceability / audit logging** (PGSSI-S) | auditd with CIS rule set; audit events forwarded to journald → Loki; sudo/SSH/AVC log-based alerts | `audit` role; Loki `security-alerts` group; `secops` role |
| **File integrity** (PGSSI-S integrity) | AIDE baseline + timed checks; integrity change surfaced as a metric and alert | `aide_check_changed_files` metric; `AideIntegrityChanged` alert; runbook |
| **Intrusion detection / response** | fail2ban fleet-wide; brute-force & ban-surge alerts; documented incident-response runbooks | `fail2ban` role; Loki rules; `docs/runbooks/` |
| **Backup & recoverability** (HDS availability) | restic encrypted backups on a schedule; documented DR playbook | `restic_backup` role; `dr.yml`; `docs/compliance/backup-encryption.md` |
| **Encryption in transit** | TLS at the edge; system-wide crypto policy | `nginx_edge` role; TLS config |
| **High availability** (HDS availability) | Redundant edge (keepalived VIP), redundant app tier, verified failover | `keepalived` role; SLO/error-budget dashboard; blackbox VIP probe |
| **Change management** | Entire platform is version-controlled, idempotent Ansible; every change is a reviewable commit; CI validates before merge | Git history; `.gitlab-ci.yml` (lint/syntax/secrets); this repo *is* the change record |
| **Continuous compliance monitoring** (PGSSI-S "ongoing") | Compliance is a live metric with staleness + regression alerts, not a one-off audit | `compliance_score_percent`, `compliance_last_scan_timestamp_seconds`; `ComplianceScanStale` alert |

## Out of scope — documented gaps (organizational / physical)

These are **not** demonstrable by a lab platform and are the hosting
organization's responsibility. Listing them explicitly is part of an honest
compliance posture:

- **Encryption at rest** (LUKS full-disk / encrypted DB volumes) — not implemented in this lab; production HDS requires it.
- **Physical security & ISO 27001 processes** — datacenter access, personnel vetting, incident-management procedures.
- **Data retention / erasure & RGPD alignment** for health data — policy + tooling beyond this platform.
- **Formal HDS certification** — an organizational audit/certification, not a technical state. This platform provides the *technical substrate* HDS expects, not the certification itself.

## How to demonstrate (for an audit or interview)

1. Show a dated ANSSI OpenSCAP report and the trend of `compliance_score_percent` in Grafana.
2. Show the access-audit summary and the vaulted-secrets + CI secrets-scan.
3. Show the auditd→Loki traceability and the incident-response runbooks.
4. Show the git history as the change-management record.
5. Be explicit about the out-of-scope organizational controls above.

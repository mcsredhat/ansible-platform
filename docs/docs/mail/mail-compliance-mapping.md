# Mail Platform — Compliance Mapping (ANSSI / PGSSI-S / HDS)

How the mail platform's technical controls map to the frameworks. This extends
the platform-wide `docs/compliance/ANSSI-PGSSI-S-HDS-mapping.md` with mail
specifics. Relevant because mail may carry health data in HDS contexts.

## Control mapping

| Requirement (theme) | How mail enforces it | Evidence |
|---|---|---|
| **Encryption in transit** | TLS on submission (587 STARTTLS) and SMTPS (465); IMAPS/POP3S enforced; opportunistic TLS inbound (`smtpd_tls_security_level=may`) | `mail_postfix` main.cf/master.cf; `mail_dovecot` `ssl=required`; self-signed in lab, real certs (Let's Encrypt) in production |
| **Authentication / access control** | SASL auth via Dovecot for submission; per-user PostgreSQL credentials (SHA512-CRYPT); no open relay (`reject_unauth_destination`) | `mail_dovecot` passdb; Postfix relay restrictions; `virtual_users` table |
| **Sender authentication (anti-spoofing)** | SPF (`v=spf1 mx -all`), DKIM signing (Rspamd), DMARC (`p=quarantine` + rua reporting) | `mail_dns` zone; `mail_rspamd` dkim_signing; DNS TXT records |
| **Transport security policy** | MTA-STS + TLS-RPT records published | `mail_dns` zone TXT records |
| **Spam / abuse filtering** | Rspamd scoring, greylisting, reject threshold | `mail_rspamd` actions.conf/greylist.conf |
| **Traceability / audit logging** | `/var/log/maillog` shipped to Loki; searchable, retained | `mail_exporter` promtail maillog job; Loki |
| **Intrusion protection** | fail2ban jails on postfix + dovecot (brute-force) | `fail2ban_jails_mail` (postfix, dovecot) |
| **Availability monitoring** | postfix + rspamd Prometheus metrics; queue-depth, exporter-down, rspamd-down alerts | `mail_exporter`; Mail Platform dashboard; MailQueueHigh/MailExporterDown/RspamdDown alerts |
| **Backup & recoverability** | restic-encrypted mailbox backups; documented restore | `docs/runbooks/mail-dr.md`; `dr.yml` |
| **Data isolation** | mail data in a dedicated PostgreSQL on mail1, separate from the app data tier (MariaDB on data1) | `mail_postgres`; ADR-mail-01 |
| **Change management** | mail stack is version-controlled idempotent Ansible; CI-validated | git history; `.gitlab-ci.yml` |

## Out of scope — documented gaps

- **Encryption at rest** for mailbox storage (Maildir) — not implemented in lab; production HDS requires encrypted volumes (LUKS).
- **Public deliverability** — lab has no public IP/PTR/real domain; outbound to the internet requires a mail-friendly VPS (PTR control) or a smarthost relay. See ADR-mail-03.
- **DMARC report ingestion** — rua address is published; automated aggregation of received reports is future work.
- **Anti-virus scanning** (ClamAV milter) — not deployed; recommended for production mail carrying attachments.
- **Formal HDS certification** — organizational, not a technical state.

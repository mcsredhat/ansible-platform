# ADR: Mail Platform Architecture Decisions

Status: Accepted. Context: self-hosted mail on mail1 (RHEL 9), part of the
ansible-platform monorepo.

## ADR-mail-01 — Dedicated PostgreSQL for mailboxes (not the app data tier)
**Decision:** Virtual domains/users/aliases live in a dedicated PostgreSQL on
mail1, not in the MariaDB app tier on data1.
**Rationale:** Mail and the web app are different failure domains and security
zones; a mail queue/DB problem must not affect WordPress and vice versa. For HDS,
separating (potentially health-related) mail data from the public app store is the
cleaner posture. Also demonstrates PostgreSQL breadth alongside MariaDB.
**Trade-off:** a second DB engine to operate/back up. Accepted for isolation.

## ADR-mail-02 — Rspamd over SpamAssassin
**Decision:** Rspamd for spam filtering + DKIM signing.
**Rationale:** Modern, faster (C, event-driven), integrated DKIM signing,
greylisting, and a web UI; single milter handles filtering + signing. SpamAssassin
is heavier and needs separate DKIM (OpenDKIM) plumbing.
**Trade-off:** Rspamd config idiom is less familiar to some ops; mitigated by
keeping config minimal and version-controlled.

## ADR-mail-03 — Receive directly, relay outbound via smarthost (production)
**Decision:** In production, receive mail directly but relay *outbound* through a
reputation-managed smarthost (e.g. SES/SendGrid) rather than self-sending.
**Rationale:** Outbound deliverability (IP reputation, PTR/FCrDNS, blocklist and
feedback-loop management) is a specialized, ongoing job. A fresh/low-reputation IP
lands in spam regardless of correct SPF/DKIM/DMARC. Knowing *when not to self-host*
outbound is senior judgment. The lab (no public IP/PTR) can only do internal mail;
the deliverability records are built as real config + design for the public case.
**Trade-off:** dependency on a third-party relay; accepted for deliverability.

## ADR-mail-04 — SHA512-CRYPT with scheme prefix in stored password
**Decision:** Store Dovecot passwords as `{SHA512-CRYPT}$6$...` (scheme in the
value) and omit `default_pass_scheme`.
**Rationale:** Self-describing hashes are robust to future scheme changes and avoid
prefix/scheme mismatches (a real bug hit during build).

## ADR-mail-05 — Rspamd controller exposed to the monitoring subnet for scraping
**Decision:** Bind the Rspamd controller to all interfaces with `secure_ip` for the
monitoring subnet so Prometheus can scrape `/metrics` without the UI password.
**Rationale:** Prometheus (obs1) must reach `/metrics`; the controller is otherwise
loopback-only.
**Trade-off:** wider exposure of the controller. In production, restrict `secure_ip`
to the specific monitoring host, or front metrics with a localhost exporter.

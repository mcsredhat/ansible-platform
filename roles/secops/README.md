# secops
Activates existing detective controls into observable signals (Phase 5d):

- **fail2ban metrics** — a timer parses `fail2ban-client status` into
  `fail2ban_banned_current/total{jail=...}` via the node_exporter textfile
  collector (no external exporter binary needed).
- **AIDE integrity metrics** — a daily timer runs `aide --check` and emits
  `aide_check_changed_files` / `aide_check_rc`, feeding the
  `AideIntegrityChanged` Prometheus alert.
- **auditd → journald** — enables the audisp syslog plugin so audit events
  (passwd/sudoers/sshd_config changes, AVC denials) reach journald and are
  shipped to Loki by promtail for the security LogQL rules.

Pairs with the security LogQL rules (loki), the security Grafana dashboard,
and the incident-response runbooks under docs/runbooks/.

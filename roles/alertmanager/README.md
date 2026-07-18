# alertmanager
Prometheus Alertmanager on obs1. Phase 5: alerts route to a local receiver
(visible in the UI/API and Grafana's alert list) — no external notification
yet. An email receiver is templated but disabled
(`alertmanager_email_enabled: false`); Phase 6 flips it on once mail1
exists. UI on `:9093`.

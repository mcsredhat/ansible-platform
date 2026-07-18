# grafana
Grafana OSS via the official RPM repo (the one exception to binary+systemd
in this platform — Grafana ships a proper YUM repo). Provisions Prometheus
and Loki as datasources automatically. Admin password is set once from
`vault_grafana_admin_pw` via `grafana-cli admin reset-admin-password`,
gated by a marker file so reruns don't reset it. UI on `:3000`.

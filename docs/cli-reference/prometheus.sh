#!/usr/bin/env bash
# =============================================================================
# prometheus.sh — CLI equivalent of the `prometheus` role
# Mirrors: roles/prometheus/tasks/main.yml — verified line-by-line against source.
# Run as root (obs1).
# =============================================================================

VER=2.54.1
useradd -r -s /sbin/nologin -d /var/lib/prometheus prometheus 2>/dev/null || true
mkdir -p /etc/prometheus /etc/prometheus/rules /var/lib/prometheus
chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

cd /tmp
curl -LO "https://github.com/prometheus/prometheus/releases/download/v${VER}/prometheus-${VER}.linux-amd64.tar.gz"
tar xzf "prometheus-${VER}.linux-amd64.tar.gz"
install -m0755 "prometheus-${VER}.linux-amd64/prometheus" /usr/local/bin/prometheus
install -m0755 "prometheus-${VER}.linux-amd64/promtool" /usr/local/bin/promtool

# Main config (list your real hosts; the role generates this from inventory groups)
cat > /etc/prometheus/prometheus.yml <<'PROM'
global:
  scrape_interval: 15s
storage:
  tsdb:
    retention.time: 15d
rule_files:
  - /etc/prometheus/rules/slo-rules.yml
  - /etc/prometheus/rules/platform-alerts.yml
alerting:
  alertmanagers:
    - static_configs: [{ targets: ['127.0.0.1:9093'] }]
scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['edge1:9100','web1:9100','data1:9100','obs1:9100','mail1:9100']
  - job_name: nginx
    static_configs: [{ targets: ['web1:9113','web2:9113','edge1:9113','edge2:9113'] }]
  - job_name: mysqld
    static_configs: [{ targets: ['data1:9104'] }]
  - job_name: blackbox
    metrics_path: /probe
    params: { module: [http_2xx] }
    static_configs: [{ targets: ['https://app.platform.lab'] }]
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: 127.0.0.1:9115
PROM

# Deploy alert/SLO rule files (separate files — see docs/cli-reference for
# example rule content); VALIDATE both config and rules before ever loading them:
touch /etc/prometheus/rules/slo-rules.yml /etc/prometheus/rules/platform-alerts.yml
promtool check config /etc/prometheus/prometheus.yml
promtool check rules /etc/prometheus/rules/*.yml
chown -R prometheus:prometheus /etc/prometheus

cat > /etc/systemd/system/prometheus.service <<'UNIT'
[Unit]
Description=Prometheus
After=network.target
[Service]
User=prometheus
ExecStart=/usr/local/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus --storage.tsdb.retention.time=15d
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now prometheus

# Firewall — the management subnet (people/Grafana reaching the UI), not just obs1
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=9090 protocol=tcp accept'
firewall-cmd --reload

# --- Operating (the query API is gold for scripting/validation) ---
curl -s 'http://127.0.0.1:9090/api/v1/query?query=up' | jq '.data.result[].metric.job' | sort -u
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[].health'

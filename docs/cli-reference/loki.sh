#!/usr/bin/env bash
# =============================================================================
# loki.sh — CLI equivalent of the `loki` role (log aggregation, obs1)
# Mirrors: roles/loki/tasks/main.yml — verified against source.
# Run as root (obs1). Single-node filesystem storage, 7-day retention.
# =============================================================================

VER=3.1.1
dnf -y install unzip
useradd -r -s /sbin/nologin -d /var/lib/loki loki 2>/dev/null || true
mkdir -p /etc/loki /var/lib/loki/chunks /var/lib/loki/rules/fake \
         /var/lib/loki/rules-temp /var/lib/loki/compactor

# LogQL alerting rules go under rules/fake (the "fake" tenant — single-tenant mode)
touch /var/lib/loki/rules/fake/log-alerts.yml
chown -R loki:loki /etc/loki /var/lib/loki

cd /tmp
curl -LO "https://github.com/grafana/loki/releases/download/v${VER}/loki-linux-amd64.zip"
unzip -o loki-linux-amd64.zip
install -m0755 loki-linux-amd64 /usr/local/bin/loki

cat > /etc/loki/loki-config.yml <<'LOKI'
auth_enabled: false
server:
  http_listen_port: 3100
common:
  path_prefix: /var/lib/loki
  storage:
    filesystem:
      chunks_directory: /var/lib/loki/chunks
      rules_directory: /var/lib/loki/rules
  replication_factor: 1
  ring:
    kvstore: { store: inmemory }
schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index: { prefix: index_, period: 24h }
limits_config:
  retention_period: 168h    # 7 days
ruler:
  rule_path: /var/lib/loki/rules-temp
  storage:
    type: local
    local: { directory: /var/lib/loki/rules }
LOKI
chown loki:loki /etc/loki/loki-config.yml

cat > /etc/systemd/system/loki.service <<'UNIT'
[Unit]
Description=Loki
After=network.target
[Service]
User=loki
ExecStart=/usr/local/bin/loki -config.file=/etc/loki/loki-config.yml
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now loki

# Firewall — allow promtail agents across the whole platform subnet to push logs in
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=3100 protocol=tcp accept'
firewall-cmd --reload

# --- Operating ---
curl -s http://127.0.0.1:3100/ready
curl -s 'http://127.0.0.1:3100/loki/api/v1/label/job/values'

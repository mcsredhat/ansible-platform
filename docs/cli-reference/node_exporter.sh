#!/usr/bin/env bash
# =============================================================================
# node_exporter.sh — CLI equivalent of the `node_exporter` role
# Mirrors: roles/node_exporter/tasks/main.yml — verified against source.
# Run as root (on EVERY node). This is the general pattern for ALL exporters
# in this platform: pinned-version binary -> system user -> systemd -> firewall
# scoped to the scraper's IP only (obs1, not the whole subnet).
# =============================================================================

VER=1.8.2
useradd -r -s /sbin/nologin -d /var/lib/node_exporter node_exporter 2>/dev/null || true
mkdir -p /var/lib/node_exporter/textfile_collector
chown node_exporter:node_exporter /var/lib/node_exporter/textfile_collector

cd /tmp
curl -LO "https://github.com/prometheus/node_exporter/releases/download/v${VER}/node_exporter-${VER}.linux-amd64.tar.gz"
tar xzf "node_exporter-${VER}.linux-amd64.tar.gz"
install -m0755 "node_exporter-${VER}.linux-amd64/node_exporter" /usr/local/bin/node_exporter

cat > /etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Node Exporter
After=network.target
[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --collector.textfile.directory=/var/lib/node_exporter/textfile_collector
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now node_exporter

# Firewall — ONLY obs1 (the Prometheus scraper), not the whole subnet:
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.50.1.41 port port=9100 protocol=tcp accept'
firewall-cmd --reload

curl -s localhost:9100/metrics | head -5

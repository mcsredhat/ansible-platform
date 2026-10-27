#!/usr/bin/env bash
# =============================================================================
# blackbox_exporter.sh — CLI equivalent of `blackbox_exporter`
# Mirrors: roles/blackbox_exporter/tasks/main.yml — verified against source.
# Run as root (obs1). Probes the VIP over HTTPS from OUTSIDE — black-box, not
# self-reported — so it catches "the site is down" even if internal
# metrics look fine.
# =============================================================================

VER=0.25.0
useradd -r -s /sbin/nologin blackbox_exporter 2>/dev/null || true
mkdir -p /etc/blackbox_exporter

cd /tmp
curl -LO "https://github.com/prometheus/blackbox_exporter/releases/download/v${VER}/blackbox_exporter-${VER}.linux-amd64.tar.gz"
tar xzf "blackbox_exporter-${VER}.linux-amd64.tar.gz"
install -m0755 "blackbox_exporter-${VER}.linux-amd64/blackbox_exporter" /usr/local/bin/blackbox_exporter

# Probe module: http_2xx against the VIP/vhost
cat > /etc/blackbox_exporter/blackbox.yml <<'CFG'
modules:
  http_2xx:
    prober: http
    http:
      valid_status_codes: [200, 301, 302]
      tls_config:
        insecure_skip_verify: true   # self-signed lab cert; false with real certs
CFG
chown -R blackbox_exporter:blackbox_exporter /etc/blackbox_exporter

cat > /etc/systemd/system/blackbox_exporter.service <<'UNIT'
[Unit]
Description=Blackbox Exporter
After=network.target
[Service]
User=blackbox_exporter
ExecStart=/usr/local/bin/blackbox_exporter --config.file=/etc/blackbox_exporter/blackbox.yml
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now blackbox_exporter

# blackbox_exporter runs ON obs1 itself, so no cross-host firewall rule needed
# unless Prometheus is on a different host.

# Test a probe manually (this is what Prometheus does via relabeling):
curl -s "http://127.0.0.1:9115/probe?target=https://10.50.1.10/&module=http_2xx" | grep probe_success

#!/usr/bin/env bash
# =============================================================================
# nginx_exporter.sh — CLI equivalent of `nginx_exporter`
# Mirrors: roles/nginx_exporter/tasks/main.yml — verified against source.
# Run as root (web + edge tiers — anywhere nginx runs).
# =============================================================================

VER=1.4.0
useradd -r -s /sbin/nologin nginx_exporter 2>/dev/null || true

# stub_status endpoint — LOOPBACK ONLY (127.0.0.1:8081), the exporter scrapes
# this locally; it's never exposed externally.
cat > /etc/nginx/conf.d/stub_status.conf <<'STUB'
server {
    listen 127.0.0.1:8081;
    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
STUB
nginx -t && systemctl reload nginx

cd /tmp
# NOTE: correct upstream repo is nginx/nginx-prometheus-exporter (not nginxinc)
curl -LO "https://github.com/nginx/nginx-prometheus-exporter/releases/download/v${VER}/nginx-prometheus-exporter_${VER}_linux_amd64.tar.gz"
tar xzf "nginx-prometheus-exporter_${VER}_linux_amd64.tar.gz"
install -m0755 nginx-prometheus-exporter /usr/local/bin/nginx-prometheus-exporter

cat > /etc/systemd/system/nginx_exporter.service <<'UNIT'
[Unit]
Description=NGINX Prometheus Exporter
After=network.target nginx.service
[Service]
User=nginx_exporter
ExecStart=/usr/local/bin/nginx-prometheus-exporter --nginx.scrape-uri=http://127.0.0.1:8081/nginx_status
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now nginx_exporter

# Firewall — ONLY obs1 may reach the exporter's metrics port
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.41 port port=9113 protocol=tcp accept'
firewall-cmd --reload

curl -s localhost:9113/metrics | head -5

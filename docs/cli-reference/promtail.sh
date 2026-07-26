#!/usr/bin/env bash
# =============================================================================
# promtail.sh — CLI equivalent of the `promtail` role (log shipper)
# Mirrors: roles/promtail/tasks/main.yml — verified against source.
# Run as root (on every node whose logs should reach Loki on obs1).
# =============================================================================

VER=3.1.1
dnf -y install unzip

# The promtail user needs journald + syslog read access — added to BOTH
# systemd-journal and adm groups (not just one):
useradd -r -s /sbin/nologin promtail 2>/dev/null || true
usermod -aG systemd-journal,adm promtail

mkdir -p /etc/promtail /var/lib/promtail
chown -R promtail:promtail /etc/promtail /var/lib/promtail

cd /tmp
curl -LO "https://github.com/grafana/loki/releases/download/v${VER}/promtail-linux-amd64.zip"
unzip -o promtail-linux-amd64.zip
install -m0755 promtail-linux-amd64 /usr/local/bin/promtail

cat > /etc/promtail/promtail-config.yml <<'PT'
server:
  http_listen_port: 9080
positions:
  filename: /var/lib/promtail/positions.yaml
clients:
  - url: http://obs1:3100/loki/api/v1/push
scrape_configs:
  - job_name: journal
    journal:
      max_age: 12h
      labels: { job: journald, host: HOSTNAME }
PT
chown promtail:promtail /etc/promtail/promtail-config.yml

# ONLY on web/edge tier nodes: grant promtail ACL read access to nginx logs
# (not applied on data1/obs1/mail1 — those don't run nginx as the primary service):
#   setfacl -R -m u:promtail:rx /var/log/nginx

cat > /etc/systemd/system/promtail.service <<'UNIT'
[Unit]
Description=Promtail
After=network.target
[Service]
User=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/promtail-config.yml
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now promtail

#!/usr/bin/env bash
# =============================================================================
# alertmanager.sh — CLI equivalent of the `alertmanager` role
# Mirrors: roles/alertmanager/tasks/main.yml — verified against source.
# Run as root (obs1). Routes firing alerts to email THROUGH the platform's
# own mail server (mail1:587) — see docs/PHASE-WALKTHROUGH.md for how the
# observability and mail phases connect.
# =============================================================================

VER=0.27.0
useradd -r -s /sbin/nologin -d /var/lib/alertmanager alertmanager 2>/dev/null || true
mkdir -p /etc/alertmanager /var/lib/alertmanager
chown -R alertmanager:alertmanager /etc/alertmanager /var/lib/alertmanager

cd /tmp
curl -LO "https://github.com/prometheus/alertmanager/releases/download/v${VER}/alertmanager-${VER}.linux-amd64.tar.gz"
tar xzf "alertmanager-${VER}.linux-amd64.tar.gz"
install -m0755 "alertmanager-${VER}.linux-amd64/alertmanager" /usr/local/bin/alertmanager
install -m0755 "alertmanager-${VER}.linux-amd64/amtool" /usr/local/bin/amtool

cat > /etc/alertmanager/alertmanager.yml <<'AM'
route:
  receiver: email
  group_by: ['alertname']
receivers:
  - name: email
    email_configs:
      - to: admin@platform.lab
        from: alertmanager@platform.lab
        smarthost: mail1.platform.lab:587
        auth_username: alertmanager@platform.lab
        auth_password: CHANGE_ME
        require_tls: true
        tls_config:
          insecure_skip_verify: true   # self-signed lab cert; false with real certs
AM
chown alertmanager:alertmanager /etc/alertmanager/alertmanager.yml

# VALIDATE before it's ever loaded:
amtool check-config /etc/alertmanager/alertmanager.yml

cat > /etc/systemd/system/alertmanager.service <<'UNIT'
[Unit]
Description=Alertmanager
After=network.target
[Service]
User=alertmanager
ExecStart=/usr/local/bin/alertmanager --config.file=/etc/alertmanager/alertmanager.yml --storage.path=/var/lib/alertmanager
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now alertmanager

firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=9093 protocol=tcp accept'
firewall-cmd --reload

# --- Test: fire a synthetic alert and watch it email ---
curl -s -XPOST http://127.0.0.1:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"EmailTest","severity":"critical"}}]'

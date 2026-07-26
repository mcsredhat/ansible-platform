#!/usr/bin/env bash
# =============================================================================
# mail_exporter.sh — CLI equivalent of `mail_exporter` (mail observability)
# Mirrors: roles/mail_exporter/tasks/main.yml — verified against source.
# Run as root (mail1).
# =============================================================================

VER=0.6.0
useradd -r -s /sbin/nologin postfix_exporter 2>/dev/null || true
usermod -aG postfix postfix_exporter        # for showq access

cd /tmp
curl -LO "https://github.com/Hsn723/postfix_exporter/releases/download/v${VER}/postfix_exporter_${VER}_linux_amd64.tar.gz"
tar xzf "postfix_exporter_${VER}_linux_amd64.tar.gz"
install -m0755 postfix_exporter /usr/local/bin/postfix_exporter

dnf -y install acl
# ACLs for BOTH the exporter AND promtail (Loki shipping) — maillog is 0600 root:
setfacl -m u:postfix_exporter:r /var/log/maillog
setfacl -m u:promtail:r /var/log/maillog 2>/dev/null || true

# Re-apply the ACL after logrotate rotates the file (a fresh file loses the ACL):
cat > /etc/logrotate.d/maillog-exporter-acl <<'CF'
# Re-apply the exporter ACL after maillog rotation
/var/log/maillog {
  postrotate
    /usr/bin/setfacl -m u:postfix_exporter:r /var/log/maillog || true
    /usr/bin/setfacl -m u:promtail:r /var/log/maillog || true
  endscript
}
CF

cat > /etc/systemd/system/postfix_exporter.service <<'UNIT'
[Unit]
Description=Postfix Exporter
After=network.target postfix.service
[Service]
User=postfix_exporter
ExecStart=/usr/local/bin/postfix_exporter --postfix.logfile_path=/var/log/maillog --postfix.showq_path=/var/spool/postfix/public/showq
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload

firewall-cmd --permanent --add-port=9154/tcp     # postfix_exporter
firewall-cmd --permanent --add-port=11334/tcp    # rspamd metrics (native)
firewall-cmd --reload

systemctl enable --now postfix_exporter

curl -s localhost:9154/metrics | grep -c postfix
# rspamd already exposes /metrics natively on :11334 (see mail_rspamd.sh)

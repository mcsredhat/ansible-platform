#!/usr/bin/env bash
# =============================================================================
# mail_rspamd.sh — CLI equivalent of `mail_rspamd` (spam filtering + DKIM)
# Mirrors: roles/mail_rspamd/tasks/main.yml — verified against source.
# Run as root (mail1).
# =============================================================================

cat > /etc/yum.repos.d/rspamd.repo <<'REPO'
[rspamd]
name=Rspamd stable repository
baseurl=https://rspamd.com/rpm-stable/centos-$releasever/$basearch/
gpgcheck=1
gpgkey=https://rspamd.com/rpm-stable/gpg.key
enabled=1
REPO

# --- THE KEY GOTCHA: RHEL 9's default crypto policy disallows SHA1 signatures,
# and Rspamd's repo key uses SHA1 — `dnf install` fails to import the key
# without this. Temporarily allow LEGACY crypto, install, then RESTORE
# whatever policy was active before (don't leave the system in LEGACY mode):
ORIG_POLICY=$(update-crypto-policies --show)
if [ "$ORIG_POLICY" != "LEGACY" ]; then
  update-crypto-policies --set LEGACY
fi

dnf -y install rspamd redis

if [ "$ORIG_POLICY" != "LEGACY" ]; then
  update-crypto-policies --set "$ORIG_POLICY"
fi

systemctl enable --now redis    # rspamd uses redis for stats/greylisting/ratelimit

# DKIM — key + DNS record generated AS THE _rspamd USER (not root), idempotent
# (skip if the key file already exists):
mkdir -p /var/lib/rspamd/dkim
chown _rspamd:_rspamd /var/lib/rspamd/dkim
chmod 0750 /var/lib/rspamd/dkim
if [ ! -f /var/lib/rspamd/dkim/platform.lab.mail.key ]; then
  sudo -u _rspamd rspamadm dkim_keygen -s mail -d platform.lab \
    -k /var/lib/rspamd/dkim/platform.lab.mail.key \
    > /var/lib/rspamd/dkim/platform.lab.mail.txt
fi
chown _rspamd:_rspamd /var/lib/rspamd/dkim/platform.lab.mail.key
chmod 0640 /var/lib/rspamd/dkim/platform.lab.mail.key
cat /var/lib/rspamd/dkim/platform.lab.mail.txt   # publish this TXT at mail._domainkey.platform.lab

# Config modules — NOTE: no worker-proxy.inc is deployed. Rspamd's stock RPM
# already ships a working milter/proxy worker on the default port (11332),
# which is what Postfix's smtpd_milters points at.
mkdir -p /etc/rspamd/local.d
cat > /etc/rspamd/local.d/dkim_signing.conf <<'CF'
domain {
  platform.lab {
    path = "/var/lib/rspamd/dkim/platform.lab.mail.key";
    selector = "mail";
  }
}
CF
cat > /etc/rspamd/local.d/worker-controller.inc <<'CF'
bind_socket = "*:11334";
password = "CHANGE_ME";
secure_ip = "127.0.0.1";
secure_ip = "192.168.1.0/24";
CF
chown -R root:_rspamd /etc/rspamd/local.d
chmod 0640 /etc/rspamd/local.d/*.conf /etc/rspamd/local.d/*.inc

firewall-cmd --permanent --add-port=11334/tcp
firewall-cmd --reload

systemctl enable --now rspamd

# --- Operating ---
rspamadm configtest
curl -s http://127.0.0.1:11334/metrics | head -3

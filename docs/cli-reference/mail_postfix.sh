#!/usr/bin/env bash
# =============================================================================
# mail_postfix.sh — CLI equivalent of `mail_postfix` (the MTA)
# Mirrors: roles/mail_postfix/tasks/main.yml — verified against source.
# Run as root (mail1). Virtual mailboxes are owned by a dedicated `vmail`
# system user (uid 5000) — NOT stored under root.
# =============================================================================

dnf -y install postfix postfix-pgsql cyrus-sasl cyrus-sasl-plain

groupadd -g 5000 vmail 2>/dev/null || true
useradd -u 5000 -g vmail -m -d /var/mail/vhosts -s /sbin/nologin -r vmail 2>/dev/null || true
mkdir -p /var/mail/vhosts
chown vmail:vmail /var/mail/vhosts
chmod 0770 /var/mail/vhosts

# THREE lookup maps — domains, mailboxes, AND aliases (all three needed):
cat > /etc/postfix/pgsql-virtual-mailbox-domains.cf <<'CF'
user = mailuser
password = CHANGE_ME
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s'
CF
cat > /etc/postfix/pgsql-virtual-mailbox-maps.cf <<'CF'
user = mailuser
password = CHANGE_ME
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s'
CF
cat > /etc/postfix/pgsql-virtual-alias-maps.cf <<'CF'
user = mailuser
password = CHANGE_ME
hosts = 127.0.0.1
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s'
CF
chmod 0640 /etc/postfix/pgsql-virtual-*.cf
chown root:postfix /etc/postfix/pgsql-virtual-*.cf

postconf -e "virtual_mailbox_domains = pgsql:/etc/postfix/pgsql-virtual-mailbox-domains.cf"
postconf -e "virtual_mailbox_maps = pgsql:/etc/postfix/pgsql-virtual-mailbox-maps.cf"
postconf -e "virtual_alias_maps = pgsql:/etc/postfix/pgsql-virtual-alias-maps.cf"
postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
# Rspamd's DEFAULT proxy/milter worker (not a custom config — it ships this way):
postconf -e "smtpd_milters = inet:127.0.0.1:11332"
postconf -e "non_smtpd_milters = inet:127.0.0.1:11332"
postconf -e "milter_protocol = 6"
postconf -e "milter_default_action = accept"
postconf -e "mynetworks = 127.0.0.0/8 [::1]/128 192.168.1.0/24"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

# Enable submission (587) + smtps (465) in master.cf — uncomment the stock
# entries or add them (both need smtpd_sasl_auth_enable=yes, smtpd_tls_security_level=encrypt)

firewall-cmd --permanent --add-service=smtp
firewall-cmd --permanent --add-service=smtp-submission
firewall-cmd --permanent --add-service=smtps
firewall-cmd --reload

systemctl enable --now postfix

# --- Test the flow end-to-end ---
dnf -y install swaks
swaks --to test@platform.lab --server 127.0.0.1
ls /var/mail/vhosts/platform.lab/test/new/
mailq

#!/usr/bin/env bash
# =============================================================================
# mail_dovecot.sh — CLI equivalent of `mail_dovecot` (IMAP/POP3 + delivery + auth)
# Mirrors: roles/mail_dovecot/tasks/main.yml — verified against source.
# Run as root (mail1).
# =============================================================================

dnf -y install dovecot dovecot-pgsql
dnf -y install checkpolicy policycoreutils
mkdir -p /etc/selinux/local

# Self-signed TLS for the lab (idempotent — skip if cert already exists)
mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
if [ ! -f /etc/pki/tls/certs/mail.crt ]; then
  openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
    -keyout /etc/pki/tls/private/mail.key -out /etc/pki/tls/certs/mail.crt \
    -subj "/CN=mail.platform.lab"
fi
chmod 0600 /etc/pki/tls/private/mail.key

# --- THE KEY GOTCHA: no SELinux boolean covers Dovecot -> PostgreSQL. The
# platform SHIPS a custom policy source file (dovecot_pgsql.te) and compiles
# it. Without this, Dovecot's PostgreSQL auth queries are silently denied
# under enforcing mode. Minimal .te content (adapt as your denials dictate):
cat > /etc/selinux/local/dovecot_pgsql.te <<'TE'
module dovecot_pgsql 1.0;
require {
    type dovecot_t;
    type postgresql_port_t;
    class tcp_socket name_connect;
}
allow dovecot_t postgresql_port_t:tcp_socket name_connect;
TE
cd /etc/selinux/local
checkmodule -M -m -o dovecot_pgsql.mod dovecot_pgsql.te
semodule_package -o dovecot_pgsql.pp -m dovecot_pgsql.mod
semodule -i dovecot_pgsql.pp

# PostgreSQL passdb — Dovecot authenticates against the mail DB
cat > /etc/dovecot/dovecot-sql.conf.ext <<'SQL'
driver = pgsql
connect = host=127.0.0.1 dbname=mailserver user=mailuser password=CHANGE_ME
password_query = SELECT email as user, password FROM virtual_users WHERE email='%u'
SQL
chown root:dovecot /etc/dovecot/dovecot-sql.conf.ext
chmod 0640 /etc/dovecot/dovecot-sql.conf.ext
# NOTE: store hashes WITH the {SHA512-CRYPT} prefix and OMIT default_pass_scheme.

# Maildir + LMTP (Postfix delivers via the dovecot-lmtp socket) — key bits
# that belong in /etc/dovecot/dovecot.conf / conf.d/*:
#   mail_location = maildir:/var/mail/vhosts/%d/%n
#   service lmtp { unix_listener /var/spool/postfix/private/dovecot-lmtp { ... } }
#   inet_listener imap { port = 143 }

firewall-cmd --permanent --add-service=imap
firewall-cmd --permanent --add-service=imaps
firewall-cmd --permanent --add-service=pop3
firewall-cmd --permanent --add-service=pop3s
firewall-cmd --reload

systemctl enable --now dovecot

# --- Test auth (the definitive check) ---
doveadm auth test test@platform.lab TestMailPass2026    # -> "auth succeeded"

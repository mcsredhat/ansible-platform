#!/usr/bin/env bash
# =============================================================================
# mail_roundcube.sh — CLI equivalent of `mail_roundcube` (webmail)
# Mirrors: roles/mail_roundcube/tasks/main.yml — verified against source.
# Run as root (mail1). NOTE: here php-fpm DOES run as `nginx` (unlike the
# WordPress web tier, which uses `webdata` — different roles, different identity).
# =============================================================================

dnf -y install nginx php-fpm php-pdo php-pgsql php-mbstring php-xml php-json \
               php-intl php-gd php-zip php-ldap

sudo -u postgres psql <<'SQL'
CREATE DATABASE roundcube;
CREATE USER roundcube WITH PASSWORD 'CHANGE_ME' ENCRYPTED;
GRANT ALL PRIVILEGES ON DATABASE roundcube TO roundcube;
SQL

VER=1.6.9
mkdir -p /var/www/roundcube
chown nginx:nginx /var/www/roundcube
if [ ! -f /var/www/roundcube/index.php ]; then
  curl -L -o /tmp/roundcube.tar.gz \
    "https://github.com/roundcube/roundcubemail/releases/download/${VER}/roundcubemail-${VER}-complete.tar.gz"
  tar xzf /tmp/roundcube.tar.gz -C /var/www/roundcube --strip-components=1
  chown -R nginx:nginx /var/www/roundcube
fi

# Load the schema AS the roundcube DB user (not postgres superuser), idempotent
# via a marker file (loading twice would error on existing tables):
if [ ! -f /var/lib/pgsql/.roundcube_schema_loaded ]; then
  PGPASSWORD='CHANGE_ME' psql -h 127.0.0.1 -U roundcube -d roundcube \
    -f /var/www/roundcube/SQL/postgres.initial.sql
  touch /var/lib/pgsql/.roundcube_schema_loaded
fi

# config.inc.php — key settings (des_key MUST be exactly 24 chars):
#   $config['db_dsnw'] = 'pgsql://roundcube:CHANGE_ME@127.0.0.1/roundcube';
#   $config['imap_host'] = 'ssl://127.0.0.1'; $config['imap_port'] = 993;
#   $config['smtp_host'] = 'tls://127.0.0.1'; $config['smtp_port'] = 587;
#   $config['des_key']  = 'rcmail-24char-changeme!!';   # exactly 24 chars

mkdir -p /var/www/roundcube/temp /var/www/roundcube/logs
chown nginx:nginx /var/www/roundcube/temp /var/www/roundcube/logs
chmod 0750 /var/www/roundcube/temp /var/www/roundcube/logs

# SELinux: nginx -> PostgreSQL/IMAP/SMTP, and writable temp/logs
setsebool -P httpd_can_network_connect on
chcon -R -t httpd_sys_rw_content_t /var/www/roundcube/temp /var/www/roundcube/logs

firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# THE KEY FIX: php-fpm defaults to `apache`, but nginx owns the files —
# run the pool as nginx, or Roundcube silently fails to load config:
sed -i 's/^user = apache/user = nginx/; s/^group = apache/group = nginx/' /etc/php-fpm.d/www.conf
sed -i 's/^listen.owner = apache/listen.owner = nginx/; s/^listen.group = apache/listen.group = nginx/' /etc/php-fpm.d/www.conf

systemctl enable --now php-fpm nginx

curl -sI http://127.0.0.1/ | head -1

#!/usr/bin/env bash
# =============================================================================
# mariadb.sh — CLI equivalent of the `mariadb` role (WordPress database)
# Mirrors: roles/mariadb/tasks/main.yml — verified line-by-line against source.
# Run as root (on data1).
# =============================================================================

dnf -y install mariadb-server mariadb python3-PyMySQL   # PyMySQL only needed if you'll use Ansible later
systemctl enable --now mariadb

# --- Platform config: bind, buffer pool sized to RAM, charset, binlog for PITR ---
# Buffer pool = 50% of host RAM (NOT a hardcoded value):
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
BUFFER_POOL=$(( RAM_MB / 2 ))
# server_id derived from the last octet of this node's IP (must be unique per node):
NODE_IP=$(hostname -I | awk '{print $1}')
SERVER_ID=${NODE_IP##*.}

cat > /etc/my.cnf.d/zz-platform.cnf <<MYCNF
[mysqld]
bind-address = 0.0.0.0
max_connections = 200
innodb_buffer_pool_size = ${BUFFER_POOL}M
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
# binary logging for point-in-time recovery
log_bin = /var/log/mariadb/binlog
server_id = ${SERVER_ID}
expire_logs_days = 7
MYCNF
systemctl restart mariadb     # role applies config via a handler + meta: flush_handlers before DB ops

# --- Idempotent "secure installation" via socket auth (no root password prompt) ---
mysql --socket=/var/lib/mysql/mysql.sock -e "DELETE FROM mysql.user WHERE User='';"
mysql --socket=/var/lib/mysql/mysql.sock -e "DROP DATABASE IF EXISTS test;"
mysql --socket=/var/lib/mysql/mysql.sock -e "FLUSH PRIVILEGES;"

# --- WordPress database + network-scoped user (web subnet only, not '%') ---
mysql --socket=/var/lib/mysql/mysql.sock -e \
  "CREATE DATABASE IF NOT EXISTS wordpress CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql --socket=/var/lib/mysql/mysql.sock -e \
  "CREATE USER IF NOT EXISTS 'wp_user'@'192.168.1.%' IDENTIFIED BY 'CHANGE_ME';"
mysql --socket=/var/lib/mysql/mysql.sock -e \
  "GRANT ALL PRIVILEGES ON wordpress.* TO 'wp_user'@'192.168.1.%';"
mysql --socket=/var/lib/mysql/mysql.sock -e "FLUSH PRIVILEGES;"

# --- Firewall: web subnet only (SELinux note: 3306 is mysqld_port_t by default,
#     nothing to relabel unless you move MariaDB to a non-standard port) ---
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=3306 protocol=tcp accept'
firewall-cmd --reload

# --- Operating ---
mysql -e "SHOW DATABASES;"
mysql -e "SELECT User,Host FROM mysql.user;"
mysqladmin status

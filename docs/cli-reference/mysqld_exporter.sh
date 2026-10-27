#!/usr/bin/env bash
# =============================================================================
# mysqld_exporter.sh — CLI equivalent of `mysqld_exporter`
# Mirrors: roles/mysqld_exporter/tasks/main.yml — verified against source.
# Run as root (data1).
# =============================================================================

VER=0.15.1
useradd -r -s /sbin/nologin mysqld_exporter 2>/dev/null || true

# Least-privilege MySQL account, created via the LOCAL SOCKET (no password
# prompt / no network exposure needed for account creation):
mysql --socket=/var/lib/mysql/mysql.sock -e \
  "CREATE USER IF NOT EXISTS 'exporter'@'localhost' IDENTIFIED BY 'CHANGE_ME';"
mysql --socket=/var/lib/mysql/mysql.sock -e \
  "GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'exporter'@'localhost';"

# Credentials file — root-readable ONLY (mode 0400), owned by the exporter user
cat > /etc/.mysqld_exporter.cnf <<'CNF'
[client]
user = exporter
password = CHANGE_ME
host = localhost
CNF
chown mysqld_exporter:mysqld_exporter /etc/.mysqld_exporter.cnf
chmod 0400 /etc/.mysqld_exporter.cnf

cd /tmp
curl -LO "https://github.com/prometheus/mysqld_exporter/releases/download/v${VER}/mysqld_exporter-${VER}.linux-amd64.tar.gz"
tar xzf "mysqld_exporter-${VER}.linux-amd64.tar.gz"
install -m0755 "mysqld_exporter-${VER}.linux-amd64/mysqld_exporter" /usr/local/bin/mysqld_exporter

cat > /etc/systemd/system/mysqld_exporter.service <<'UNIT'
[Unit]
Description=MySQLd Exporter
After=network.target mariadb.service
[Service]
User=mysqld_exporter
Environment=MYSQLD_EXPORTER_CONFIG=/etc/.mysqld_exporter.cnf
ExecStart=/usr/local/bin/mysqld_exporter --config.my-cnf=/etc/.mysqld_exporter.cnf
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now mysqld_exporter

# Firewall — ONLY obs1 may scrape
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.50.1.41 port port=9104 protocol=tcp accept'
firewall-cmd --reload

curl -s localhost:9104/metrics | head -5

#!/usr/bin/env bash
# =============================================================================
# tuning.sh — CLI equivalent of the `tuning` role (performance baseline)
# Mirrors: roles/tuning/tasks/main.yml — verified line-by-line against source.
# Run as root.
# =============================================================================

dnf -y install tuned
systemctl enable --now tuned

# Idempotent profile switch — only apply if NOT already the active profile
# (mirrors the same idempotence pattern used for php_fpm's dnf module):
ACTIVE=$(tuned-adm active 2>/dev/null)
if ! echo "$ACTIVE" | grep -q "throughput-performance"; then
  tuned-adm profile throughput-performance
fi
tuned-adm active                              # confirm

# Transparent Huge Pages — disabled via a proper oneshot systemd unit
# (NOT a raw `echo` at boot, which wouldn't survive reboot):
cat > /etc/systemd/system/disable-thp.service <<'UNIT'
[Unit]
Description=Disable Transparent Huge Pages
After=sysinit.target local-fs.target
Before=mariadb.service redis.service

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now disable-thp.service

# Resource limits
cat > /etc/security/limits.d/99-platform.conf <<'LIMITS'
* soft nofile 65535
* hard nofile 65535
LIMITS

# Performance sysctls
cat > /etc/sysctl.d/90-performance.conf <<'SYSCTL'
vm.swappiness = 10
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
SYSCTL
sysctl --system

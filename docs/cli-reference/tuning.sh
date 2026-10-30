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
# Profile: lab KVM guests use virtual-guest; bare metal uses throughput-performance
PROFILE=virtual-guest
ACTIVE=$(tuned-adm active 2>/dev/null)
if ! echo "$ACTIVE" | grep -q "$PROFILE"; then
  tuned-adm profile "$PROFILE"
fi
tuned-adm active                              # confirm

# Transparent Huge Pages — disabled via a proper oneshot systemd unit
# (NOT a raw `echo` at boot, which wouldn't survive reboot):
cat > /etc/systemd/system/disable-thp.service <<'UNIT'
[Unit]
Description=Disable Transparent Huge Pages (THP)
DefaultDependencies=no
After=sysinit.target local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled; echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=basic.target
UNIT
systemctl daemon-reload
systemctl enable --now disable-thp.service

# Resource limits (login sessions only; systemd services need LimitNOFILE=)
cat > /etc/security/limits.d/90-tuning.conf <<'LIMITS'
*     soft    nofile    65535
*     hard    nofile    65535
*     soft    nproc     16384
*     hard    nproc     16384
root  soft    nofile    65535
root  hard    nofile    65535
LIMITS

# Performance sysctls: vm.* belongs to tuned; fs.file-max and somaxconn stay at
# the kernel default. Port range sits above every platform listener (highest 11334).
cat > /etc/sysctl.d/95-tuning.conf <<'SYSCTL'
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 12000 65535
SYSCTL
sysctl --system

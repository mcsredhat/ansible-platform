#!/usr/bin/env bash
# =============================================================================
# base.sh — CLI equivalent of the `base` role (foundation for every node)
# Mirrors: roles/base/tasks/main.yml — verified line-by-line against source.
# Run as root.
# =============================================================================

# 1. Identity
hostnamectl set-hostname web1.platform.lab

# /etc/hosts rendered from one platform map (unsafe_writes because /etc/hosts
# is a bind-mount in containers — needed for molecule, harmless on real hosts):
cat >> /etc/hosts <<'HOSTS'
10.50.1.10  vip.platform.lab app.platform.lab
10.50.1.11  edge1.platform.lab edge1
10.50.1.21  web1.platform.lab web1
10.50.1.31  data1.platform.lab data1
10.50.1.41  obs1.platform.lab obs1
10.50.1.51  mail1.platform.lab mail1
HOSTS

# 2. Repos — CodeReady Builder (RHEL subscription-manager) + EPEL
subscription-manager repos --enable codeready-builder-for-rhel-9-x86_64-rpms
dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm

# 3. Base packages — allowerasing resolves the curl-minimal vs curl conflict
#    that shows up on minimal/container images:
dnf -y install vim curl wget git jq tar rsync chrony firewalld --allowerasing

# 4. Time
timedatectl set-timezone Europe/Paris
systemctl enable --now chronyd
chronyc sources

# 5. Static networking via NetworkManager (nmcli) — IMPORTANT: this is
#    idempotent (no-op if already at the target IP), but the FIRST DHCP->static
#    conversion can drop your SSH session. Run from console for the first node,
#    or accept one reconnect.
#
# >>> SET THIS per node before running — example below is web1's address: <<<
#   edge1=10.50.1.11  edge2=10.50.1.12  web1=10.50.1.21  web2=10.50.1.22
#   data1=10.50.1.31  obs1=10.50.1.41   mail1=10.50.1.51
NODE_IP=10.50.1.21/24

IFACE=$(nmcli -t -f DEVICE,STATE device | awk -F: '$2=="connected"{print $1; exit}')
nmcli connection modify "$IFACE" \
  ipv4.addresses "$NODE_IP" \
  ipv4.gateway 10.50.1.254 \
  ipv4.dns 10.50.1.254 \
  ipv4.method manual \
  802-3-ethernet.mtu 1230    # lab only (VXLAN over Tailscale); omit elsewhere = "auto"
nmcli connection up "$IFACE"     # applies immediately — may briefly drop the connection
ip link show "$IFACE" | grep -o 'mtu [0-9]*'   # expect: mtu 1230

# 6. SELinux enforcing (targeted policy)
setenforce 1
sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config

# 7. Firewall on
systemctl enable --now firewalld
firewall-cmd --state

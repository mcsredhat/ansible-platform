#!/usr/bin/env bash
# =============================================================================
# keepalived.sh — CLI equivalent of the `keepalived` role (floating VIP / HA)
# Mirrors: roles/keepalived/tasks/main.yml — verified line-by-line against source.
# Run as root (edge1/edge2). edge1=MASTER (priority 150), edge2=BACKUP (100).
# =============================================================================

dnf -y install keepalived

# Health-check script — keepalived drops priority (-60 weight) if nginx dies,
# triggering VRRP failover to the peer.
cat > /etc/keepalived/chk_nginx.sh <<'CHECK'
#!/bin/bash
systemctl is-active --quiet nginx
CHECK
chmod 0755 /etc/keepalived/chk_nginx.sh

# Detect this node's interface + IP (the real template does this dynamically)
IFACE=$(ip route show default | awk '/default/{print $5; exit}')
MY_IP=$(ip -4 addr show "$IFACE" | awk '/inet /{print $2}' | cut -d/ -f1)

# IMPORTANT: the platform uses UNICAST VRRP (unicast_src_ip + unicast_peer),
# not multicast — more reliable across some network/cloud setups where
# multicast is filtered. Set STATE/PRIORITY per node:
#   edge1: STATE=MASTER  PRIORITY=150
#   edge2: STATE=BACKUP  PRIORITY=100
STATE=MASTER          # or BACKUP on the other edge node
PRIORITY=150          # or 100 on the other edge node
PEER_IP=192.168.1.12  # the OTHER edge node's IP (12 if you're 11, and vice versa)

cat > /etc/keepalived/keepalived.conf <<KACONF
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_nginx {
    script "/etc/keepalived/chk_nginx.sh"
    interval 2
    timeout 5
    fall 2
    rise 2
    weight -60
}

vrrp_instance VI_APP {
    state ${STATE}
    interface ${IFACE}
    virtual_router_id 51
    priority ${PRIORITY}
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass Pl4tf0rm
    }

    unicast_src_ip ${MY_IP}
    unicast_peer {
        ${PEER_IP}
    }

    virtual_ipaddress {
        192.168.1.10/24
    }

    track_script {
        chk_nginx
    }
}
KACONF
# NOTE: auth_pass is silently truncated to 8 chars by keepalived — keep it short
# and make sure BOTH edge nodes use the exact same value.

# Firewall — allow VRRP protocol (not a port; it's IP protocol 112) from the subnet,
# only if firewalld is actually active:
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 protocol value=vrrp accept'
  firewall-cmd --reload
fi

systemctl enable --now keepalived

# --- Operating: who holds the VIP right now? ---
ip addr show | grep 192.168.1.10        # only the MASTER (or a failed-over BACKUP) shows it
systemctl status keepalived
journalctl -u keepalived -f             # watch state transitions live (MASTER/BACKUP/FAULT)

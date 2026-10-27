# Role: keepalived

The floating VIP that makes the edge tier HA (00-architecture §4.6). edge1 holds the
VIP as MASTER; if edge1 (or its nginx) fails, edge2 takes `10.50.1.10` over within a
couple of seconds, so `https://app.platform.lab` keeps answering.

## What it does
- Installs **keepalived**, deploys a **unicast** VRRP config (no multicast needed).
- **Health-tracks nginx**: `chk_nginx.sh` checks the nginx master via `/run/nginx.pid`;
  if nginx dies, priority drops by 60 (MASTER 150 -> 90 < BACKUP 100) so the VIP moves
  even when the node is up but nginx is down.
- Opens **VRRP** in the firewall (daemon-tolerant: permanent always, immediate only
  when firewalld is live).

## Per-node vars (host_vars)
- edge1: `keepalived_state: MASTER`, `keepalived_priority: 150`
- edge2: defaults (`BACKUP`, `100`)

## Verify
```bash
# the VIP should live on edge1:
ansible edge1 -b -m shell -a "ip -4 addr show | grep 10.50.1.10"
# reach the site through the VIP:
curl -sk -D - -o /dev/null --resolve app.platform.lab:443:10.50.1.10 https://app.platform.lab/ | grep -iE 'HTTP/|x-backend'
# failover: stop nginx on edge1, VIP should jump to edge2:
ansible edge1 -b -m service -a "name=nginx state=stopped"
ansible edge2 -b -m shell -a "ip -4 addr show | grep 10.50.1.10"   # now here
ansible edge1 -b -m service -a "name=nginx state=started"            # recover
```

#!/usr/bin/env bash
# =============================================================================
# redis.sh — CLI equivalent of the `redis` role (shared cache — WP + Rspamd)
# Mirrors: roles/redis/tasks/main.yml — verified line-by-line against source.
# Run as root (on data1). Both web nodes (WP object cache) AND mail1 (Rspamd)
# depend on this Redis instance.
# =============================================================================

dnf -y install redis
REDIS_CONF=/etc/redis/redis.conf
NODE_IP=$(hostname -I | awk '{print $1}')

# Bind to loopback + this node's IP only (targeted line replacement, distro
# config paths preserved — NOT a full config rewrite):
sed -i "s/^bind .*/bind 127.0.0.1 ${NODE_IP}/" "$REDIS_CONF"
sed -i 's/^protected-mode .*/protected-mode yes/' "$REDIS_CONF"
sed -i "s/^#\?\s*requirepass .*/requirepass CHANGE_ME/" "$REDIS_CONF"
sed -i 's/^#\?\s*maxmemory .*/maxmemory 256mb/' "$REDIS_CONF"
sed -i 's/^#\?\s*maxmemory-policy .*/maxmemory-policy allkeys-lru/' "$REDIS_CONF"

# Disable ONLY FLUSHALL. FLUSHDB is deliberately KEPT — WordPress's object
# cache plugin needs it to clear its own DB. Don't disable CONFIG either
# (the role doesn't) — some tooling needs it for introspection.
if ! grep -q "ANSIBLE REDIS HARDENING" "$REDIS_CONF"; then
  cat >> "$REDIS_CONF" <<'HARDEN'
# BEGIN ANSIBLE REDIS HARDENING
rename-command FLUSHALL ""
# END ANSIBLE REDIS HARDENING
HARDEN
fi

systemctl enable --now redis

# Firewall — Redis from the platform subnet only (6379 is redis_port_t under
# SELinux by default — nothing to relabel unless you move the port)
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.50.1.0/24 port port=6379 protocol=tcp accept'
firewall-cmd --reload

# --- Operating ---
redis-cli -a CHANGE_ME ping                # -> PONG
redis-cli -a CHANGE_ME info memory
redis-cli -a CHANGE_ME monitor             # watch live commands (Ctrl-C to stop)

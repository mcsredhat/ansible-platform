#!/usr/bin/env bash
# =============================================================================
# nginx_edge.sh — CLI equivalent of `nginx_edge` (TLS + load-balanced reverse proxy)
# Mirrors: roles/nginx_edge/tasks/main.yml — verified line-by-line against source.
# Run as root (edge1/edge2). Depends on nginx_common running first.
# =============================================================================

mkdir -p /etc/pki/nginx /etc/pki/nginx/private
chmod 0700 /etc/pki/nginx/private

# Self-signed cert WITH a SAN (subjectAltName) covering the app name, VIP alias,
# and the actual VIP IP — modern browsers/clients require SAN, not just CN.
# `creates:`-style idempotence: skip if the cert already exists.
if [ ! -f /etc/pki/nginx/app.platform.lab.crt ]; then
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/pki/nginx/private/app.platform.lab.key \
    -out /etc/pki/nginx/app.platform.lab.crt \
    -days 825 -subj "/CN=app.platform.lab" \
    -addext "subjectAltName=DNS:app.platform.lab,DNS:vip.platform.lab,IP:192.168.1.10"
fi
chmod 0600 /etc/pki/nginx/private/app.platform.lab.key

# Upstream: least_conn load balancing with real failover tuning (not just a
# round-robin list) — 3 failures within 15s marks a backend down temporarily.
cat > /etc/nginx/conf.d/00-upstream.conf <<'UPSTREAM'
upstream app_backend {
    least_conn;
    server web1:8080 max_fails=3 fail_timeout=15s;
    server web2:8080 max_fails=3 fail_timeout=15s;
}
UPSTREAM

cat > /etc/nginx/conf.d/app.conf <<'VHOST'
server {
    listen 443 ssl;
    server_name app.platform.lab vip.platform.lab;
    ssl_certificate     /etc/pki/nginx/app.platform.lab.crt;
    ssl_certificate_key /etc/pki/nginx/private/app.platform.lab.key;
    include /etc/nginx/snippets/ssl-params.conf;
    include /etc/nginx/snippets/security-headers.conf;
    location / {
        proxy_pass http://app_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
VHOST

# SELinux: nginx must both relay (reverse-proxy) AND initiate outbound connections
setsebool -P httpd_can_network_relay on
setsebool -P httpd_can_network_connect on

nginx -t && systemctl enable --now nginx

# Firewall — only apply --immediate if firewalld is actually running (avoid
# an error on a host where it's masked/stopped):
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-service=http
  firewall-cmd --permanent --add-service=https
  firewall-cmd --reload
fi

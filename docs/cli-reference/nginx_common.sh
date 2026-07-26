#!/usr/bin/env bash
# =============================================================================
# nginx_common.sh — CLI equivalent of `nginx_common` (shared nginx baseline)
# Mirrors: roles/nginx_common/tasks/main.yml — verified against source.
# Run as root. Installed on BOTH web and edge tiers; vhosts come from the
# tier-specific roles (nginx_edge / wordpress), not from this one.
# =============================================================================

dnf -y install nginx

mkdir -p /etc/nginx/snippets
cat > /etc/nginx/snippets/ssl-params.conf <<'SSL'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
SSL
cat > /etc/nginx/snippets/security-headers.conf <<'HDR'
add_header X-Frame-Options SAMEORIGIN;
add_header X-Content-Type-Options nosniff;
add_header Referrer-Policy strict-origin-when-cross-origin;
HDR

# Baseline nginx.conf tuning (worker settings, body size headroom for WP media):
sed -i 's/^worker_processes .*/worker_processes auto;/' /etc/nginx/nginx.conf
sed -i 's/worker_connections .*/worker_connections 1024;/' /etc/nginx/nginx.conf
if grep -qE '^\s*#?\s*server_tokens' /etc/nginx/nginx.conf; then
  sed -i 's/^\s*#\?\s*server_tokens .*/    server_tokens off;/' /etc/nginx/nginx.conf
else
  sed -i '/http {/a \    server_tokens off;\n    client_max_body_size 64m;' /etc/nginx/nginx.conf
fi

# ALWAYS validate before it's ever active — a bad config is rejected, not applied:
nginx -t && systemctl enable --now nginx

# --- Operating ---
nginx -t
systemctl reload nginx
ss -tlnp | grep nginx

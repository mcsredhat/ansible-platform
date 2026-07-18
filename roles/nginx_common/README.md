# Role: nginx_common

The hardened nginx **baseline** (00-architecture §4.1), installed on **both** the web
and edge tiers. It deploys no vhosts itself — the `wordpress` (web) and `nginx_edge`
(edge) roles drop their server blocks into `conf.d/`.

## What it does
- Installs **nginx** (RHEL 9 AppStream).
- Deploys a tuned, validated `nginx.conf` (`worker_processes auto`, gzip, a
  forwarded-for log format, **`server_tokens off`**, `client_max_body_size 64m` for
  WP uploads). The template is `validate: nginx -t` — a bad config never activates.
- Ships reusable **snippets**: `security-headers.conf` and `ssl-params.conf`
  (TLS 1.2/1.3, modern ciphers), included by the tier vhosts.
- Enables + starts nginx; reloads (never hard-restarts) on config change.

## Deliberately NOT here
- **Vhosts / firewall ports** — the tier roles own those (web opens 80 from the edge
  subnet; edge opens 80/443 publicly).
- **SELinux booleans** — set where needed (`httpd_can_network_connect` in `php_fpm`
  for Redis, `httpd_use_nfs` in `nfs_client` for the uploads mount).

## Verify
```bash
nginx -t
systemctl is-active nginx
curl -sI localhost | head -n1      # 404 until a vhost lands — expected
```

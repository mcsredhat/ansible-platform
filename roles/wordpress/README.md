# Role: wordpress

The WordPress application (00-architecture §4.4) — the role that turns the platform
into a running site. Reconciled from the web1/web2 manual builds.

## What it does
- Installs **WP-CLI**, downloads **WordPress core**, templates a proxy-aware
  **`wp-config.php`** (DB on data1, **Redis via Predis**, identical **vault salts**,
  the `X-Forwarded-Proto` shim + https `WP_HOME`/`WP_SITEURL`).
- Labels **tcp/8080** `http_port_t`, deploys the **`:8080` vhost** with the blue/green
  `X-Backend` marker (`backend_label` host_var), a `/healthz` endpoint, FastCGI to the
  php-fpm socket, static caching, and deny rules for `.ht`/`.git`/`xmlrpc.php`.
- **Installs WordPress once** (`run_once`, guarded by `wp core is-installed` — both
  nodes share the DB) via WP-CLI, no browser/DNS.
- Installs + activates the **Redis Object Cache** plugin and enables the drop-in
  (per node — plugin files are local).
- Owns the tree as **webdata** (excluding the NFS uploads mount), sets
  `httpd_sys_content_t` / `httpd_sys_rw_content_t`, and `restorecon`s.
- Opens **8080** to the platform subnet, reloads nginx only after `nginx -t` passes.

## Required vault keys
`vault_mariadb_wp_pw` (already set), `vault_redis_pw` (already set),
`vault_wp_admin_pw`, and `vault_wp_salts` (8 keys). Add the last two to your vault.

## Apply order
After `php_fpm` (socket) and ideally after `nfs_client` is **not** yet applied on the
node, OR accept that `restorecon` skips the NFS mount. The vhost needs `nginx_common`
already present.

## Verify (on web1, then through the VIP)
```bash
curl -s -o /dev/null -w 'healthz: %{http_code}\n' http://127.0.0.1:8080/healthz   # 200
curl -sI -H 'X-Forwarded-Proto: https' http://127.0.0.1:8080/ | grep -i x-backend # web1-blue
wp redis status --path=/var/www/wordpress --allow-root                            # Connected
```

# Web tier: manual reference -> Ansible roles (mapping & divergences)

The web1/web2 manual builds (03-, 05-) are the blueprint for Phase 4. The Ansible
implementation reproduces their behaviour but **deliberately diverges** in a few
places to fit the platform invariants we already established in Phases 1-3.

## Step -> role mapping
| Manual step (web1/web2) | Ansible role |
|---|---|
| nginx install + tuned nginx.conf | `nginx_common` (done) |
| PHP 8.2 + extensions, FPM pool, socket | `php_fpm` |
| NFS uploads mount (boot-safe) | `nfs_client` |
| WordPress code, wp-config, vhost :8080, WP-CLI install | `wordpress` |
| edge TLS + load-balance + VIP | `nginx_edge` + `keepalived` (+ `haproxy`) |

## Deliberate divergences (manual -> ours, and why)
1. **App identity: `nginx` pinned to 980  ->  dedicated `webdata` 1980.**
   The manual repurposes the nginx account at UID 980 for everything (web server,
   FPM, files, NFS owner). We use a dedicated **`webdata` 1980** as the file/NFS
   identity (980 collided with the system GID auto-allocation range on data1, see
   Phase 3). So the **FPM pool runs as `webdata`**, while nginx stays its own user.
   Files use standard perms (0644/0755) so nginx reads static assets as "other";
   the FPM socket is group `nginx` so nginx can connect. Cleaner separation, no
   UID pinning, no cross-node rsync.

2. **NFS export path `/export/wordpress/uploads`  ->  `/srv/wordpress/uploads`.**
   Our `nfs_server` role (Phase 3) exports `/srv/wordpress/uploads`, so the client
   mounts that.

3. **Redis object cache added (absent in the manual).**
   We built Redis in Phase 3, so the web tier uses it: `php-pecl-redis` in
   `php_fpm`, `WP_REDIS_*` in wp-config, and the Redis Object Cache drop-in in
   `wordpress`. This needs **`httpd_can_network_connect`** (Redis 6379) *in addition
   to* the manual's `httpd_can_network_connect_db` (MariaDB 3306).

4. **Salts: fetch-once-then-rsync  ->  generated once, stored in vault, templated.**
   The control node is the single source of truth. Identical salts come from the
   vault, templated to both nodes - no node-to-node rsync, no "don't regenerate"
   footgun.

5. **WP install: manual `wp core install`  ->  guarded by `wp core is-installed`.**
   Both nodes hit the same DB, so the check is naturally idempotent: once web1
   installs, web2 sees "installed" and skips. Runs via WP-CLI, no browser/DNS.

6. **Blue/green marker `X-Backend`  ->  `backend_label` host_var.**
   `web1 -> web1-blue`, `web2 -> web2-green`, templated into the vhost.

## Carried over unchanged
Port **8080** backend (+ `semanage port http_port_t 8080`), the proxy-aware
`X-Forwarded-Proto` shim + https `WP_HOME`/`WP_SITEURL`, `httpd_sys_rw_content_t`
on wp-content, `nofail,_netdev` on the NFS fstab line, the `/healthz` endpoint,
and the deny rules for `.ht`/`.git`/`xmlrpc.php`.

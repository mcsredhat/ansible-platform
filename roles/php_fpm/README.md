# Role: php_fpm

PHP 8.2 FPM for the WordPress backend (00-architecture §4.2). Reconciled from the
web1/web2 manual builds (see `docs/reference/web-tier-ansible-mapping.md`).

## What it does
- Sets the **php:8.2** module stream and installs FPM + the WordPress extension set,
  including **`php-cli`** (manual gotcha: `php-fpm` alone has no `php` command) and
  Predis (pure-PHP, in the `wordpress` role) for the Redis object cache — **not** the EPEL phpredis extension, which is ABI-incompatible with the php:8.2 module stream.
- Configures the `[www]` pool to run as **`webdata` (1980)** — so anything PHP writes
  (especially NFS uploads) is owned by the shared identity that data1's export expects.
- Socket `/run/php-fpm/www.sock` is `listen.owner=webdata`, `listen.group=nginx`,
  mode `0660`, so **nginx can connect** while FPM runs as webdata.
- Flips both SELinux booleans PHP needs here: **`httpd_can_network_connect_db`**
  (MariaDB 3306) and **`httpd_can_network_connect`** (Redis 6379).

## Why webdata, not nginx-980
The manual pinned `nginx` to UID 980 and ran everything as it. We use a dedicated
`webdata` 1980 for files/NFS and let nginx stay its own user; static files are world-
readable (0644) so nginx serves them as "other", and the socket is group `nginx`.
Cleaner separation, and it matches the `nfs_server` export owner from Phase 3.

## Depends on / pairs with
- `nginx_common` (the web server that talks to this socket)
- `nfs_client` (sets `httpd_use_nfs` for the uploads mount)
- `wordpress` (deploys code + wp-config that uses this pool, DB, and Redis)

## Verify (on web1)
```bash
php -v                                 # 8.2.x
php -m | grep -E 'mysqlnd|opcache'     # core extensions present
id webdata                             # uid=1980
ls -l /run/php-fpm/www.sock            # webdata nginx, srw-rw----
getsebool httpd_can_network_connect_db httpd_can_network_connect   # both on
systemctl is-active php-fpm
```

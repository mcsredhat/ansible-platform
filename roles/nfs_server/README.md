# Role: nfs_server

Exports the shared `wp-content/uploads` directory (00-architecture §3.3) from the
`data` tier. Both web nodes mount it, so an upload on blue is instantly visible on
green — without it, media would silently diverge across the pool.

## What it does
- Installs **nfs-utils**.
- Creates the **webdata 980:980** group+user (the shared identity that must match on
  server and clients), then the export dir owned `webdata:webdata`, mode **2775**
  (setgid → new files inherit the group).
- SELinux: enables **`nfs_export_all_rw`**.
- Exports `{{ nfs_export_path }}` to the web subnet with **`rw,sync,no_subtree_check,root_squash`**
  via `/etc/exports.d/wordpress.exports`, reloaded with `exportfs -ra`.
- Firewall: opens the **nfs** service (NFSv4, port 2049).

## Why the UID/GID alignment matters
php-fpm on the web nodes runs as uid 980. With `root_squash`, only non-root writes
pass through as themselves — so files land owned by 980 on the server, and because
980 is `webdata` on BOTH ends, ownership stays coherent. Mismatched ids = permission
denied or files owned by `nobody`.

## Client side (later, in nfs_client/web role)
- Mount `data1:{{ nfs_export_path }}` at the WordPress uploads path.
- Set SELinux boolean **`httpd_use_nfs`** so php/nginx may read the mount.

## Verify (on data1)
```bash
exportfs -v
showmount -e localhost
ls -ld /srv/wordpress/uploads      # drwxrwsr-x webdata webdata
```

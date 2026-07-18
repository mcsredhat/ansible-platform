# Role: nfs_client

Mounts the shared `wp-content/uploads` export from data1 onto each web node
(00-architecture §4.3), the client half of the Phase 3 `nfs_server` role. Both
blue/green nodes write to the same media store, so an upload on either is visible
through both.

## What it does
- Installs **nfs-utils**.
- Ensures the **webdata 1980** identity exists (so the mount point is owned by the
  same uid the export expects — self-sufficient if run before `php_fpm`).
- Creates the mount point `webdata:webdata`, mode 2775.
- Sets the SELinux boolean **`httpd_use_nfs`** so php-fpm/nginx may read+write the
  NFS-backed docroot.
- Mounts `data1:/srv/wordpress/uploads` with **`_netdev,nofail`** and persists it to
  fstab — a down data1 can never strand a web node in emergency mode at boot.

## Apply order
Recommended **after** `wordpress` so the WP tree's `restorecon` runs on local files
before the NFS mount is laid over `uploads` (NFS contexts come from `httpd_use_nfs`,
not file labels). It's safe to run before too — it creates its own path — but the
post-wordpress order keeps SELinux relabeling clean.

## Verify (on web1)
```bash
df -h | grep uploads                 # data1:/srv/wordpress/uploads mounted
mount | grep uploads                 # nfs, _netdev,nofail
getsebool httpd_use_nfs              # on
touch /var/www/wordpress/wp-content/uploads/_t && ls -l $_ && rm -f $_   # webdata-owned
```

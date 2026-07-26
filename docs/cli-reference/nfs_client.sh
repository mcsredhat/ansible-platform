#!/usr/bin/env bash
# =============================================================================
# nfs_client.sh — CLI equivalent of the `nfs_client` role (mount shared uploads)
# Mirrors: roles/nfs_client/tasks/main.yml — verified line-by-line against source.
# Run as root (on web1/web2).
# =============================================================================

dnf -y install nfs-utils

# Shared identity must match the server exactly (uid/gid 1980)
groupadd -g 1980 webdata 2>/dev/null || true
useradd -u 1980 -g webdata -M -s /sbin/nologin -r webdata 2>/dev/null || true

# Mount point — note the real path is under wordpress/, not html/
mkdir -p /var/www/wordpress/wp-content/uploads
chown webdata:webdata /var/www/wordpress/wp-content/uploads
chmod 2775 /var/www/wordpress/wp-content/uploads

# SELinux: allow httpd/php to read/write NFS-mounted files
setsebool -P httpd_use_nfs on

# Mount + persist to fstab. IMPORTANT: nofail + _netdev — if data1 is down,
# this must NEVER drop the web node into emergency mode at boot.
mount -t nfs -o defaults,_netdev,nofail data1:/srv/wordpress/uploads /var/www/wordpress/wp-content/uploads
echo "data1:/srv/wordpress/uploads /var/www/wordpress/wp-content/uploads nfs defaults,_netdev,nofail 0 0" >> /etc/fstab

# Verify
mount | grep uploads
df -h /var/www/wordpress/wp-content/uploads

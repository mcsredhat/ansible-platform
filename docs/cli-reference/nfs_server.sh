#!/usr/bin/env bash
# =============================================================================
# nfs_server.sh — CLI equivalent of the `nfs_server` role (shared uploads export)
# Mirrors: roles/nfs_server/tasks/main.yml — verified line-by-line against source.
# Run as root (on data1). NOTE: NFS server needs real kernel modules — this is
# exactly why it can't run in a container (documented CI exclusion).
# =============================================================================

dnf -y install nfs-utils

# Shared identity: webdata uid/gid MUST match on server AND every client (1980)
groupadd -g 1980 webdata 2>/dev/null || true
useradd -u 1980 -g webdata -M -s /sbin/nologin -r webdata 2>/dev/null || true

# Export directory with setgid (new files inherit the webdata group)
mkdir -p /srv/wordpress/uploads
chown webdata:webdata /srv/wordpress/uploads
chmod 2775 /srv/wordpress/uploads

# SELinux: allow NFS read-write export
setsebool -P nfs_export_all_rw on

# Define the export. root_squash matters: it keeps a client-root user from
# owning files — php-fpm writes as uid 1980, which lines up with the dir
# owner on both ends, which is the entire point of the shared-identity pattern.
cat > /etc/exports.d/wordpress.exports <<'EXPORTS'
/srv/wordpress/uploads 10.50.1.0/24(rw,sync,no_subtree_check,root_squash)
EXPORTS
exportfs -rav
exportfs -s

systemctl enable --now nfs-server

# Firewall — the nfs SERVICE definition (covers nfs + rpc-bind + mountd together)
firewall-cmd --permanent --add-service=nfs
firewall-cmd --reload

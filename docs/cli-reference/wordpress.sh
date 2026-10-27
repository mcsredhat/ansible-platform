#!/usr/bin/env bash
# =============================================================================
# wordpress.sh — CLI equivalent of the `wordpress` role
# Mirrors: roles/wordpress/tasks/main.yml — verified line-by-line against source.
# Run as root (web1/web2). CORRECTION vs an earlier draft: the docroot is
# /var/www/wordpress (NOT /var/www/html), owned by webdata (uid 1980).
# =============================================================================

WP_PATH=/var/www/wordpress

# Shared identity (idempotent; same uid as php_fpm/nfs_client)
groupadd -g 1980 webdata 2>/dev/null || true
useradd -u 1980 -g webdata -M -s /sbin/nologin -r webdata 2>/dev/null || true

# WP-CLI
curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod 0755 /usr/local/bin/wp
# The role always invokes wp with a raised memory limit — do the same:
WP="php -d memory_limit=512M /usr/local/bin/wp"

mkdir -p "$WP_PATH"
chown webdata:webdata "$WP_PATH"
chmod 2775 "$WP_PATH"

# Download core — idempotent (skip if wp-settings.php already exists)
[ -f "$WP_PATH/wp-settings.php" ] || $WP core download --path="$WP_PATH" --force --allow-root

# wp-config.php: DB on data1 + Redis on data1 (Predis, no phpredis extension needed)
$WP config create --path="$WP_PATH" --allow-root \
  --dbname=wordpress --dbuser=wp_user --dbpass='CHANGE_ME' --dbhost=data1 \
  --extra-php <<'PHP'
define('WP_REDIS_HOST', 'data1');
define('WP_REDIS_PORT', 6379);
define('WP_REDIS_PASSWORD', 'CHANGE_ME');
PHP

# SELinux: label the backend port 8080 as http_port_t BEFORE nginx listens on it
semanage port -a -t http_port_t -p tcp 8080 2>/dev/null || \
  semanage port -m -t http_port_t -p tcp 8080

# Install — ONCE (both web nodes share the same DB, so guard by is-installed).
# --skip-email avoids WP trying (and failing) to send the "site is live" mail.
if ! $WP core is-installed --path="$WP_PATH" --allow-root 2>/dev/null; then
  $WP core install --path="$WP_PATH" --allow-root \
    --url=https://app.platform.lab --title="Platform Lab" \
    --admin_user=admin --admin_password='CHANGE_ME_ADMIN' \
    --admin_email=admin@platform.lab --skip-email
fi

# Redis object cache — Predis-based plugin, idempotent via file-exists guards
[ -f "$WP_PATH/wp-content/plugins/redis-cache/redis-cache.php" ] || \
  $WP plugin install redis-cache --activate --path="$WP_PATH" --allow-root
[ -f "$WP_PATH/wp-content/object-cache.php" ] || \
  $WP redis enable --path="$WP_PATH" --allow-root

# Ownership — everything EXCEPT the NFS-mounted uploads dir (that's owned by
# the NFS export/mount, not by this chown):
find "$WP_PATH" -path "$WP_PATH/wp-content/uploads" -prune -o -exec chown webdata:webdata {} +

# SELinux contexts: code is read-only httpd content; wp-content is writable
semanage fcontext -a -t httpd_sys_content_t "${WP_PATH}(/.*)?" 2>/dev/null || true
semanage fcontext -a -t httpd_sys_rw_content_t "${WP_PATH}/wp-content(/.*)?" 2>/dev/null || true
restorecon -R "$WP_PATH"

# Remove the distro default vhost (it would compete with the WordPress vhost)
rm -f /etc/nginx/conf.d/default.conf

# WordPress vhost — serves on :8080 for the edge to proxy to
cat > /etc/nginx/conf.d/wordpress.conf <<'VHOST'
server {
    listen 8080;
    server_name app.platform.lab _;
    root /var/www/wordpress;
    index index.php;
    location / { try_files $uri $uri/ /index.php?$args; }
    location ~ \.php$ {
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
VHOST
nginx -t && systemctl reload nginx

# Firewall — backend port reachable from the platform subnet only (the edge lives there)
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=10.50.1.0/24 port port=8080 protocol=tcp accept'
firewall-cmd --reload

# --- Operating ---
$WP core is-installed --path="$WP_PATH" --allow-root && echo "installed"
$WP plugin list --path="$WP_PATH" --allow-root

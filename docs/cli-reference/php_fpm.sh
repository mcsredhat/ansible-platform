#!/usr/bin/env bash
# =============================================================================
# php_fpm.sh — CLI equivalent of the `php_fpm` role (PHP 8.2 FPM pool)
# Mirrors: roles/php_fpm/tasks/main.yml — verified line-by-line against source.
# Run as root (web1/web2).
#
# CRITICAL CORRECTION vs an earlier draft of this file: the FPM pool runs as
# the shared `webdata` identity (uid 1980) — NOT `nginx`. `webdata` is the same
# uid used by the wordpress role and the NFS mount, so file ownership lines up
# across php-fpm, the docroot, and the NFS-shared uploads. nginx only needs
# GROUP access to the FPM socket (listen.group = nginx) to proxy to it.
# =============================================================================

# 1. PHP module stream — idempotent (only reset+enable if not already active)
STATE=$(dnf -y module list php --enabled 2>/dev/null)
if ! echo "$STATE" | grep -q "8.2 \[e\]"; then
  dnf -y module reset php
  dnf -y module enable php:8.2
fi

# 2. Install. NOTE php-cli is required explicitly — php-fpm alone does NOT
#    provide the `php` CLI binary (a real gotcha if you skip it).
#    NOTE: deliberately NO php-pecl-redis — EPEL's php-pecl-redis5 is built
#    against RHEL's base PHP 8.0 (php-api 20200930) and CONFLICTS with the
#    php:8.2 module stream. The wordpress role uses Predis (a pure-PHP client
#    bundled with the redis-cache plugin) instead — same Redis object cache,
#    zero ABI risk, no third-party repo needed.
dnf -y install php-fpm php-cli php-mysqlnd php-gd php-mbstring php-xml \
               php-intl php-opcache php-pecl-zip php-process

# 3. Shared identity: webdata (uid/gid 1980) — must match on this node AND data1/web peer
groupadd -g 1980 webdata 2>/dev/null || true
useradd -u 1980 -g webdata -M -s /sbin/nologin -r webdata 2>/dev/null || true

# 4. Pool: runs as webdata, socket group nginx (so nginx can reach it)
sed -i 's/^user = .*/user = webdata/'                     /etc/php-fpm.d/www.conf
sed -i 's/^group = .*/group = webdata/'                   /etc/php-fpm.d/www.conf
sed -i 's/^;\?listen.owner = .*/listen.owner = webdata/'  /etc/php-fpm.d/www.conf
sed -i 's/^;\?listen.group = .*/listen.group = nginx/'    /etc/php-fpm.d/www.conf
sed -i 's/^;\?listen.mode = .*/listen.mode = 0660/'       /etc/php-fpm.d/www.conf

# 5. SELinux: PHP must reach MariaDB (3306) AND Redis (6379) on data1
setsebool -P httpd_can_network_connect_db on
setsebool -P httpd_can_network_connect on

systemctl enable --now php-fpm

# --- Operating ---
php-fpm -t
php -v
php -m | grep -i "mysqlnd\|opcache"     # note: shows as "Zend OPcache" (case matters!)

# web1 — Corrected Reference Build (RHEL 9) — Blue Backend

The first application-tier node: **nginx on :8080 + PHP-FPM + WordPress**, behind the HA edge
(edge1/edge2) which terminates TLS and load-balances to it. No TLS/WAF here — those live at
the edge. Every fix from the live build is folded in. Tested on RHEL 9.7, nginx (appstream),
PHP-FPM 8.2, WordPress 6.x, enforcing SELinux.

> **Dependency:** WordPress needs the **database** and **shared uploads** from **data1
> (192.168.1.31)**, built separately. This file stands up web1's full web stack now; the two
> steps marked **⟂ NEEDS data1** (NFS mount, WordPress install) finish once data1 exists. The
> milestone you reach here is the expected **"Error establishing a database connection" (500)**
> — proof the whole path works, waiting only on the DB.

## IP plan & data flow

```
client ──TLS──> VIP 192.168.1.10 (edge1/edge2)  ──HTTP :8080──>  web1 192.168.1.21 (blue)
                                                 └─HTTP :8080──>  web2 192.168.1.22 (green)
                                                                    │  MySQL :3306 / NFS
                                                                    └──>  data1 192.168.1.31
```

## web-tier gotchas handled inline (the corrections)

1. **`php-fpm` does NOT install the `php` CLI** — add **`php-cli`**, or `php -v` and the salt step fail with "command not found".
2. **Port 8080** isn't in SELinux `http_port_t` by default → `semanage port -a -t http_port_t -p tcp 8080`.
3. **WordPress behind a TLS proxy** → trust `X-Forwarded-Proto` (set `$_SERVER['HTTPS']`) + pin `WP_HOME`/`WP_SITEURL` to `https://…`, or infinite http→https redirects.
4. **PHP → MariaDB on data1** → `setsebool -P httpd_can_network_connect_db 1`; **NFS uploads** → `setsebool -P httpd_use_nfs 1`.
5. **Pin `nginx` to a fixed UID/GID (980)** now — so it matches data1's NFS export owner and web2, avoiding upload-permission drift later.
6. **Identical auth salts** on web1/web2 or logins break across blue/green.
7. **`wp-content` must be writable** → `httpd_sys_rw_content_t` (code stays `httpd_sys_content_t`).
8. **NFS fstab needs `nofail`** so a data1 outage doesn't drop web1 into emergency mode at boot; `systemctl daemon-reload` after editing fstab.
9. **The pre-data1 `500` is expected** — validate `wp-config.php` with `php -l` to confirm it's the DB, not a config fault.

---

## 1. Base system

```bash
sudo -i
subscription-manager repos --enable "codeready-builder-for-rhel-9-$(arch)-rpms"
dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf clean all && dnf makecache
dnf -y update
dnf -y install chrony firewalld policycoreutils-python-utils vim curl tar jq

hostnamectl set-hostname web1
cat >> /etc/hosts <<'EOF'
192.168.1.10  vip.platform.lab
192.168.1.11  edge1.platform.lab edge1
192.168.1.12  edge2.platform.lab edge2
192.168.1.21  web1.platform.lab  web1
192.168.1.22  web2.platform.lab  web2
192.168.1.31  data1.platform.lab data1
192.168.1.41  obs1.platform.lab  obs1
EOF

NIC=$(ip -br a | awk '$1!="lo"{print $1; exit}'); echo "NIC=$NIC"
CON=$(nmcli -g NAME con show --active | head -1)
nmcli con mod "$CON" ipv4.addresses 192.168.1.21/24 ipv4.gateway 192.168.1.254 \
  ipv4.dns 192.168.1.254 ipv4.method manual
systemctl restart NetworkManager
nmcli con up "$CON"                      # reconnect on .21

systemctl enable --now chronyd firewalld
setenforce 1; sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
```

**Verify:** `hostname` → web1, `getenforce` → Enforcing, `ping -c1 192.168.1.10`.

---

## 2. Install nginx + PHP-FPM (incl. php-cli) + pin the nginx UID

```bash
# RHEL appstream nginx is fine for a backend (no WAF/HTTP3 needed)
dnf -y install nginx

# PHP 8.2 stream; NOTE php-cli — php-fpm alone does NOT give you the `php` command
dnf -y module reset php
dnf -y module enable php:8.2
dnf -y install php-fpm php-cli php-mysqlnd php-gd php-mbstring php-xml php-intl \
               php-opcache php-pecl-zip php-process
php -v          # must now report PHP 8.2.x  (this failed before php-cli was added)

# --- pin nginx to UID/GID 980 so it matches data1's NFS export + web2 (do this BEFORE chowns) ---
groupmod -g 980 nginx
usermod  -u 980 -g 980 nginx
chown -R nginx:nginx /var/lib/nginx /var/log/nginx
id nginx        # uid=980(nginx) gid=980(nginx)
```

> If UID/GID **980** is already taken on this box, pick another free number and use the **same**
> one on web2 and for data1's export owner. The exact number doesn't matter; matching does.
> If WordPress Site Health later flags a missing PHP extension, `dnf search php-<name>` + install.

---

## 3. Firewall + SELinux (port 8080, DB, NFS)

```bash
# backend port, only from the edge subnet
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=8080 protocol=tcp accept'
firewall-cmd --reload

semanage port -a -t http_port_t -p tcp 8080     # let nginx bind 8080
setsebool -P httpd_can_network_connect_db 1      # PHP -> MariaDB on data1
setsebool -P httpd_use_nfs 1                     # NFS-mounted uploads
```

**Verify:** `semanage port -l | grep -w http_port_t` lists `tcp ... 8080`;
`getsebool httpd_can_network_connect_db httpd_use_nfs` → both on.

---

## 4. PHP-FPM pool (run as nginx)

```bash
sed -i 's/^user = apache/user = nginx/'   /etc/php-fpm.d/www.conf
sed -i 's/^group = apache/group = nginx/' /etc/php-fpm.d/www.conf
sed -i 's#^;\?listen.owner =.*#listen.owner = nginx#' /etc/php-fpm.d/www.conf
sed -i 's#^;\?listen.group =.*#listen.group = nginx#' /etc/php-fpm.d/www.conf
sed -i 's#^;\?listen.mode =.*#listen.mode = 0660#'    /etc/php-fpm.d/www.conf

systemctl enable --now php-fpm
ls -l /run/php-fpm/www.sock        # owned nginx:nginx
```

---

## 5. nginx vhost on :8080 (proxy-aware + FastCGI)

```bash
mkdir -p /var/www/wordpress
rm -f /etc/nginx/conf.d/default.conf

cat > /etc/nginx/conf.d/wordpress.conf <<'EOF'
server {
    listen 8080;
    server_name app.platform.lab _;
    root  /var/www/wordpress;
    index index.php;

    add_header X-Backend "web1-blue" always;     # see which node served (LB demo)

    set_real_ip_from 192.168.1.0/24;
    real_ip_header   X-Forwarded-For;

    location = /healthz { default_type text/plain; return 200 "web1 ok\n"; }

    location / { try_files $uri $uri/ /index.php?$args; }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto;   # pass edge scheme to PHP
        fastcgi_read_timeout 60s;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ { expires 30d; access_log off; }
    location ~ /\.(ht|git) { deny all; }
    location = /xmlrpc.php  { deny all; }
}
EOF

nginx -t && systemctl enable --now nginx
curl -s -o /dev/null -w 'healthz: %{http_code}\n' http://127.0.0.1:8080/healthz   # 200
```

---

## 6. Deploy WordPress + wp-config (proxy-aware, points at data1)

```bash
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzf latest.tar.gz
cp -a wordpress/. /var/www/wordpress/
cp /var/www/wordpress/wp-config-sample.php /var/www/wordpress/wp-config.php

# --- DB connection (data1). Password MUST match data1's wp_user grant ---
sed -i "s/database_name_here/wordpress/"      /var/www/wordpress/wp-config.php
sed -i "s/username_here/wp_user/"             /var/www/wordpress/wp-config.php
sed -i "s/password_here/CHANGE_ME_strong_pw/" /var/www/wordpress/wp-config.php
sed -i "s/localhost/192.168.1.31/"            /var/www/wordpress/wp-config.php

# --- auth salts: fetch ONCE; the SAME block must end up on web2 (needs php-cli) ---
php -r '
$c=file_get_contents("/var/www/wordpress/wp-config.php");
$s=file_get_contents("https://api.wordpress.org/secret-key/1.1/salt/");
$c=preg_replace("/define\(\x27AUTH_KEY.*NONCE_SALT\x27,\s*\x27[^\x27]*\x27\);/s",$s,$c,1);
file_put_contents("/var/www/wordpress/wp-config.php",$c);
'

# --- proxy + URL settings: insert right after the <?php opening ---
sed -i "/^<?php/a \\
if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) \&\& \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') { \$_SERVER['HTTPS'] = 'on'; }\\
define('WP_HOME','https://app.platform.lab');\\
define('WP_SITEURL','https://app.platform.lab');" /var/www/wordpress/wp-config.php

# --- VALIDATE the sed surgery didn't break the file (do this every time) ---
php -l /var/www/wordpress/wp-config.php                      # "No syntax errors detected"
grep -E "WP_HOME|WP_SITEURL|HTTP_X_FORWARDED_PROTO" /var/www/wordpress/wp-config.php
```

> Keep this `wp-config.php` to reuse on web2 — the DB block and **salts must be identical**
> across blue/green. Easiest: rsync `/var/www/wordpress/` to web2 (same UID 980) so config and
> salts already match.

---

## 7. SELinux file contexts + ownership

```bash
chown -R nginx:nginx /var/www/wordpress         # nginx is UID 980 (pinned in step 2)

semanage fcontext -a -t httpd_sys_content_t    "/var/www/wordpress(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/wordpress/wp-content(/.*)?"
restorecon -Rv /var/www/wordpress

systemctl restart php-fpm nginx
```

---

## 8. Milestone verification (works now, before data1)

```bash
curl -s -o /dev/null -w 'healthz: %{http_code}\n' http://127.0.0.1:8080/healthz   # 200
curl -s http://127.0.0.1:8080/index.php | grep -iE 'database|establishing'        # the DB-error page
php -l /var/www/wordpress/wp-config.php                                            # no syntax errors

# from an edge node:  curl -s -o /dev/null -w '%{http_code}\n' http://192.168.1.21:8080/healthz   # 200
# end-to-end via the VIP:
curl -sk -o /dev/null -w 'via VIP: %{http_code}\n' --resolve app.platform.lab:443:192.168.1.10 'https://app.platform.lab/'
```

**Expected at this stage:** `healthz` = **200**, and via the VIP a **500** whose body is
"Error establishing a database connection". **That 500 is the success milestone** — it proves
client → VIP → edge → web1 → PHP-FPM → WordPress all work; only the DB hop (data1) is missing.
Two confirmations that it's *only* the DB:

- `grep` shows "Error establishing a database connection" (not a PHP fatal/blank page), and
- `php -l` reports no syntax errors in `wp-config.php` (the `sed` edits are valid).

The edge correctly passes the 500 through without retrying the other backend — `proxy_next_upstream`
only retries `502`/`503`/connect errors (backend *down*), not `500` (the app answered).

---

## 9. ⟂ NEEDS data1 — finish once the DB/NFS node exists

### 9a. NFS-mounted shared uploads (boot-safe)

```bash
dnf -y install nfs-utils
mkdir -p /var/www/wordpress/wp-content/uploads

# NOTE: 'nofail' so a down/absent data1 never drops this node to emergency mode at boot
echo '192.168.1.31:/export/wordpress/uploads  /var/www/wordpress/wp-content/uploads  nfs  defaults,_netdev,nofail  0 0' >> /etc/fstab
systemctl daemon-reload          # REQUIRED after editing fstab, or systemd uses the old version

# This only succeeds AFTER data1 exports the share. Until then, 'mount -a' returns
# "mount.nfs: No route to host" — that's expected (data1 isn't up); the nofail line keeps boot safe.
mount -a
df -h | grep uploads
chown 980:980 /var/www/wordpress/wp-content/uploads
restorecon -Rv /var/www/wordpress/wp-content/uploads      # NFS needs httpd_use_nfs=1 (step 3)
```

### 9b. Complete the WordPress install (WP-CLI — no browser/DNS needed)

Once data1's MariaDB has the `wordpress` DB and `wp_user` granted from `192.168.1.%`:

```bash
dnf -y install mariadb        # client, for the connectivity test
mysql -h 192.168.1.31 -u wp_user -pCHANGE_ME_strong_pw wordpress -e 'SELECT 1;'   # -> 1

# install WP-CLI and run the install non-interactively (avoids the browser + DNS entirely)
cd /var/www/wordpress
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp
wp core install \
  --url="https://app.platform.lab" --title="Platform Lab" \
  --admin_user="admin" --admin_password='CHANGE_ME_admin_pw' \
  --admin_email="admin@platform.lab" --skip-email --allow-root

wp post list --allow-root        # the default "Hello world!" post = install succeeded

# chown local files but SKIP the NFS mount: root_squash forbids chown there, and those files
# are already 980:980 via the export's anonuid — so 'chown -R' would error "Operation not permitted"
find /var/www/wordpress -path '*/wp-content/uploads' -prune -o -exec chown nginx:nginx {} +

# verify the live site:
curl -sk -o /dev/null -w 'via VIP: %{http_code}\n' --resolve app.platform.lab:443:192.168.1.10 'https://app.platform.lab/'   # 200
```

**Browser access (optional).** The site name `app.platform.lab` must resolve to the VIP — the
working `curl` above uses `--resolve` to fake it. To reach it from a browser, add
`192.168.1.10  app.platform.lab` to your DNS (192.168.1.254) or the hosts file of the machine
you browse from. On Windows, if the hosts entry seems ignored, the browser's **Secure DNS /
DNS-over-HTTPS** is bypassing it — disable it (Settings → Privacy → Secure DNS) and run
`ipconfig /flushdns`; check with `ping app.platform.lab`. Self-signed certs trigger a browser
warning — accept it. (WP-CLI above sidesteps all of this.)

After install, confirm WordPress emits **https** URLs (no redirect loop — the
`X-Forwarded-Proto`/`WP_HOME` work paying off), upload a media file, and confirm it lands in
data1's `/export/wordpress/uploads` as `980:980`.

---

## 10. Acceptance checklist

```bash
nginx -t && systemctl is-active nginx php-fpm firewalld         # active
getenforce                                                      # Enforcing
id nginx                                                        # uid=980 gid=980
php -v                                                          # 8.2.x (php-cli present)
semanage port -l | grep -w http_port_t | grep 8080             # 8080 labeled
getsebool httpd_can_network_connect_db httpd_use_nfs            # both on
ss -tlnp | grep ':8080'                                         # nginx listening
curl -s -o /dev/null -w 'healthz: %{http_code}\n' http://127.0.0.1:8080/healthz   # 200
php -l /var/www/wordpress/wp-config.php                         # no syntax errors
ls -Z /var/www/wordpress | head                                # httpd_sys_content_t
ls -Z /var/www/wordpress/wp-content                            # httpd_sys_rw_content_t
```

---

## Troubleshooting (everything hit on the web tier)

| Symptom | Cause | Fix |
|---|---|---|
| `php: command not found` / `php -v` fails | only `php-fpm` installed, not the CLI | `dnf -y install php-cli` (step 2) |
| nginx won't start: `bind() to 0.0.0.0:8080 failed (13)` | 8080 not in `http_port_t` | `semanage port -a -t http_port_t -p tcp 8080` (step 3) |
| via VIP `500`, body "Error establishing a database connection" | **expected** pre-data1; DB not reachable | bring up data1; it's not a fault — confirm with `php -l` (no syntax error) |
| blank page / PHP fatal instead of the DB-error page | `wp-config.php` broken by the `sed` edits | `php -l /var/www/wordpress/wp-config.php`; fix the offending insert |
| infinite redirect / "too many redirects" in browser | WP doesn't know it's behind TLS | the `X-Forwarded-Proto` shim + https `WP_HOME`/`WP_SITEURL` (step 6) |
| `mount.nfs: No route to host` | data1 isn't up yet (or NFS/ firewall down) | **expected before data1**; mount after data1 exports the share (9a) |
| "fstab modified, but systemd uses the old version" | systemd mount units stale | `systemctl daemon-reload` after editing fstab |
| node drops to emergency mode at boot | NFS line in fstab without `nofail`, server down | add `nofail,_netdev` (9a) |
| 502/504 from edge, `connect() to FPM failed (13)` | SELinux on the FPM socket / WP path | `restorecon -Rv /var/www/wordpress /run/php-fpm`; check `ausearch -m avc` for `httpd_t` |
| uploads fail: permission denied | wp-content not writable, or UID mismatch | `httpd_sys_rw_content_t` (step 7); pin nginx UID 980 (step 2) |
| uploads fail on NFS with SELinux AVC | `httpd_use_nfs` off | `setsebool -P httpd_use_nfs 1` (step 3) |
| logged-in users randomly logged out | salts differ between web1/web2 | identical salts on both (step 6) |
| `chown: Operation not permitted` on `wp-content/uploads` | it's the NFS mount (`root_squash`); root can't chown it | harmless — files are already 980:980; skip it with `-path '*/wp-content/uploads' -prune` (9b) |
| browser can't reach `app.platform.lab` | name doesn't resolve to the VIP | add `192.168.1.10 app.platform.lab` to DNS/hosts; on Windows disable browser Secure DNS + `ipconfig /flushdns` (9b) |
| can't run the install wizard (no browser / DNS) | — | use WP-CLI `wp core install` instead (9b) |
| WordPress Site Health: missing extension | extension not installed | `dnf search php-<name>` + install, restart php-fpm |

---

## Where this leaves the platform

web1 (blue) is a live backend — the edge VIP proxies to a real web server (currently the
expected DB-error `500` until data1 is up). Next:

- **data1 (192.168.1.31)** — MariaDB (the `wordpress` DB + `wp_user`@`192.168.1.%`), the NFS
  export owned **980:980** (matching web1's pinned nginx), and restic backups. This clears the
  500 and lets you finish web1 steps 9a/9b.
- **web2 (192.168.1.22, green)** — clone web1: same build, IP `.22`, `X-Backend "web2-green"`,
  nginx pinned to UID **980**, and the **same `/var/www/wordpress/`** (identical salts/wp-config)
  rsync'd from web1. Then the edge load-balances blue/green (watch `X-Backend` alternate) and you
  can test backend failover (stop nginx on web1 → all traffic to web2).
- **obs1 (192.168.1.41)** — Prometheus/Grafana scraping node/nginx/PHP-FPM/MariaDB exporters.
```

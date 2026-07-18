# web2 — Reference Build (RHEL 9) — Green Backend

The second application-tier node and the twin of web1: **nginx on :8080 + PHP-FPM + WordPress**,
behind the HA edge. web2 is a **serve-only clone** — the site is already installed in data1's
database, so web2 runs **no install**; it brings over web1's code and config (so salts match)
and connects to the same DB and the same NFS uploads share. Once it's up, the edge
load-balances blue/green. Tested on RHEL 9.7, nginx (appstream), PHP-FPM 8.2, enforcing SELinux.

> **Prereq:** data1 (MariaDB + NFS) is up and web1 is live (the site returns 200 through the VIP).
> You can SSH from web1 to web2 as root (`ssh-copy-id root@192.168.1.22` if needed).

## What differs from web1

1. hostname `web2`, IP `192.168.1.22`
2. `X-Backend "web2-green"` in the vhost
3. WordPress files **rsync'd from web1** (identical `wp-config.php` + salts) — **not** re-downloaded, **not** re-installed
4. **no `wp core install`** — the DB already has the installed site

Everything else (nginx, PHP-FPM, UID 980, SELinux, NFS) is identical to web1.

## clone gotchas handled inline

1. **Pin `nginx` to UID/GID 980 BEFORE the rsync**, so copied files (980:980 on web1) line up and match data1's export.
2. **rsync must EXCLUDE `wp-content/uploads`** — that's web1's shared NFS mount; copying it would duplicate the shared media locally (and then get hidden under web2's own mount).
3. **Identical salts** come automatically from rsyncing web1's `wp-config.php` — don't regenerate them.
4. **Don't run the WordPress install on web2** — it serves the same data1 DB, which is already installed.
5. **restorecon after rsync** — rsync doesn't carry SELinux contexts.

---

## 1. Base system

```bash
sudo -i
subscription-manager repos --enable "codeready-builder-for-rhel-9-$(arch)-rpms"
dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm
dnf clean all && dnf makecache
dnf -y update
dnf -y install chrony firewalld policycoreutils-python-utils vim curl tar jq

hostnamectl set-hostname web2
cat >> /etc/hosts <<'EOF'
192.168.1.10  vip.platform.lab  app.platform.lab
192.168.1.11  edge1.platform.lab edge1
192.168.1.12  edge2.platform.lab edge2
192.168.1.21  web1.platform.lab  web1
192.168.1.22  web2.platform.lab  web2
192.168.1.31  data1.platform.lab data1
192.168.1.41  obs1.platform.lab  obs1
EOF

NIC=$(ip -br a | awk '$1!="lo"{print $1; exit}'); echo "NIC=$NIC"
CON=$(nmcli -g NAME con show --active | head -1)
nmcli con mod "$CON" ipv4.addresses 192.168.1.22/24 ipv4.gateway 192.168.1.254 \
  ipv4.dns 192.168.1.254 ipv4.method manual
systemctl restart NetworkManager
nmcli con up "$CON"                      # reconnect on .22

systemctl enable --now chronyd firewalld
setenforce 1; sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
```

**Verify:** `hostname` → web2, `getenforce` → Enforcing, `ping -c1 192.168.1.31` (reach data1).

---

## 2. Install nginx + PHP-FPM (incl. php-cli) + pin the nginx UID

```bash
dnf -y install nginx

dnf -y module reset php
dnf -y module enable php:8.2
dnf -y install php-fpm php-cli php-mysqlnd php-gd php-mbstring php-xml php-intl \
               php-opcache php-pecl-zip php-process
php -v

# pin nginx to the SAME UID/GID as web1 + data1's export (do this BEFORE the rsync in step 6)
groupmod -g 980 nginx
usermod  -u 980 -g 980 nginx
chown -R nginx:nginx /var/lib/nginx /var/log/nginx
id nginx        # uid=980 gid=980  — must match web1
```

---

## 3. Firewall + SELinux (port 8080, DB, NFS)

```bash
firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=8080 protocol=tcp accept'
firewall-cmd --reload

semanage port -a -t http_port_t -p tcp 8080
setsebool -P httpd_can_network_connect_db 1
setsebool -P httpd_use_nfs 1
```

---

## 4. PHP-FPM pool (run as nginx)

```bash
sed -i 's/^user = apache/user = nginx/'   /etc/php-fpm.d/www.conf
sed -i 's/^group = apache/group = nginx/' /etc/php-fpm.d/www.conf
sed -i 's#^;\?listen.owner =.*#listen.owner = nginx#' /etc/php-fpm.d/www.conf
sed -i 's#^;\?listen.group =.*#listen.group = nginx#' /etc/php-fpm.d/www.conf
sed -i 's#^;\?listen.mode =.*#listen.mode = 0660#'    /etc/php-fpm.d/www.conf
systemctl enable --now php-fpm
ls -l /run/php-fpm/www.sock
```

---

## 5. nginx vhost on :8080 (green)

Identical to web1 except the backend marker.

```bash
mkdir -p /var/www/wordpress
rm -f /etc/nginx/conf.d/default.conf

cat > /etc/nginx/conf.d/wordpress.conf <<'EOF'
server {
    listen 8080;
    server_name app.platform.lab _;
    root  /var/www/wordpress;
    index index.php;

    add_header X-Backend "web2-green" always;     # <-- the only difference from web1

    set_real_ip_from 192.168.1.0/24;
    real_ip_header   X-Forwarded-For;

    location = /healthz { default_type text/plain; return 200 "web2 ok\n"; }

    location / { try_files $uri $uri/ /index.php?$args; }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php-fpm/www.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto;
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

## 6. Copy WordPress from web1 (identical config + salts)

```bash
# === run FROM web1 — exclude the uploads dir (it's the shared NFS mount, mounted separately on web2) ===
rsync -a --exclude='wp-content/uploads' /var/www/wordpress/ root@192.168.1.22:/var/www/wordpress/
```

```bash
# === back on web2 ===
php -l /var/www/wordpress/wp-config.php                 # "No syntax errors detected"
grep -E "WP_HOME|WP_SITEURL|192.168.1.31" /var/www/wordpress/wp-config.php   # same DB + URLs as web1
# salts match web1 because wp-config came from web1 (do NOT regenerate them)
```

> rsync as root preserves the 980:980 ownership from web1, which matches web2's pinned nginx —
> no chown needed for the code. `--exclude='wp-content/uploads'` keeps the shared media out
> (web2 mounts the same NFS export in step 8).

---

## 7. SELinux file contexts (rsync doesn't carry them)

```bash
semanage fcontext -a -t httpd_sys_content_t    "/var/www/wordpress(/.*)?"
semanage fcontext -a -t httpd_sys_rw_content_t "/var/www/wordpress/wp-content(/.*)?"
restorecon -Rv /var/www/wordpress
systemctl restart php-fpm nginx
```

---

## 8. Mount the shared NFS uploads (data1 is up now)

```bash
dnf -y install nfs-utils
mkdir -p /var/www/wordpress/wp-content/uploads
echo '192.168.1.31:/export/wordpress/uploads  /var/www/wordpress/wp-content/uploads  nfs  defaults,_netdev,nofail  0 0' >> /etc/fstab
systemctl daemon-reload
mount -a
df -h | grep uploads                                   # data1 export mounted
restorecon -Rv /var/www/wordpress/wp-content/uploads
```

> Both web nodes now read/write the **same** uploads share, so media uploaded via either is
> visible through both — essential for blue/green to serve one consistent site.

---

## 9. Verify web2 serves the installed site (no install needed)

```bash
# web2 reaches the same DB that web1 installed -> it serves the real site, not a 500/install
curl -s -o /dev/null -w 'healthz: %{http_code}\n' http://127.0.0.1:8080/healthz                # 200
# through the edge (which sets X-Forwarded-Proto), confirm web2 specifically answers:
curl -sk -D - -o /dev/null -H 'X-Forwarded-Proto: https' http://192.168.1.22:8080/ | grep -iE 'HTTP/|x-backend'   # 200, X-Backend: web2-green
```

(A direct `curl http://127.0.0.1:8080/` may 301 to https because `WP_HOME` is https — that's
correct; test with the `X-Forwarded-Proto: https` header or through the VIP.)

---

## 10. Blue/green load-balance + backend-failover tests

**Both backends serving** — hit the VIP repeatedly and watch `X-Backend` change:

```bash
for i in $(seq 8); do
  curl -sk -D - -o /dev/null --resolve app.platform.lab:443:192.168.1.10 https://app.platform.lab/ \
    | awk 'tolower($0) ~ /x-backend/ {print}'
done
# expect clean alternation: web1-blue, web2-green, web1-blue, web2-green, ...
# (least_conn sends each request to the now-idle backend, so they alternate)
```

**Backend failover** — stop one backend and confirm traffic shifts. **Check `X-Backend`, not
just the status code**: an all-200 loop alone can't tell "failover working" from "both backends
up" — you must see every response come from the *surviving* node while one is stopped.

```bash
# on web1:
systemctl stop nginx

# from the client — show the backend AND prove no 502s (run both):
for i in $(seq 6); do
  curl -sk -D - -o /dev/null --resolve app.platform.lab:443:192.168.1.10 https://app.platform.lab/ \
    | awk 'tolower($0) ~ /x-backend/ {print}'
done
# expect: EVERY line "web2-green" (web1 is down)
for i in $(seq 6); do
  curl -sk -o /dev/null -w '%{http_code} ' --resolve app.platform.lab:443:192.168.1.10 https://app.platform.lab/
done; echo
# expect: all 200 (no 502 — the edge marked web1 down via max_fails and routed to web2-green)

# recover:
systemctl start nginx
# re-run the load-balance loop above -> alternation resumes (web1-blue reappears)
```

The edge retries to the healthy backend because `proxy_next_upstream` includes
`error timeout http_502 http_503` and the upstream has `max_fails=3 fail_timeout=15s` — so a
down backend is bypassed within a few seconds, seamlessly. The **success signals** are: clean
blue/green alternation when both are up, and all-`web2-green`/all-200 when web1 is stopped.

---

## 11. Acceptance checklist

```bash
nginx -t && systemctl is-active nginx php-fpm firewalld         # active
id nginx                                                        # uid=980 gid=980 (matches web1)
php -l /var/www/wordpress/wp-config.php                         # no syntax errors
diff <(ssh root@192.168.1.21 'grep AUTH_KEY /var/www/wordpress/wp-config.php') \
     <(grep AUTH_KEY /var/www/wordpress/wp-config.php)          # empty = salts match web1
df -h | grep uploads                                            # NFS share mounted
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz   # 200
# both backends visible through the VIP (rerun the step-10 loop): web1-blue AND web2-green
```

---

## Troubleshooting (clone-specific)

| Symptom | Cause | Fix |
|---|---|---|
| copied files owned by wrong UID | nginx not pinned to 980 before rsync | pin UID 980 (step 2), re-rsync or `find -xdev -exec chown nginx:nginx {} +` |
| `wp-content/uploads` duplicated/huge on local disk | rsync didn't exclude the share | `--exclude='wp-content/uploads'` (step 6); remove the local copy, then mount NFS |
| logged-in users logged out when LB flips nodes | salts differ (wp-config regenerated, not copied) | rsync web1's `wp-config.php`; don't regenerate salts (step 6) |
| web2 shows install wizard / different site | web2 pointed at a different/empty DB | confirm `wp-config.php` DB host = 192.168.1.31 and creds match (step 6) |
| only one `X-Backend` value ever appears | other backend down, or edge stuck | check both nginx active; `least_conn` favors idle — generate more concurrent load |
| failover loop is all-200 but you can't tell if it failed over | status code alone can't distinguish failover from "both up" | check `X-Backend` while one node is stopped — every line should be the surviving node (step 10) |
| stopped web1 but requests still show `web1-blue` | edge still within `fail_timeout` / fewer than `max_fails` errors seen | wait a few seconds; the edge bypasses it after `max_fails=3` within `fail_timeout=15s` |
| 502 when one backend is stopped | upstream retry not kicking in | confirm edge `proxy_next_upstream` + `max_fails`/`fail_timeout` (edge `00-upstream.conf`/`app.conf`) |
| SELinux denials after rsync | contexts not restored | `restorecon -Rv /var/www/wordpress` (step 7) |
| `mount.nfs: No route to host` | data1 down/unreachable | check data1 `nfs-server` + firewall; `nofail` keeps web2 booting regardless |

---

## Where this leaves the platform

The application tier is now **redundant**: blue (web1) and green (web2) serve one shared
WordPress site — same DB on data1, same NFS uploads — behind the HA edge, which load-balances
and fails over between them. Five of six nodes done:

- ✅ edge1 ✅ edge2 ✅ web1 ✅ data1 ✅ web2 — ⬜ obs1

The last node, **obs1 (192.168.1.41)**, is observability: Prometheus scraping exporters
(node_exporter on every host, nginx/stub_status, php-fpm_exporter, mysqld_exporter), Grafana
dashboards, and Alertmanager — so you can see the load balancing, failovers, and resource use
across the whole platform you've built.

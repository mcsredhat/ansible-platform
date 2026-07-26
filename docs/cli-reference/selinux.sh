#!/usr/bin/env bash
# =============================================================================
# selinux.sh — SELinux operations reference (RHEL 9)
# SELinux isn't one role — it's woven through many (dovecot->postgres policy,
# php->db/redis booleans, etc.). This is the practical SELinux toolkit you'll
# actually use when troubleshooting "it works with SELinux permissive but not
# enforcing". Run as root.
# =============================================================================

# ---------------------------------------------------------------------------
# 1. State + mode
# ---------------------------------------------------------------------------
getenforce                       # Enforcing | Permissive | Disabled
sestatus                         # full status
setenforce 0                     # TEMPORARILY set permissive (until reboot) — for testing ONLY
setenforce 1                     # back to enforcing
# Permanent mode lives in /etc/selinux/config (SELINUX=enforcing)

# ---------------------------------------------------------------------------
# 2. Diagnosing denials (the #1 SELinux task)
# ---------------------------------------------------------------------------
# When something breaks under enforcing but works under permissive, it's an AVC:
ausearch -m avc -ts recent                    # recent denials
ausearch -m avc -ts recent | grep -i dovecot  # filter by process
journalctl -t setroubleshoot --since "10 min ago"   # human-readable explanations
sealert -a /var/log/audit/audit.log           # analyze all denials (needs setroubleshoot)

# ---------------------------------------------------------------------------
# 3. Booleans (toggle allowed behaviors — often the cleanest fix)
# ---------------------------------------------------------------------------
getsebool -a | grep httpd                     # list httpd-related booleans
# Examples the platform uses (php-fpm/nginx needing DB + redis network):
setsebool -P httpd_can_network_connect_db on  # allow web -> database
setsebool -P httpd_can_network_connect on     # allow web -> any network (redis, etc.)
# -P makes it persistent across reboots. Without -P it's temporary.

# ---------------------------------------------------------------------------
# 4. File contexts (when files are in a non-default location)
# ---------------------------------------------------------------------------
ls -Z /var/www/html                           # view contexts
semanage fcontext -a -t httpd_sys_content_t "/srv/myapp(/.*)?"   # add a context rule
restorecon -Rv /srv/myapp                     # apply contexts to files
restorecon -Rv /var/mail/vhosts               # (platform uses this after mail restores)

# ---------------------------------------------------------------------------
# 5. Ports (when a service uses a non-standard port)
# ---------------------------------------------------------------------------
semanage port -l | grep http                  # what ports a type is allowed
semanage port -a -t http_port_t -p tcp 8080   # allow nginx to bind :8080

# ---------------------------------------------------------------------------
# 6. Custom policy modules (the platform's dovecot->postgres case)
# ---------------------------------------------------------------------------
# When no boolean fits, build a policy from the denials:
ausearch -m avc -ts recent | audit2allow -M my_dovecot_pgsql   # generates .te + .pp
semodule -i my_dovecot_pgsql.pp               # install the compiled module
semodule -l | grep dovecot                    # confirm it's loaded
# The platform ships roles/mail_dovecot/files/dovecot_pgsql.te for exactly this:
#   checkmodule -M -m -o dovecot_pgsql.mod dovecot_pgsql.te
#   semodule_package -o dovecot_pgsql.pp -m dovecot_pgsql.mod
#   semodule -i dovecot_pgsql.pp

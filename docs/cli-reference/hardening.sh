#!/usr/bin/env bash
# =============================================================================
# hardening.sh — CLI equivalent of the `hardening` role (preventive security)
# Mirrors: roles/hardening/tasks/main.yml — verified line-by-line against source.
# Run as root.
# =============================================================================

# 1. SSH hardening (drop-in, VALIDATED before it's ever loaded — a bad config
#    can't be written because `validate: sshd -t -f %s` blocks a bad write)
cat > /tmp/00-hardening.conf <<'SSHD'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 4
ClientAliveInterval 300
ClientAliveCountMax 2
SSHD
sshd -t -f /tmp/00-hardening.conf && \
  mv /tmp/00-hardening.conf /etc/ssh/sshd_config.d/00-hardening.conf && \
  chmod 600 /etc/ssh/sshd_config.d/00-hardening.conf && \
  systemctl reload sshd

# 2. Account lockout (faillock)
cat > /etc/security/faillock.conf <<'FAILLOCK'
deny = 5
unlock_time = 900
fail_interval = 900
FAILLOCK
# Only touch authselect when needed (idempotent). rc=2 = no profile yet (cloud images).
# Roll back: list /var/lib/authselect/backups/, then authselect backup-restore <newest>
dnf install -y authselect sssd-client libpwquality
CURRENT=$(authselect current 2>/dev/null)
RC=$?
if [ "$RC" -eq 2 ]; then
  authselect select sssd with-faillock --force --backup="pre-hardening-$(date +%Y%m%dT%H%M%S)"
elif [ "$RC" -eq 0 ] && ! echo "$CURRENT" | grep -q with-faillock; then
  authselect enable-feature with-faillock
fi
faillock                                     # show failed attempts per user
faillock --user someuser --reset             # clear a user's lockout

# 3. Password quality (pwquality)
cat > /etc/security/pwquality.conf <<'PWQ'
minlen = 14
dcredit = -1
ucredit = -1
ocredit = -1
lcredit = -1
PWQ

# 4. Password aging + umask (login.defs — targeted line replacement)
sed -i 's/^#\?\s*PASS_MAX_DAYS\b.*/PASS_MAX_DAYS\t90/' /etc/login.defs
sed -i 's/^#\?\s*PASS_MIN_DAYS\b.*/PASS_MIN_DAYS\t1/'  /etc/login.defs
sed -i 's/^#\?\s*PASS_WARN_AGE\b.*/PASS_WARN_AGE\t7/'  /etc/login.defs
sed -i 's/^#\?\s*UMASK\b.*/UMASK\t\t027/'              /etc/login.defs

# 5. sudo command logging (drop-in, validated). NOTE the real directives are
#    log_year + log_host (timestamps + hostname in the log), not log_input/output:
cat > /etc/sudoers.d/10-logging <<'SUDO'
Defaults logfile="/var/log/sudo.log"
Defaults log_year, log_host
SUDO
chmod 0440 /etc/sudoers.d/10-logging
visudo -cf /etc/sudoers.d/10-logging     # validates syntax; sudo refuses to run if broken

# 6. Kernel sysctl hardening
cat > /etc/sysctl.d/90-hardening.conf <<'SYSCTL'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
fs.suid_dumpable = 0
SYSCTL
sysctl --system

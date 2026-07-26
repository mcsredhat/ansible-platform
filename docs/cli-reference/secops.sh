#!/usr/bin/env bash
# =============================================================================
# secops.sh — CLI equivalent of the `secops` role (security -> observability)
# Mirrors: roles/secops/tasks/main.yml — verified line-by-line against source.
# Run as root. (For raw SELinux ops see selinux.sh; for jails see fail2ban.sh.)
# The mission: security events shouldn't sit in a silo — expose them as metrics
# and forward them to logs so you can alert and dashboard on them.
# =============================================================================

# Container detection here is a BELT-AND-SUSPENDERS check — both the virt fact
# AND marker files (/run/.containerenv, /.dockerenv), because the virt fact
# alone didn't reliably detect podman in testing:
IN_CONTAINER=false
[ -f /run/.containerenv ] && IN_CONTAINER=true
[ -f /.dockerenv ] && IN_CONTAINER=true

mkdir -p /var/lib/node_exporter/textfile_collector

# ---------------------------------------------------------------------------
# 1. fail2ban -> metrics (currently-banned count per jail)
# ---------------------------------------------------------------------------
cat > /usr/local/bin/fail2ban-metrics.sh <<'SCRIPT'
#!/bin/bash
OUT=/var/lib/node_exporter/textfile_collector/fail2ban.prom
echo "# HELP fail2ban_banned_total Currently banned IPs per jail" > $OUT
echo "# TYPE fail2ban_banned_total gauge" >> $OUT
for jail in $(fail2ban-client status | sed -n 's/.*Jail list:\s*//p' | tr ',' ' '); do
  n=$(fail2ban-client status "$jail" | sed -n 's/.*Currently banned:\s*//p')
  echo "fail2ban_banned_total{jail=\"$jail\"} ${n:-0}" >> $OUT
done
SCRIPT
chmod 0755 /usr/local/bin/fail2ban-metrics.sh

cat > /etc/systemd/system/fail2ban-metrics.service <<'UNIT'
[Unit]
Description=Export fail2ban ban counts for Prometheus
[Service]
Type=oneshot
ExecStart=/usr/local/bin/fail2ban-metrics.sh
UNIT
cat > /etc/systemd/system/fail2ban-metrics.timer <<'UNIT'
[Unit]
Description=Run fail2ban-metrics every 5 minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
if [ "$IN_CONTAINER" = false ]; then
  systemctl enable --now fail2ban-metrics.timer
fi

# ---------------------------------------------------------------------------
# 2. AIDE -> metrics (did the last integrity check find changes?)
# ---------------------------------------------------------------------------
cat > /usr/local/bin/aide-metrics.sh <<'SCRIPT'
#!/bin/bash
OUT=/var/lib/node_exporter/textfile_collector/aide.prom
aide --check >/tmp/aide.out 2>&1; rc=$?
echo "# HELP aide_check_changed 1 if AIDE found filesystem changes" > $OUT
echo "# TYPE aide_check_changed gauge" >> $OUT
echo "aide_check_changed ${rc}" >> $OUT
SCRIPT
chmod 0755 /usr/local/bin/aide-metrics.sh

cat > /etc/systemd/system/aide-metrics.service <<'UNIT'
[Unit]
Description=Export AIDE integrity-check result for Prometheus
[Service]
Type=oneshot
ExecStart=/usr/local/bin/aide-metrics.sh
UNIT
cat > /etc/systemd/system/aide-metrics.timer <<'UNIT'
[Unit]
Description=Run aide-metrics daily
[Timer]
OnCalendar=daily
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
if [ "$IN_CONTAINER" = false ]; then
  systemctl enable --now aide-metrics.timer
fi

# ---------------------------------------------------------------------------
# 3. auditd -> journald/syslog forwarding (so promtail ships audit events to Loki)
#    The role LOCATES the audisp-syslog binary rather than assuming a path,
#    since it moves between RHEL minor versions:
# ---------------------------------------------------------------------------
dnf -y install audispd-plugins || true    # best-effort; needs internet

AUDISP_PATH=""
for p in /usr/sbin/audisp-syslog /sbin/audisp-syslog; do
  [ -x "$p" ] && AUDISP_PATH="$p" && break
done

if [ -n "$AUDISP_PATH" ]; then
  cat > /etc/audit/plugins.d/syslog.conf <<CF
active = yes
direction = out
path = ${AUDISP_PATH}
type = always
args = LOG_LOCAL6
format = string
CF
  chmod 0640 /etc/audit/plugins.d/syslog.conf
  systemctl restart auditd
else
  echo "audisp-syslog binary not found — skip syslog forwarding (package unavailable?)"
fi

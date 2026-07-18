#!/bin/bash
# Emit fail2ban ban counts as Prometheus metrics via the node_exporter
# textfile collector. No external exporter needed.
set -euo pipefail
PROM_DIR="/var/lib/node_exporter/textfile_collector"
PROM="${PROM_DIR}/fail2ban.prom"
TMP="$(mktemp)"

echo "# HELP fail2ban_banned_current Currently banned IPs per jail." >> "$TMP"
echo "# TYPE fail2ban_banned_current gauge" >> "$TMP"
echo "# HELP fail2ban_banned_total Total banned IPs per jail since fail2ban start." >> "$TMP"
echo "# TYPE fail2ban_banned_total counter" >> "$TMP"

# jail list from fail2ban-client
jails=$(/usr/bin/fail2ban-client status 2>/dev/null | /usr/bin/awk -F: '/Jail list/ {gsub(/[ \t]/,"",$2); print $2}' | /usr/bin/tr ',' ' ')
for jail in $jails; do
    status=$(/usr/bin/fail2ban-client status "$jail" 2>/dev/null || true)
    cur=$(echo "$status" | /usr/bin/awk '/Currently banned/ {print $NF}')
    tot=$(echo "$status" | /usr/bin/awk '/Total banned/ {print $NF}')
    cur=${cur:-0}; tot=${tot:-0}
    echo "fail2ban_banned_current{jail=\"$jail\"} $cur" >> "$TMP"
    echo "fail2ban_banned_total{jail=\"$jail\"} $tot" >> "$TMP"
done

/usr/bin/install -m 0644 "$TMP" "$PROM"
/usr/bin/rm -f "$TMP"

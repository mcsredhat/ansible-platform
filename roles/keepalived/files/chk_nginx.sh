#!/bin/bash
# Healthy if nginx is serving. Absolute paths (keepalived uses a minimal PATH).
# One retry absorbs the transient miss when keepalived starts before nginx has
# settled. Signals: systemd unit active, live :443 listener, or master pid alive.
for i in 1 2; do
    /usr/bin/systemctl is-active --quiet nginx && exit 0
    /usr/sbin/ss -lnt 2>/dev/null | /usr/bin/grep -q ':443 ' && exit 0
    if [ -f /run/nginx.pid ] && /bin/kill -0 "$(/bin/cat /run/nginx.pid)" 2>/dev/null; then
        exit 0
    fi
    [ "$i" -eq 1 ] && /usr/bin/sleep 1
done
exit 1

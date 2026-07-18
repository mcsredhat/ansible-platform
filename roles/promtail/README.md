# promtail
Ships logs to Loki from every node. Journald logs fleet-wide; nginx
access/error logs additionally on web + edge (via ACL grant, since promtail
runs as an unprivileged system user). Positions tracked in
`/var/lib/promtail` so restarts don't re-ship old log lines.

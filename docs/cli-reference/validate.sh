#!/usr/bin/env bash
# =============================================================================
# validate.sh — CLI equivalent of `validate.yml` (Phase 10 end-to-end health check)
# Mirrors: validate.yml — verified line-by-line against source. Read-only.
# =============================================================================

# ---------------------------------------------------------------------------
# EDGE tier (edge1/edge2) — keepalived + nginx + the VIP answers HTTPS
# ---------------------------------------------------------------------------
systemctl is-active keepalived nginx            # both -> active
curl -sk -o /dev/null -w "%{http_code}\n" https://192.168.1.10/    # -> 200/301/302/403

# ---------------------------------------------------------------------------
# WEB tier (web1/web2) — php-fpm + nginx + WordPress backend on :8080
# ---------------------------------------------------------------------------
systemctl is-active php-fpm nginx
# follow redirects, correct Host header (matches app.<domain>):
curl -sL -o /dev/null -w "%{http_code}\n" -H 'Host: app.platform.lab' http://127.0.0.1:8080/

# ---------------------------------------------------------------------------
# DATA tier (data1) — mariadb + redis active, NFS export present
# ---------------------------------------------------------------------------
systemctl is-active mariadb redis
exportfs -s                                     # non-empty output + rc=0 means the export is live

# ---------------------------------------------------------------------------
# OBS tier (obs1) — 4 services + ALL Prometheus targets up + compliance metric
# ---------------------------------------------------------------------------
systemctl is-active prometheus grafana-server loki alertmanager
UP=$(curl -s 'http://127.0.0.1:9090/api/v1/query?query=up')
echo "$UP" | jq -r '.data.result[] | "\(.metric.job) \(.value[1])"' | sort -u
DOWN=$(echo "$UP" | jq '[.data.result[] | select(.value[1]=="0")] | length')
echo "targets DOWN: $DOWN"    # this MUST be 0 for the tier to be healthy
# compliance metric present (confirms the OpenSCAP scan actually ran):
curl -s 'http://127.0.0.1:9090/api/v1/query?query=compliance_score_percent' \
  | jq '.data.result | length'    # -> number of hosts reporting a score

# ---------------------------------------------------------------------------
# MAIL tier (mail1) — 7 services + auth + DNS records + backup snapshot
# ---------------------------------------------------------------------------
systemctl is-active postfix dovecot rspamd postgresql named nginx postfix_exporter
doveadm auth test test@platform.lab TestMailPass2026 2>&1 | grep -q "auth succeeded" \
  && echo "mail auth: OK" || echo "mail auth: FAILED"
dig @127.0.0.1 platform.lab MX +short
dig @127.0.0.1 platform.lab TXT +short
dig @127.0.0.1 _dmarc.platform.lab TXT +short
RESTIC_PASSWORD='CHANGE_ME' restic -r /srv/restic/mail snapshots --json | jq 'length'  # must be > 0

# ---------------------------------------------------------------------------
# The Ansible one-liner that does ALL of the above in one shot, tier by tier:
#   ansible-playbook validate.yml
#   ansible-playbook validate.yml --tags edge      # just one tier
# No failed tasks reported = every tier is healthy: services active, VIP up,
# app responding, all Prometheus targets scraping, compliance scanned,
# mail auth/DNS/backups OK.
# ---------------------------------------------------------------------------

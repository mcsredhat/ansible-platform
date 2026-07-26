#!/usr/bin/env bash
# =============================================================================
# grafana.sh — CLI equivalent of the `grafana` role (dashboards)
# Mirrors: roles/grafana/tasks/main.yml — verified line-by-line against source.
# Run as root (obs1).
# =============================================================================

# 1. Official RPM repo (Grafana is the one exception to binary+systemd install —
#    it ships a proper YUM repo, so use it instead of a manual tarball).
cat > /etc/yum.repos.d/grafana.repo <<'REPO'
[grafana]
name=Grafana OSS
baseurl=https://rpm.grafana.com
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
enabled=1
REPO
dnf -y install grafana

# 2. grafana.ini — deployed from a template; the admin password setting there
#    only takes effect on FIRST boot, which is why the password is actually
#    set below via grafana-cli (works even before the service re-reads ini).

# 3. Provisioning directories
install -d -o root -g grafana -m 0750 /etc/grafana/provisioning/datasources
install -d -o root -g grafana -m 0750 /etc/grafana/provisioning/dashboards
install -d -o grafana -g grafana -m 0755 /var/lib/grafana/dashboards

# 4. Datasources — Prometheus (default) + Loki, both via proxy access
cat > /etc/grafana/provisioning/datasources/platform.yml <<'DS'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:9090
    isDefault: true
    editable: false
  - name: Loki
    type: loki
    access: proxy
    url: http://127.0.0.1:3100
    editable: false
DS

# 5. Dashboard provider (tells Grafana to auto-load JSON from the dashboards dir)
cat > /etc/grafana/provisioning/dashboards/platform.yml <<'PROV'
apiVersion: 1
providers:
  - name: platform
    folder: Platform
    type: file
    options:
      path: /var/lib/grafana/dashboards
PROV

# 6. The platform ships 7 real dashboards (roles/grafana/files/dashboards/*.json) —
#    copy each into place. On a real client without this repo, you'd build/import
#    these dashboards via the UI or Grafana's dashboard JSON export/import:
#      platform-overview.json   host-metrics.json      slo-error-budget.json
#      capacity-trends.json     security-overview.json compliance.json
#      mail.json
# cp /path/to/dashboards/*.json /var/lib/grafana/dashboards/
chown grafana:grafana /var/lib/grafana/dashboards/*.json 2>/dev/null || true

# 7. Start (service name is grafana-server, not grafana)
systemctl daemon-reload
systemctl enable --now grafana-server

# 8. Set the admin password from Vault — ONCE, using a marker file so re-runs
#    are idempotent (grafana-cli always reports success, so without the marker
#    this would show as "changed" every single run):
if [ ! -f /etc/grafana/.admin_pw_set ]; then
  grafana-cli --homepath /usr/share/grafana admin reset-admin-password 'CHANGE_ME_VAULT_PW'
  touch /etc/grafana/.admin_pw_set
  chown root:grafana /etc/grafana/.admin_pw_set
  chmod 0640 /etc/grafana/.admin_pw_set
fi

# 9. Firewall — only if firewalld is actually active (the role checks first),
#    restricted to the management subnet, not open to the world:
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --add-rich-rule='rule family=ipv4 source address=192.168.1.0/24 port port=3000 protocol=tcp accept'
  firewall-cmd --reload
fi

# --- Operating ---
curl -s http://127.0.0.1:3000/api/health          # -> {"database":"ok",...}
# Browse to http://obs1:3000  (log in as admin / the password you set above)

# Runbook: VIP Availability / SLO Burn

**Alerts:** `VipProbeDown`, `SLOErrorBudgetFastBurn`, `SLOErrorBudgetSlowBurn`
**Severity:** critical (probe down / fast burn) / warning (slow burn)

## 1. Confirm user impact
- `curl -sk -o /dev/null -w '%{http_code}\n' --resolve app.platform.lab:443:10.50.1.10 https://app.platform.lab/` from the control node.
- Grafana → SLO / Error Budget → current availability + burn rate.

## 2. Locate the failure in the stack
- **VIP itself:** `ansible edge -b -m shell -a "ip -4 -o addr show | grep 10.50.1.10"` — is the VIP assigned to exactly one edge?
- **keepalived:** `ansible edge -b -m shell -a "systemctl is-active keepalived; env -i /etc/keepalived/chk_nginx.sh; echo rc=$?"` — both should be healthy.
- **edge nginx:** `ansible edge -b -m shell -a "systemctl is-active nginx"`.
- **web backends:** `ansible web -b -m shell -a "systemctl is-active nginx php-fpm; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/healthz"`.
- **data tier:** `ansible data1 -b -m shell -a "systemctl is-active mariadb redis"`.

## 3. Common causes
- Both edges faulted (keepalived health script failing) → no VIP holder. See the keepalived health-check logic; confirm `chk_nginx.sh` returns 0.
- A web backend down → edge should route around it (least_conn, proxy_next_upstream); if both down, the site is down.
- Data tier down → app errors (5xx); check MariaDB/Redis.

## 4. Recover
- Restart the failed component via its playbook (idempotent).
- If data is lost/corrupt, invoke `dr.yml` (restore from restic).

## 5. Close out
- Note the outage window (it consumes error budget). Document root cause; if it recurs, address the underlying fragility.

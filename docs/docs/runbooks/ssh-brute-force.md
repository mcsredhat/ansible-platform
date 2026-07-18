# Runbook: SSH Brute-Force / Invalid-User Probing

**Alerts:** `SshAuthFailureSpike`, `InvalidSshUser`
**Severity:** warning (escalate if a valid account is targeted)

## 1. Confirm scope
- Grafana → Security Overview → "SSH Failed Logins rate by instance" — which host(s)?
- Loki: `{job="journald", instance="<host>"} |= "Failed password"` — identify source IPs and whether attempts target real usernames.

## 2. Determine if anything succeeded
- Loki: `{job="journald", instance="<host>"} |= "Accepted password" or "Accepted publickey"` around the attack window.
- If a login **succeeded** from an attacker IP → treat as compromise, jump to step 5.

## 3. Verify fail2ban responded
- `ansible <host> -b -m shell -a "fail2ban-client status sshd"` — the source IPs should be banned.
- If not banned, check the jail: `ansible <host> -b -m shell -a "systemctl status fail2ban"`.

## 4. Contain
- If the source is a single IP/range, block at the edge: add a firewalld rich-rule drop on edge1/edge2.
- Confirm SSH is key-only (it is, per hardening) — password auth being off makes brute-force ineffective; this is usually just noise from internet scanning.

## 5. If compromise suspected
- Isolate the host (detach from the app path; for web nodes, drain from the edge upstream).
- Rotate the `deploy` SSH key fleet-wide and any credentials on that host.
- Review `/var/log/audit/audit.log` and journald for post-login activity.
- Rebuild the host from Ansible (cattle, not pets): re-run `site.yml` against a fresh VM.

## 6. Close out
- Document source IPs, timeline, and whether contained. Silence the alert in Alertmanager only after confirming remediation.

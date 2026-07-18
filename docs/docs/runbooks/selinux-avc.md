# Runbook: SELinux AVC Denial

**Alert:** `SelinuxAvcDenial`
**Severity:** warning

## 1. Identify the denial
- `ansible <host> -b -m shell -a "ausearch -m avc -ts recent"` — see what was denied (process, target, permission).
- Grafana → Security Overview → recent-events log panel filters AVCs too.

## 2. Classify
- **Legitimate app broken by policy** (most common) → a service can't do something it should. Confirm the service is failing.
- **Unexpected process** touching something it shouldn't → possible intrusion; do not blindly allow.

## 3. Legitimate case
- Generate a targeted policy: `ausearch -m avc -ts recent | audit2allow -M mymodule` then review the `.te` before `semodule -i`.
- Prefer setting the correct fcontext/boolean over a custom module where one exists (the platform already sets booleans like `httpd_can_network_connect_db`).
- Encode the fix in the relevant Ansible role so it persists.

## 4. Suspicious case
- Do NOT allow. Investigate the process origin. Treat as potential compromise (see ssh-brute-force runbook step 5).

## 5. Close out
- Never resolve by setting SELinux permissive. Document the denial and the policy change.

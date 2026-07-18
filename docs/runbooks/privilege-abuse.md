# Runbook: Privilege Abuse / Sensitive File Change

**Alerts:** `SudoFailure`, `SensitiveFileChange`
**Severity:** warning (sudo) / critical (sensitive file)

## 1. Identify the actor
- Loki: `{job="journald", instance="<host>"} |= "sudo"` — which user, which command, from where.
- For file changes: `ansible <host> -b -m shell -a "ausearch -f /etc/passwd -ts recent"` (swap the path for the flagged file).

## 2. Assess
- Repeated sudo failures from a legitimate user → likely fumbling, not malicious; confirm with them.
- Sudo failures from an unexpected account, or a sensitive-file change with no change-ticket → treat as intrusion.

## 3. Respond (suspicious)
- Lock the account: `ansible <host> -b -m shell -a "usermod -L <user>"`.
- Review what the session did (audit.log, shell history).
- If /etc/sudoers or /etc/passwd was modified unexpectedly, restore from Ansible-managed config (`ansible-playbook hardening.yml`) and rebuild if integrity is in doubt.

## 4. Close out
- Every legitimate change to these files should come through Ansible — if it didn't, that's the signal. Document and remediate.

# Runbook: AIDE File-Integrity Change

**Alert:** `AideIntegrityChanged` (aide_check_changed_files > 0)
**Severity:** critical

## 1. See what changed
- `ansible <host> -b -m shell -a "aide --check"` — lists added/removed/changed files with attributes.

## 2. Classify the change
- **Expected** (a package update, a config deploy you ran) → legitimate; update the baseline (step 4).
- **Unexpected** (system binaries, /etc/passwd, cron, SSH keys changed with no known cause) → treat as compromise.

## 3. Unexpected → respond
- Isolate the host from the app path.
- Compare changed binaries against known-good (package verification: `rpm -Va`).
- Preserve evidence (copy audit.log, the AIDE report) before remediation.
- Rebuild from Ansible against a fresh VM rather than cleaning in place.

## 4. Expected → re-baseline
- Re-init the AIDE database: `ansible <host> -b -m shell -a "aide --init && mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz"`.
- The next `aide-metrics` run clears the metric and the alert.

## 5. Close out
- Document what changed and why. Never re-baseline without confirming the change was authorized.

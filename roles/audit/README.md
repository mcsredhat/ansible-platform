# Role: audit

Detective security controls (00-architecture §4.2) — the "prove it" half of security,
applied to every node. Pairs with `hardening` (preventive).

## What it does
- **auditd** + a CIS-style ruleset in `/etc/audit/rules.d/99-platform.rules` (time
  changes, identity files, sudoers, logins/sessions, perm/ownership, access denials,
  privileged commands, module loads, mounts, deletions, MAC policy). Loaded with
  `augenrules --load`. Set `audit_immutable: true` to append `-e 2` (CIS; needs a
  reboot to change rules afterward).
- **AIDE** installed, baseline DB built once, **daily integrity check** via a systemd timer.
- **OpenSCAP** scanner + SCAP Security Guide, with a **weekly compliance scan** timer
  writing an HTML report to `/var/log/oscap/` — you *prove* CIS posture, not just claim it.

## Future integration (Phase 5, observability)
- Ship audit/auth logs off-box via `promtail` -> Loki (so a compromised node can't erase
  its trail), and alert on SELinux AVC denials via Prometheus. Wired when the obs tier exists.

## Notes
- auditd, AIDE init, and OpenSCAP scans auto-skip in containers via `audit_in_container`.
- `audit_openscap_run_now: false` by default — the playbook sets up the timer but doesn't
  run a (slow) scan inline. Set true to scan during the run, or trigger:
  `systemctl start oscap-scan.service`.

## Key toggles
`audit_auditd`, `audit_immutable`, `audit_aide`, `audit_aide_init`, `audit_openscap`,
`audit_openscap_run_now` — plus schedules/profiles in `defaults/main.yml`.

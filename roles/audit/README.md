# Role: audit

Detective security controls (00-architecture §4.2) — the "prove it" half of security,
applied to every node. Pairs with `hardening` (preventive).

## What it does
- **auditd** + a CIS-style ruleset in `/etc/audit/rules.d/99-platform.rules` (time
  changes, identity files, sudoers, logins/sessions, perm/ownership, access denials,
  privileged commands, module loads, mounts, deletions, MAC policy). Loaded with
  `augenrules --load`. Set `audit_immutable: true` to append `-e 2` (CIS; needs a
  reboot to change rules afterward).
  Every `-S` syscall rule comes as a **b64/b32 pair**: a 32-bit binary on x86_64 uses the
  b32 syscall table and would bypass a b64-only rule. The b32 twin also lists the
  32-bit-only names (`stime`, `chown32`/`fchown32`/`lchown32`, `truncate64`/`ftruncate64`).
  Both arches also cover the modern variants that tools call today: `openat2` (access),
  `renameat2` (delete), `finit_module` (modules: what `modprobe` uses), `umount2` (mounts).
  `-w` watches and `-F path=` rules are arch-independent and have no twin.
- **AIDE** installed, **daily integrity check** via a systemd timer. The baseline is **not**
  built by `audit.yml`: see [AIDE baseline](#aide-baseline).
- **OpenSCAP** scanner + SCAP Security Guide, with a **weekly compliance scan** timer
  writing an HTML report to `/var/log/oscap/` — you *prove* CIS posture, not just claim it.
- Both timers are **jittered** (`RandomizedDelaySec`, also applied to the `Persistent=true`
  catch-up after boot) and both services run at **`Nice=19` / `IOSchedulingClass=idle`**,
  so a fleet of small VMs doesn't scan all at once after a reboot.
  `IOSchedulingClass=idle` only takes effect with the BFQ (or legacy CFQ) I/O scheduler;
  with `mq-deadline` or `none` (common on virtio disks) it is ignored and only `Nice=19`
  applies. Check with `cat /sys/block/vda/queue/scheduler`.

## AIDE baseline
The baseline is built by `aide_baseline.yml` (`tasks_from: aide_baseline`), the **last** play
of `site.yml`, so it captures the finished node rather than the state before mariadb, nginx,
wordpress and the exporters changed it. A node that already has `/var/lib/aide/aide.db.gz`
keeps it. Until the baseline exists, `aide-check.service` fails, which is visible on purpose.

**Existing nodes:** a node where the role ran before this change has a baseline taken
early, at the audit step. It is kept, so re-baseline it once (below).

Re-baseline after an intentional change (package update, config change). It rebuilds with
`aide --init` and activates the new DB, so there is no manual `mv`:

```bash
ansible-playbook aide_baseline.yml --limit web1 -e audit_aide_rebaseline=true --check --diff
ansible-playbook aide_baseline.yml --limit web1 -e audit_aide_rebaseline=true
```

Review what `aide --check` reports **before** re-baselining: a re-baseline accepts every
current difference as legitimate.

## OpenSCAP exit codes
`oscap-scan.sh` treats oscap rc 0 or 2 as a good scan (0 = all pass, 2 = some rules failed,
which is normal). Any other rc, or rc 0/2 with no results XML, prints an error, leaves
`compliance.prom` untouched and exits `1`, so `oscap-scan.service` shows as failed. A stale
`compliance_last_scan_timestamp_seconds` then signals that scans stopped working.

## Future integration (Phase 5, observability)
- Ship audit/auth logs off-box via `promtail` -> Loki (so a compromised node can't erase
  its trail), and alert on SELinux AVC denials via Prometheus. Wired when the obs tier exists.

## Notes
- auditd, the AIDE baseline, and OpenSCAP scans auto-skip in containers via `audit_in_container`.
- `audit_openscap_run_now: false` by default — the playbook sets up the timer but doesn't
  run a (slow) scan inline. Set true to scan during the run, or trigger:
  `systemctl start oscap-scan.service`.

## Key toggles
`audit_auditd`, `audit_immutable`, `audit_aide`, `audit_aide_init`, `audit_aide_rebaseline`,
`audit_openscap`, `audit_openscap_run_now` — plus schedules (`*_oncalendar`,
`audit_aide_check_randomized_delay`, `audit_openscap_randomized_delay`) and profiles in
`defaults/main.yml`.

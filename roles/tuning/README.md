# Role: tuning

Host-level performance tuning (00-architecture §4.3), applied to every node.
Per-service tuning (nginx workers, php-fpm children, MariaDB buffer pool, Redis
maxmemory) lives in those service roles — this role is the host baseline.

## What it does
- **tuned** installed + active, profile set to `{{ tuned_profile }}` (role default
  `throughput-performance` for bare metal; the lab inventory sets `virtual-guest`);
  idempotent via `tuned-adm active` check.
- **Transparent Huge Pages disabled** via a `disable-thp.service` oneshot unit
  (RemainAfterExit, runs at every boot) — the MariaDB/Redis perf footgun.
- **Resource limits** in `/etc/security/limits.d/90-tuning.conf` (nofile/nproc).
  These only affect login sessions, through `pam_limits`. systemd services don't
  pass through PAM, so they need `LimitNOFILE=` in their unit or a drop-in.
- **Performance sysctls** in `/etc/sysctl.d/95-tuning.conf` (backlog, tcp tuning,
  ephemeral port range) — separate file from the security sysctls
  (`90-hardening.conf`), so the two never collide.

## Notes
- All kernel-level tasks auto-skip in containers via `tuning_in_container`.
- **vm.\*, fs.file-max and net.core.somaxconn are deliberately not set.** tuned owns
  `vm.*`, and tuned reapplies `/etc/sysctl.d` after its profile, so a key here would
  override it. The kernel defaults for the other two are already higher.
- **`ip_local_port_range` starts at 12000**, above every platform listener (highest:
  rspamd 11334). A new service listening at 12000 or above needs this range revisited.
- THP and some sysctls take full effect from the next boot; the service applies
  THP immediately on first run too.

## Key toggles
`tuning_tuned`, `tuning_disable_thp`, `tuning_limits`, `tuning_sysctl` — plus
tunable values in `defaults/main.yml`.

# Role: tuning

Host-level performance tuning (00-architecture §4.3), applied to every node.
Per-service tuning (nginx workers, php-fpm children, MariaDB buffer pool, Redis
maxmemory) lives in those service roles — this role is the host baseline.

## What it does
- **tuned** installed + active, profile set to `{{ tuned_profile }}` (default
  `throughput-performance`); idempotent via `tuned-adm active` check.
- **Transparent Huge Pages disabled** via a `disable-thp.service` oneshot unit
  (RemainAfterExit, runs at every boot) — the MariaDB/Redis perf footgun.
- **Resource limits** in `/etc/security/limits.d/90-tuning.conf` (nofile/nproc
  for login sessions; systemd services get their own LimitNOFILE in their roles).
- **Performance sysctls** in `/etc/sysctl.d/95-tuning.conf` (somaxconn, backlog,
  tcp tuning, file-max, swappiness, dirty ratios) — separate file from the
  security sysctls (`90-hardening.conf`), so the two never collide.

## Notes
- All kernel-level tasks auto-skip in containers via `tuning_in_container`.
- THP and some sysctls take full effect from the next boot; the service applies
  THP immediately on first run too.

## Key toggles
`tuning_tuned`, `tuning_disable_thp`, `tuning_limits`, `tuning_sysctl` — plus
tunable values in `defaults/main.yml`.

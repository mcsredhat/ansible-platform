# Access & Privilege Audit Summary

Service and human accounts on the platform, their scope, and justification —
evidence for PGSSI-S access-control / least-privilege requirements.

> Regenerate the live account inventory with:
> `ansible all -b -m shell -a "getent passwd | awk -F: '\$3>=1000 || \$3==0'"`
> and the sudo grants with:
> `ansible all -b -m shell -a "getent group wheel; ls -l /etc/sudoers.d/"`

## Service accounts (least-privilege by design)

| Account | Host(s) | Scope / privilege | Justification |
|---|---|---|---|
| `deploy` | all | sudo (Ansible automation) | Controlled automation account; key-only SSH |
| `prometheus` | obs1 | runs prometheus; no shell | monitoring server |
| `grafana` | obs1 | runs grafana; no shell | dashboards |
| `loki` | obs1 | runs loki; no shell | log store |
| `node_exporter` | all | runs node_exporter; no login | host metrics |
| mysqld_exporter DB user | data1 | `PROCESS, REPLICATION CLIENT, SELECT` only | metrics; cannot read/modify app data |
| `webdata` (uid/gid 1980) | web+data | owns WordPress files/NFS | fixed uid/gid for consistent NFS perms |

## Controls
- SSH is **key-only** (password auth disabled) fleet-wide.
- No shared interactive accounts; `deploy` is the single automation identity.
- `sudo` use is logged (auditd) and shipped to Loki; `SudoFailure` alerts on abuse.
- Service accounts run with `nologin`/`n_shell` and minimal privilege.

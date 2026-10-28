# Role: base

Foundation applied to every node: hostname, `/etc/hosts` from the platform map,
EPEL + CodeReady (RHEL), base packages, timezone + chrony, static networking via
nmcli, SELinux enforcing, firewalld.

## Key variables
| Variable | Default | Notes |
|---|---|---|
| `base_manage_network` | `true` | `false` skips nmcli (leave NIC pre-set) |
| `base_mtu` | unset | NIC MTU via nmcli; unset = OS default. Lab sets `1230` (VXLAN over Tailscale) |
| `base_selinux_state` | `enforcing` | |
| `base_timezone` | `Europe/Paris` | |
| `node_ip` | — | per-host, in `host_vars` |
| `gateway` / `dns_server` / `base_prefix` | — | in `group_vars/all` |

## Run
```bash
ansible-playbook base.yml --limit edge1 --check --diff   # preview one node
ansible-playbook base.yml --limit edge1                  # apply, then run AGAIN -> 0 changed
ansible-playbook base.yml                                # scale to all
```

## Test (Molecule)
```bash
cd roles/base && molecule test
```
Container tasks (SELinux/firewalld/nmcli/chrony) auto-skip via `base_in_container`.

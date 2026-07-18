# TROUBLESHOOTING — Phase 0/1 (every issue hit during setup, and its fix)

A running log of the real errors encountered bringing this platform up on RHEL 9,
with the cause and the fix. Ordered roughly by where they appear in SETUP.md.

## Control node / Ansible install

| Symptom | Cause | Fix |
|---|---|---|
| `Collection community.general does not support Ansible version 2.15.13` | RHEL 9's default Python 3.9 caps ansible-core at 2.15, too old for current collections | Build the control-node venv on **Python 3.12**: `dnf install python3.12`, `python3.12 -m venv ~/.venv/ansible`, reinstall ansible + `ansible-galaxy collection install -r requirements.yml --force` |
| `ERROR! community.general.yaml has been removed` | `stdout_callback = yaml` referenced a callback removed in community.general 12.0.0 | In `ansible.cfg` use the built-in: `stdout_callback = default` + `result_format = yaml` |
| `sudo: <file>: command not found` / `bash: <file>: Permission denied` when editing a file | `$EDITOR` is unset, so the shell tried to run the filename as a command | Use a real editor (`vi <file>`); set it: `export EDITOR=vi` and add to `~/.bashrc` |

## Vault

| Symptom | Cause | Fix |
|---|---|---|
| `Attempting to decrypt but no vault secrets found` | Ran a play without a vault password; the encrypted `vault.yml` loads on every run | Add `--ask-vault-pass`, or set up `.vault-pass` + uncomment `vault_password_file` in `ansible.cfg` |
| `Decryption failed (no vault secrets were found that could decrypt)` | `.vault-pass` holds the wrong content (often the literal placeholder text) | Put the REAL vault password in it: `printf '%s' 'REALPW' > .vault-pass` (printf avoids a trailing newline); verify with `ansible-vault view inventories/lab/group_vars/all/vault.yml` |
| Forgot the vault password | n/a | `ansible-vault rekey inventories/lab/group_vars/all/vault.yml` (asks old once, sets new) |

## Editing inventory / YAML

| Symptom | Cause | Fix |
|---|---|---|
| `YAML parsing failed: ... did not find expected key` | An edit (e.g. uncommenting `ansible_user: deploy`) introduced bad indentation or a tab | Keys must be flush-left at column 0; no tabs. Pinpoint with `python3 -m yamllint <file>`; inspect hidden chars with `tail -15 <file> | cat -A` (`^I` = tab) |
| `'ansible.builtin.set_fact' is not a valid attribute for a Play` | Role *tasks* were pasted into the playbook `base.yml` | `base.yml` holds only the play (`hosts:` + `roles:`); tasks live in `roles/base/tasks/main.yml` |

## Bootstrap / connectivity

| Symptom | Cause | Fix |
|---|---|---|
| `UNREACHABLE! ... No route to host` (one node) | Node powered off, or not on its expected IP | Power it on; from console `ip -br a`; re-run `--limit <node>` |
| Same node flaps reachable/unreachable | DHCP (not pinned) or an IP conflict on that address | Pin static from the console (`nmcli con mod ... ipv4.method manual ipv4.addresses X/24 ...`); check duplicates: `arping -D -I <iface> -c2 <ip>`. Running `base` pins it permanently |
| "Register with Red Hat" shows `ok` not `changed` | Node was already registered — module is idempotent | Not an error; nothing to do |
| A node re-bootstraps every run (`changed=3` repeatedly) | VM snapshots being reverted between runs, discarding state | Make changes on live VMs; stop reverting; pin static IPs for determinism |

## Base role

| Symptom | Cause | Fix |
|---|---|---|
| `DEPRECATION WARNING: INJECT_FACTS_AS_VARS ...` | Tasks used top-level facts (`ansible_distribution`, `ansible_default_ipv4.interface`) | Cosmetic only. Cleaned by using `ansible_facts['distribution']`, `ansible_facts['default_ipv4']['interface']`, etc. (already applied in this bundle) |
| Want to silence ALL deprecation noise quickly | — | Set `deprecation_warnings = False` in `ansible.cfg` (hides real ones too — prefer the fact-form fix) |

## Golden rules learned
- **`changed=0` on the second run** is the idempotence proof — always run twice.
- The encrypted `vault.yml` loads on *every* play, so vault auth is needed even by plays that don't use its variables.
- Pin static IPs early; DHCP-driven flapping wastes hours.
- `base.yml` = play; `roles/base/tasks/main.yml` = tasks. Never mix them.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

One Ansible monorepo that provisions two stacks on **RHEL 9 with SELinux enforcing**: an HA WordPress platform (edge / web / data / obs tiers) and a mail platform (mail1), built from shared foundation roles. The design is locked in `00-ansible-platform-architecture.md` (design principles §1, role map §3, orchestration order §9, variable catalog §10). Read it before adding or restructuring roles.

## Rules

- Never run `ansible-playbook` without `--check` (or `--syntax-check`) unless I explicitly ask; show me the command first.
- FQCN only (`ansible.builtin.*`, `ansible.posix.*`, `community.*`), every task idempotent.
- Known issue: `keepalived_auth_pass` in `roles/keepalived/defaults/main.yml` is a plaintext secret; it must move to `vault_*` in the vault. Never add new plaintext secrets.
- The current lab subnet is `10.50.1.0/24` . all role IPs derive from subnet,vip ,and node_ip in the inventory : never hardcode an IP in a role.

## Commands

The Python 3.12 venv at `~/.venv/ansible` holds ansible-core, ansible-lint and molecule. RHEL 9's default Python 3.9 caps ansible-core at 2.15, which is too old for the collections.

```bash
ansible-galaxy collection install -r requirements.yml

# Lint (same gates as CI)
yamllint . && ansible-lint
scripts/ci/secrets-scan.sh                 # vault must be encrypted; no plaintext creds outside it

# Syntax-check every play (CI loop; requirements.yml is not a playbook)
ansible-playbook site.yml --syntax-check
ansible-playbook <play>.yml --syntax-check

# Test one role (full create→converge→idempotence→verify→destroy in a podman systemd container)
cd roles/<role> && molecule test
cd roles/<role> && molecule converge && molecule verify   # faster iteration loop

# Run against the lab: preview, apply, re-apply. The second run must report changed=0.
ansible-playbook <play>.yml --limit <host> --check --diff
ansible-playbook <play>.yml --limit <host>    # (only when asked)
ansible-playbook site.yml --tags <role>       # (only when asked) tasks are tagged per role (e.g. redis, audit)
ansible-playbook validate.yml [--tags edge|web|data|obs|mail]   # read-only end-to-end health check
```

`ansible.cfg` sets `vault_password_file = .vault-pass` (git-ignored). Because the encrypted `group_vars/all/vault.yml` loads on every play, **every** `ansible-playbook` run, syntax-check included, needs `.vault-pass` to exist. Create the vault from `vault.yml.example`.

## Architecture

**Playbook layout.** Each role has a thin top-level play `<role>.yml` (`hosts:` + `roles:` only, never tasks). `site.yml` only `import_playbook`s those plays, in dependency order: foundation → data → web → edge → fail2ban → secops → observability servers → exporters. The order matters. For example, `nginx_common` runs before `nginx_edge` and `fail2ban`, and `alertmanager` runs before `prometheus`. Keep that order when inserting plays. These plays are **not** in `site.yml`:
- `bootstrap.yml`: run once by hand before anything else (RHSM registration, `deploy` user, key, sudo).
- `mail.yml`: the whole mail stack (`mail_*` roles) on the `mail` group, run on its own.
- `dr.yml`: manual restic restore. It is guarded by `-e confirm=RESTORE`, and `target=live` is destructive (it re-imports the DB and runs `rsync --delete` on the uploads).
- `validate.yml`: assert-based checks of each tier.

**Inventory.** `inventories/lab/` is the only inventory. Platform-wide invariants (`subnet`, `vip`, `domain`, `webdata_uid/gid`, `platform_hosts`, `tuned_profile`) are defined once in `group_vars/all/main.yml` and referenced everywhere. Per-host differences live in `host_vars` (`ansible_host`, `node_ip`, `backend_marker`, `wp_role: install|serve`). Secrets are `vault_*` variables in `group_vars/all/vault.yml`, and other files reference them indirectly (`foo_pw: "{{ vault_foo_pw }}"`).

**Role conventions** (copy `roles/base` and its molecule scenario as the reference pattern):
- Each service role owns its own firewalld port/rich rule, SELinux booleans, fcontext and seport. There is no central firewall role. Internal services allow only `subnet` as source.
- Roles detect containers (`<role>_in_container` fact from `ansible_facts['virtualization_type']`) and skip service start and firewalld when the role runs under molecule. Keep that guard on anything that can't run in an unprivileged container.
- Tasks carry tags `[<role>, packages|config|service|firewall]`.
- Use `ansible_facts['...']`, not injected top-level facts like `ansible_distribution`.
- Interactive steps become guarded tasks (`creates:`, `changed_when:`). Idempotence is checked by molecule and CI.
- Validate before reloading anything that can lock you out (`sshd -t`, `nginx -t`, `visudo -cf`, `promtool check config`).
- `base` manages static IPs with nmcli. `base_manage_network: false` disables that (molecule sets it).

**Molecule scenarios do not read the lab inventory.** Each `molecule/default/molecule.yml` repeats the group_vars it needs (subnet, vip, platform_hosts, test passwords like `molecule_test_pw`). When a role starts using a new global variable, add it to that role's molecule.yml as well. Image: `rockylinux:9-ubi-init` with systemd.

## CI

`.gitlab-ci.yml` is the real pipeline. It runs on a self-hosted shell runner tagged `homelab` (setup in `docs/SETUP-GITLAB-CI.md`), and `before_script` writes `.vault-pass` from `$ANSIBLE_VAULT_PASSWORD`. Stages: lint → syntax → secrets → molecule. The molecule matrix runs only on MRs and the default branch.
- `nfs_server` is `allow_failure` because kernel NFS can't run in a container. It is integration-tested on data1 and by `validate.yml`.
- `wordpress` is excluded because it needs the live data tier.
- The `mail_*` roles have no molecule scenarios.
- A new role with a passing scenario goes into the `ROLE` matrix list.

`.github/workflows/ci.yml` is a smaller mirror (lint + `base` molecule only).

`.ansible-lint` uses the `production` profile, with deliberate skips explained inline. Notable: `community.mysql` stays as-is (`fqcn[canonical]` is skipped), and `command-instead-of-module` is skipped because auditd can't be restarted through systemd on RHEL.

## Docs

When you change a role's behavior, update its by-hand equivalent in `docs/cli-reference/<role>.sh` to match.

# ansible-platform

One Ansible monorepo provisioning two production-grade stacks on **RHEL 9 under enforcing
SELinux** — the HA WordPress platform (edge / web / data / obs) and the mail platform
(Postfix / Dovecot / Rspamd / webmail) — from shared foundation roles. Full design in
`00-ansible-platform-architecture.md`.

## Layout
```
ansible.cfg            # inventory path, sudo, pipelining
requirements.yml       # ansible.posix, community.general/mysql/postgresql
site.yml               # master orchestration (grows per phase)
base.yml               # Phase 1 entry play
inventories/lab/       # hosts.yml + group_vars + host_vars (the 6 nodes)
roles/base/            # foundation role + molecule (the reference pattern)
.ansible-lint .yamllint .pre-commit-config.yaml .github/workflows/ci.yml
```

## Quick start (build small, grow)
```bash
ansible-galaxy collection install -r requirements.yml

# 1) one node, preview then apply, then re-run to prove idempotence
ansible-playbook base.yml --limit edge1 --check --diff
ansible-playbook base.yml --limit edge1
ansible-playbook base.yml --limit edge1        # second run = 0 changed (the golden rule)

# 2) scale the SAME role to every node
ansible-playbook base.yml
```

## Secrets
```bash
cp inventories/lab/group_vars/all/vault.yml.example inventories/lab/group_vars/all/vault.yml
ansible-vault encrypt inventories/lab/group_vars/all/vault.yml
```

## Test & lint
```bash
yamllint . && ansible-lint
cd roles/base && molecule test
```

## Networking note
`base` manages each node's static IP with **nmcli**. It is idempotent — a node already on its
target IP never flaps. Do the first DHCP→static conversion from the console, or set
`base_manage_network: false` to leave networking pre-configured.

## Build phases
See §9 of the architecture doc. Phase 1 (this scaffold) = `base`. Next: `hardening`, `tuning`,
`audit`, then the data tier.

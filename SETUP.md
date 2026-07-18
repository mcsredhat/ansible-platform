# SETUP — Control node + all-hosts bootstrap (Phase 0, RHEL 9)

From zero to `base` running on all eight nodes. Everything — control node and
all managed nodes — is **RHEL 9**. The host-bootstrap (incl. Red Hat
registration) is automated by `bootstrap.yml`.

## Prerequisites
- Eight **RHEL 9** VMs reachable by IP (edge1 .11, edge2 .12, web1 .21,
  web2 .22, data1 .31, obs1 .41, mail1 .51), each with one working login
  (root password or a cloud-init user).
- A separate **RHEL 9** control node (small VM). Not one of the managed nodes.
- A free **Red Hat Developer Subscription for Individuals** (covers up to 16
  systems). Create an **activation key** + note your **org ID** at
  https://console.redhat.com -> *Activation Keys* — used for unattended node
  registration.

> RHEL needs subscription-manager registration before `dnf` can install
> anything. Register the *control node* by hand (below); the *managed nodes*
> are registered automatically by `bootstrap.yml`. Do NOT register the golden
> image before cloning — register each clone fresh (avoids duplicate consumer UUIDs).

## 1. Control node — register, then install Ansible
```bash
# register this one box by hand
sudo subscription-manager register --username <rh-login> --password <pw>
# (RHEL 9 uses Simple Content Access — repos enable automatically)

sudo dnf -y install python3.12 python3.12-pip git
python3.12 -m venv ~/.venv/ansible
source ~/.venv/ansible/bin/activate
echo 'source ~/.venv/ansible/bin/activate' >> ~/.bashrc
pip install --upgrade pip
pip install ansible ansible-lint "molecule-plugins[podman]" molecule
ansible --version
```
RHEL-native alternative for Ansible itself: `sudo dnf -y install ansible-core`
(then pip-install ansible-lint/molecule, which are pip-only).

## 2. SSH key (the control node's identity)
```bash
ssh-keygen -t ed25519 -C "ansible-control"     # accept defaults, no passphrase for a lab
```

## 3. Get the project + collections + vault
```bash
tar xzf ansible-platform.tar.gz && cd ansible-platform   # or: git clone <your repo>
ansible-galaxy collection install -r requirements.yml

# create the vault and put your RHSM org ID + activation key in it
cp inventories/lab/group_vars/all/vault.yml.example inventories/lab/group_vars/all/vault.yml
vi inventories/lab/group_vars/all/vault.yml          # set vault_rhsm_org_id + key
ansible-vault encrypt inventories/lab/group_vars/all/vault.yml
```

## 4. Bootstrap ALL hosts (register + python + deploy user + key + sudo)
First run uses your existing login + password and the vault password:
```bash
# connecting as root with a password:
ansible-playbook bootstrap.yml -k --ask-vault-pass

# OR as a non-root cloud-init user (also needs the sudo password):
ansible-playbook bootstrap.yml -u clouduser -k -K --ask-vault-pass
```
Expect a green run with a "bootstrapped — registered + deploy user + key + sudo"
line per host. (If nodes are already registered, run with `-e rhsm_register=false`.)

## 5. Switch to key-based deploy user
Edit `inventories/lab/group_vars/all/main.yml` and uncomment:
```yaml
ansible_user: deploy
```
From here on, no SSH/sudo passwords — key + passwordless sudo handle everything.

## 6. Verify connectivity (the moment of truth)
```bash
ansible all -m ping                                     # every node -> "pong"
ansible all -m setup -a 'filter=ansible_distribution*'   # confirms RHEL 9
```

## 7. First role — build small, prove idempotence
```bash
ansible-playbook base.yml --limit edge1 --check --diff   # preview, no changes
ansible-playbook base.yml --limit edge1                  # apply
ansible-playbook base.yml --limit edge1                  # AGAIN -> changed=0 (idempotent)
ansible-playbook base.yml                                # scale base to all eight
```

## Troubleshooting
| Symptom | Fix |
|---|---|
| `dnf` → "This system is not registered" | node not registered; rerun step 4, or register by hand with `subscription-manager register` |
| registration task fails | wrong org ID / activation key in vault, or no developer subscription attached to the key |
| `ping` → unreachable / auth fail | wrong initial user/password; redo step 4 with `-u <user> -k -K` |
| `Permission denied (publickey)` after step 5 | bootstrap didn't install the key; rerun step 4, confirm `~/.ssh/id_ed25519.pub` exists |
| become / sudo errors | deploy sudoers not applied; rerun bootstrap, or run with `-K` |
| `nmcli` task warning on first base run | DHCP→static conversion; run that node from its console, or set `base_manage_network: false` |
| duplicate consumer / already registered | golden image was registered before cloning; `subscription-manager unregister` then rerun, and register clones not the template |

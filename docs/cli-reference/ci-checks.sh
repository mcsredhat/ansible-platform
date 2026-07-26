#!/usr/bin/env bash
# =============================================================================
# ci-checks.sh — CLI equivalent of the Phase 6 CI pipeline (.gitlab-ci.yml)
# Mirrors: .gitlab-ci.yml — verified line-by-line against source.
# Run the same quality gates by hand, locally, BEFORE pushing.
# =============================================================================

# --- Recreate the vault password file (every CI job does this fresh) ---
echo "$ANSIBLE_VAULT_PASSWORD" > .vault-pass
chmod 0600 .vault-pass

# --- Stage 1: lint ---
yamllint .
ansible-lint            # NOTE: no --profile flag needed here — profile:production
                         # is set in .ansible-lint / ansible-lint config, not the CLI call

# --- Stage 2: syntax-check (every playbook parses, imports resolve) ---
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml --syntax-check
for play in *.yml; do
  case "$play" in site.yml|requirements.yml) continue;; esac
  echo "--- syntax-check: $play"
  ansible-playbook "$play" --syntax-check
done

# --- Stage 3: secrets — NOT gitleaks. A custom two-part check: ---
#   1. the vault file must actually be ansible-vault encrypted
#   2. no plaintext password/secret/token/api_key patterns anywhere else
scripts/ci/secrets-scan.sh
# Reading what it does, so you can run the checks manually too:
#   head -1 inventories/lab/group_vars/all/vault.yml | grep '^\$ANSIBLE_VAULT'
#   grep -rniE '(password|secret|api_key|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'{$][^"'"'"']{5,}' \
#     --include='*.yml' --exclude='vault.yml' --exclude-dir=molecule --exclude-dir=docs .

# --- Stage 4: molecule (each role: create -> converge -> idempotence -> verify -> destroy) ---
# The MUST-PASS matrix is 23 specific roles (nfs_server and wordpress are
# intentionally excluded — see the comments in .gitlab-ci.yml for why):
MUST_PASS="base hardening tuning audit fail2ban mariadb redis nfs_client \
nginx_common nginx_edge keepalived node_exporter restic_backup prometheus \
alertmanager loki grafana blackbox_exporter promtail nginx_exporter \
mysqld_exporter secops php_fpm"

for role in $MUST_PASS; do
  echo "=== molecule: $role ==="
  ( cd "roles/$role" && molecule test ) || echo "FAILED: $role"
done

# nfs_server: run for visibility, but it's EXPECTED to fail in a container
# (no kernel NFS support) — allow_failure in CI, documented, not a real bug:
( cd roles/nfs_server && molecule test ) || echo "nfs_server failed as expected (container limitation)"

# Iterate faster during development (skip destroy between edits):
#   cd roles/<role>
#   molecule create && molecule converge      # repeat converge as you edit
#   molecule verify
#   molecule destroy

# --- The golden idempotence check by hand (no molecule needed) ---
# Run a play twice; the second run MUST report changed=0:
#   ansible-playbook base.yml --limit web1
#   ansible-playbook base.yml --limit web1     # changed=0 = idempotent

#!/bin/bash
# CI secrets gate:
#  1. the vault file must be ansible-vault encrypted
#  2. no plaintext credential patterns outside the vault
set -euo pipefail
fail=0

# --- 1. vault must be encrypted -------------------------------------------
VAULT="inventories/lab/group_vars/all/vault.yml"
if [ -f "$VAULT" ]; then
    if ! head -1 "$VAULT" | grep -q '^\$ANSIBLE_VAULT'; then
        echo "FAIL: $VAULT is NOT vault-encrypted (plaintext committed!)"
        fail=1
    else
        echo "OK: vault file is encrypted"
    fi
fi

# --- 2. plaintext secret patterns outside the vault ------------------------
# Look for obvious credential assignments with literal values. Excludes the
# encrypted vault, molecule test fixtures, docs and this script.
matches=$(grep -rniE \
    '(password|passwd|secret|api_key|token)[[:space:]]*[:=][[:space:]]*["'\''][^"'\''{$][^"'\'']{5,}' \
    --include='*.yml' --include='*.yaml' --include='*.cfg' --include='*.ini' \
    --exclude='vault.yml' \
    --exclude-dir='molecule' --exclude-dir='.git' --exclude-dir='docs' \
    . 2>/dev/null \
    | grep -vE 'vault_[a-z_]+ *[:=]' \
    | grep -vE '\{\{.*\}\}' \
    | grep -vE '(changeme|example|placeholder|molecule-test|CHANGE_ME)' \
    || true)

if [ -n "$matches" ]; then
    echo "FAIL: possible plaintext secrets found:"
    echo "$matches"
    fail=1
else
    echo "OK: no plaintext secret patterns outside the vault"
fi

exit $fail

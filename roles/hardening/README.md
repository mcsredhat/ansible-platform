# Role: hardening

Preventive security controls (00-architecture §4.1), applied to every node.

## What it does
- **sshd** drop-in `/etc/ssh/sshd_config.d/00-hardening.conf` (validated with `sshd -t`):
  no root login, key-only auth, strong ciphers/MACs/KEX, idle timeout, MaxAuthTries.
- **pam_faillock** via `authselect` + `/etc/security/faillock.conf` (lockout policy).
- **pam_pwquality** via `/etc/security/pwquality.conf` (complexity).
- **login.defs** password aging + `UMASK 027`.
- **sudo** command logging drop-in (validated with `visudo -cf`).
- **security sysctls** in `/etc/sysctl.d/90-hardening.conf` (rp_filter, syncookies,
  no redirects/source-routing, kptr/dmesg restrict, ASLR).

## SAFETY — do not lock yourself out
- Password auth is disabled; this is safe because the `deploy` user logs in by key
  (already proven by `ansible all -m ping`). Console access remains as a fallback.
- The sshd file is `validate`d, so a malformed config is never written.
- Roll out one node first and **open a second SSH session to confirm access BEFORE
  closing your current one**:
  ```bash
  ansible-playbook hardening.yml --limit edge1 --check --diff
  ansible-playbook hardening.yml --limit edge1
  ssh deploy@192.168.1.11 true     # confirm in a NEW session
  ansible-playbook hardening.yml   # then scale to all
  ```

## Key toggles
Every block has an on/off var (`hardening_ssh`, `hardening_faillock`,
`hardening_pwquality`, `hardening_login_defs`, `hardening_sudo_logging`,
`hardening_sysctl`) and tunable values — see `defaults/main.yml`.

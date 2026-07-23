# Backup Encryption Verification (HDS availability / confidentiality)

restic encrypts every repository with AES-256 and authenticates with Poly1305;
a repository cannot be read without its password. This documents how to *verify*
that on the platform.

## Verify the repo is encrypted and healthy
```bash
# on data1 (or wherever restic runs), with RESTIC_PASSWORD sourced from vault:
restic -r "$RESTIC_REPOSITORY" cat config      # prints repo config only if the password decrypts it
restic -r "$RESTIC_REPOSITORY" check           # verifies integrity of the encrypted repo
restic -r "$RESTIC_REPOSITORY" snapshots        # lists recovery points
```
A successful `cat config` / `check` proves the repository is encrypted *and* the
key is valid — an unencrypted or corrupt repo would fail these.

## Controls
- restic repo password stored in `ansible-vault`, never in plaintext.
- Backups run on a timer (`restic_backup` role); recovery is exercised via `dr.yml`.
- **Gap:** off-site replication of the restic repo is recommended for HDS-grade
  durability and is not yet implemented (documented as future work).

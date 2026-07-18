# Incident-Response Runbooks

Each runbook maps a fired alert to concrete response steps. They pair with
`dr.yml` (disaster recovery): these detect-and-respond, dr.yml restores.

| Alert | Runbook |
|-------|---------|
| SshAuthFailureSpike / InvalidSshUser | [ssh-brute-force.md](ssh-brute-force.md) |
| SelinuxAvcDenial | [selinux-avc.md](selinux-avc.md) |
| AideIntegrityChanged | [aide-integrity.md](aide-integrity.md) |
| SudoFailure / SensitiveFileChange | [privilege-abuse.md](privilege-abuse.md) |
| VipProbeDown / SLO burn | [vip-availability.md](vip-availability.md) |

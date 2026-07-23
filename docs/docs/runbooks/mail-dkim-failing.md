# Runbook: DKIM Validation Failing

## Symptoms
Recipients report DKIM `fail`/`none`; DMARC failures; mail spam-foldered.

## Triage
1. **Is Rspamd signing?** Send a test and check for a `DKIM-Signature` header:
   `swaks --to test@<domain> --server 127.0.0.1 --header 'Subject: t'` then
   `grep -l DKIM-Signature /var/mail/vhosts/<domain>/<user>/new/*`.
2. **Does the published key match the private key?**
   Compare the DNS TXT at `<selector>._domainkey.<domain>` with the generated
   record in `/var/lib/rspamd/dkim/<domain>.<selector>.txt`.
3. **Is Rspamd up and the milter reachable?** `systemctl is-active rspamd`;
   Postfix `smtpd_milters = inet:127.0.0.1:11332`.

## Common causes & fixes
- **DNS record not published / stale:** publish the exact TXT from the rspamd
  `.txt` file; wait for TTL/propagation.
- **Selector mismatch:** `mail_dkim_selector` in the role must equal the DNS
  selector (`<selector>._domainkey`).
- **Key regenerated but DNS not updated:** re-publish the new public key.
- **Rspamd not signing (milter down):** restart rspamd; verify the milter port.

## Verify
Use an external validator (mail-tester.com or a DKIM checker) once the domain is
public; internally, confirm the `DKIM-Signature` header is present and the
`Authentication-Results` header shows `dkim=pass`.

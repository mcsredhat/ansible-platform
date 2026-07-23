# Runbook: Outbound Mail Blacklisted / Rejected

## Symptoms
Recipients bounce with "blocked", "listed on RBL", or mail lands in spam.

## Triage
1. **Check the bounce reason** in `/var/log/maillog` — it usually names the RBL
   (e.g. Spamhaus ZEN, Barracuda) and a lookup URL.
2. **Check your sending IP reputation:** query the RBL (e.g. mxtoolbox.com/blacklists)
   or Spamhaus. Note *which* list.
3. **Verify your auth records resolve:** SPF, DKIM, DMARC, and a correct **PTR**
   (`dig -x <your-public-ip>`). A missing/mismatched PTR is the #1 cause.

## Common causes & fixes
- **No/wrong PTR** (residential or generic reverse DNS): set PTR at your provider to
  `mail.<domain>`. On a lab IP this is impossible — relay outbound through a smarthost
  (see ADR-mail-03).
- **SPF/DKIM failing:** re-check the published records (`dig <domain> TXT`,
  `dig <selector>._domainkey.<domain> TXT`) match what Postfix/Rspamd send.
- **New IP with no reputation:** IP "warming" takes time; low volume initially, or
  relay through a reputation-managed smarthost.
- **Compromised account sending spam:** check `postfix-sasl`/auth logs for a breached
  mailbox; reset its password, review `virtual_users`.

## Prevention
- Keep SPF `-all` (hard fail), DKIM signing on, DMARC `p=quarantine`+.
- Monitor via Google Postmaster Tools / mail-tester.com (target 10/10).
- For a lab / low-reputation IP: **relay outbound via smarthost** rather than self-send.

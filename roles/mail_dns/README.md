# mail_dns
BIND authoritative DNS for the mail domain, with the full deliverability record
set: MX, A, SPF, DMARC, DKIM (from rspamd), MTA-STS, TLS-RPT.

For the lab this is internal authoritative DNS. For a PUBLIC domain, publish the
same records at your registrar/Cloudflare instead of self-hosting BIND — the
zone file here is the source of truth for what those records should contain.

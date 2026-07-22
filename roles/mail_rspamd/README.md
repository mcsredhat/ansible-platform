# mail_rspamd
Rspamd for the mail platform: spam scoring, greylisting, and DKIM signing of
outbound mail. Integrates with Postfix as a milter (see mail_postfix milter
settings). Generates a DKIM keypair; the public TXT record for DNS is saved to
/var/lib/rspamd/dkim/<domain>.<selector>.txt for publishing.

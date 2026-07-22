# mail_postfix
Postfix MTA for the mail platform. Uses PostgreSQL (mail_postgres) for virtual
domain/mailbox/alias lookups, hands local delivery to Dovecot over LMTP, and
offers authenticated submission on 587/465 with SASL auth via Dovecot.

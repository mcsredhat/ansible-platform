# mail_dovecot
Dovecot for the mail platform: IMAP/POP3 access, LMTP local delivery (Postfix
hands mail here), and the SASL auth backend Postfix uses for submission. Looks up
users/passwords in PostgreSQL (mail_postgres). Mailboxes are Maildir under
/var/mail/vhosts/<domain>/<user>, owned by the vmail user.

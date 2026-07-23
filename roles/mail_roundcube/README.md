# mail_roundcube
Roundcube webmail on mail1: nginx + PHP-FPM serving the Roundcube app, backed by
its own PostgreSQL database, connecting to local Dovecot (IMAP 993) and Postfix
submission (587). Reachable at http://webmail.<domain> (add TLS in production).

# mail_postgres
PostgreSQL backend for the mail platform on mail1. Provides the `virtual_domains`,
`virtual_users`, and `virtual_aliases` tables that Postfix and Dovecot query for
domain routing, mailbox lookup, and alias expansion. Isolated from the app data
tier (MariaDB on data1) — mail and web are separate failure domains.

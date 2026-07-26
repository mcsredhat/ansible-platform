#!/usr/bin/env bash
# =============================================================================
# mail_postgres.sh — CLI equivalent of `mail_postgres` (mailbox backend)
# Mirrors: roles/mail_postgres/tasks/main.yml — verified against source.
# Run as root (mail1). Separate PostgreSQL from the app's MariaDB (different
# failure/security domain).
# =============================================================================

dnf -y install postgresql-server postgresql python3-psycopg2
[ -f /var/lib/pgsql/data/PG_VERSION ] || postgresql-setup --initdb

echo "host all all 127.0.0.1/32 md5" >> /var/lib/pgsql/data/pg_hba.conf
echo "host all all ::1/128 md5"       >> /var/lib/pgsql/data/pg_hba.conf
systemctl enable --now postgresql
systemctl reload postgresql

sudo -u postgres psql <<'SQL'
CREATE DATABASE mailserver;
CREATE USER mailuser WITH PASSWORD 'CHANGE_ME' ENCRYPTED;
SQL

# Schema: virtual domains, users, aliases
sudo -u postgres psql -d mailserver <<'SQL'
CREATE TABLE virtual_domains (id SERIAL PRIMARY KEY, name VARCHAR(255) NOT NULL UNIQUE);
CREATE TABLE virtual_users (
  id SERIAL PRIMARY KEY,
  domain_id INT REFERENCES virtual_domains(id),
  email VARCHAR(255) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL
);
CREATE TABLE virtual_aliases (
  id SERIAL PRIMARY KEY,
  domain_id INT REFERENCES virtual_domains(id),
  source VARCHAR(255) NOT NULL,
  destination VARCHAR(255) NOT NULL
);
GRANT SELECT ON virtual_domains, virtual_users, virtual_aliases TO mailuser;
INSERT INTO virtual_domains (name) VALUES ('platform.lab') ON CONFLICT (name) DO NOTHING;
SQL

# --- Add a mailbox (password stored as SHA512-CRYPT WITH the scheme prefix) ---
H=$(doveadm pw -s SHA512-CRYPT -p 'TestMailPass2026')
sudo -u postgres psql -d mailserver -c \
  "INSERT INTO virtual_users (domain_id, email, password)
   VALUES ((SELECT id FROM virtual_domains WHERE name='platform.lab'),
           'test@platform.lab', '$H');"

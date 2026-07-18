# mysqld_exporter
Prometheus exporter for MariaDB (data tier). Creates a dedicated,
least-privilege MySQL account (`PROCESS, REPLICATION CLIENT, SELECT` only —
no data access) and exposes metrics on `:9104`. Firewalled to the obs1
scraper only. Requires `vault_mysqld_exporter_pw`.

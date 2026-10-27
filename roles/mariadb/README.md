# Role: mariadb

The WordPress database tier (00-architecture §3.2), applied to the `data` group.

## What it does
- Installs **mariadb-server** + **PyMySQL** (needed by the mysql modules).
- Deploys `/etc/my.cnf.d/zz-platform.cnf`: network **bind**, `max_connections`,
  **`innodb_buffer_pool_size` sized to host RAM** (not hardcoded), utf8mb4, and
  **binary logging** (`log_bin`, `server_id`, ROW format) for point-in-time recovery.
- Idempotent **secure-installation**: removes anonymous users and the test DB
  (root uses unix_socket auth, so no password handling).
- Creates the **WordPress database** and a **network-scoped user**
  `wp_user@<a.b.c>.%` (pattern derived from `subnet`, /24 only, e.g. `wp_user@10.50.1.%`)
  with a vaulted password (`vault_mariadb_wp_pw`).
- Firewall: allows **3306 only from the web subnet**. (SELinux needs nothing —
  3306 is `mysqld_port_t` and mariadb runs as `mysqld_t` by default.)

## Prerequisites
- `vault_mariadb_wp_pw` set in the encrypted vault (must match what web nodes put
  in `wp-config.php` later).
- Run as a tier role: `ansible-playbook mariadb.yml` (targets `data`).

## Key variables
`mariadb_bind_address`, `mariadb_max_connections`, `mariadb_buffer_pool`,
`mariadb_binlog`, `mariadb_wp_db/user/host`, `mariadb_allowed_subnet` — see `defaults/`.

## Verify (on data1)
```bash
ss -tlnp | grep 3306                              # 0.0.0.0:3306
mysql -e 'SHOW DATABASES;' | grep wordpress       # the DB exists
# from web1:  mysql -h 10.50.1.31 -u wp_user -p wordpress -e 'SELECT 1;'
```

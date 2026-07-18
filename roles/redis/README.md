# Role: redis

Secured, shared Redis cache (00-architecture §3.2), on the `data` tier. Serves the
WordPress object cache (both web nodes) and the Rspamd backend (mail) — one instance,
the same shared-state reasoning as the DB and NFS export.

## What it does
- Installs **redis** (RHEL 9 AppStream).
- Edits `/etc/redis/redis.conf` in place (preserving distro paths):
  **binds to loopback + the node IP only** (not 0.0.0.0), `protected-mode on`,
  **`requirepass`** from the vault (`vault_redis_pw`), **`maxmemory` + `allkeys-lru`**
  eviction, and **disables `FLUSHALL`/`FLUSHDB`**.
- Firewall: allows **6379 only from the platform subnet**. (SELinux needs nothing —
  6379 is `redis_port_t` by default.)

## Shared-cache notes
- Both web nodes must point at THIS Redis (same instance) or the object cache goes
  inconsistent across blue/green — identical logic to the shared NFS uploads.
- Web nodes will need the SELinux boolean `httpd_can_network_connect` to reach it
  (set in the php/wordpress role).

## Key variables
`redis_bind`, `redis_password`, `redis_maxmemory`, `redis_maxmemory_policy`,
`redis_rename_dangerous`, `redis_allowed_subnet` — see `defaults/`.

## Verify (on data1)
```bash
ss -tlnp | grep 6379
redis-cli -a "$REDIS_PW" ping        # PONG
```

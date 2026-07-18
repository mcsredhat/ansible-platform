# node_exporter

Installs the Prometheus `node_exporter` (pinned binary + hardened systemd unit)
on every node, with the textfile collector enabled so other roles (e.g.
`restic_backup`) can publish custom metrics as `*.prom` files.

## What it does
- Creates a `node_exporter` system user (nologin).
- Downloads and installs the pinned `node_exporter` binary to `/usr/local/bin`.
- Enables the textfile collector at `/var/lib/node_exporter/textfile_collector`.
- Runs a hardened systemd service on `:9100`.
- Opens `:9100` in firewalld to the scraper (obs1) only.

## Key variables (`defaults/main.yml`)
| Variable | Default | Purpose |
|---|---|---|
| `node_exporter_version` | `1.8.2` | Pinned release |
| `node_exporter_port` | `9100` | Listen port |
| `node_exporter_textfile_dir` | `/var/lib/node_exporter/textfile_collector` | Custom-metric drop dir |
| `node_exporter_scraper_ip` | `192.168.1.41` | obs1 (only allowed scraper) |

## Scope
Runs on `all` hosts. Scraped by Prometheus on obs1.

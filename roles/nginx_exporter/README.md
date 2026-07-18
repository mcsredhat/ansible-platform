# nginx_exporter
Prometheus exporter for nginx (web + edge tiers). Deploys a local
`stub_status` endpoint on `127.0.0.1:8081`, then scrapes it and exposes
Prometheus metrics on `:9113`. Firewalled to the obs1 scraper only.

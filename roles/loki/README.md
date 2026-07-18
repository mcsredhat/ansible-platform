# loki
Grafana Loki (single-node, filesystem storage) on obs1. 7-day retention
(`loki_retention: 168h`). Receives logs pushed by `promtail` from every
node. API on `:3100`, firewalled to the platform subnet.

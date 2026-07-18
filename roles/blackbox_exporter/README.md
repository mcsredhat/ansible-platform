# blackbox_exporter
External synthetic monitoring on obs1. Probes the platform VIP over HTTPS
(`https://app.platform.lab/` resolved to the VIP) end-to-end through the
edge→web→app path — proving the *user-facing* site is up, independent of
whether individual service exporters report healthy. Prometheus scrapes it
with the multi-target pattern; the probe result feeds the platform SLO.

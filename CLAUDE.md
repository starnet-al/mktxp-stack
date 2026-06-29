# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Docker Compose monitoring stack for Mikrotik RouterOS devices. It wires together [MKTXP Exporter](https://github.com/akpw/mktxp) → Prometheus → Grafana, and optionally a centralized syslog pipeline: RouterOS devices → syslog-ng (UDP 514) → promtail (TCP 1514) → Loki → Grafana.

## Running the stack

There are three compose file variants — pick based on what you need:

```bash
# Full stack (metrics + logs, Loki receives syslog via TCP from promtail)
docker compose -f ./docker-compose-mktxp-stack.yml up -d

# Full stack with filesystem-persisted logs (logs written to syslog-ng/logs/)
docker compose -f ./docker-compose-mktxp-stack-fs.yml up -d

# Metrics only — no Loki, syslog-ng, or promtail
docker compose -f ./docker-compose-mktxp-stack-no-logs.yml up -d
```

Stop / restart individual containers:
```bash
docker compose -f ./docker-compose-mktxp-stack.yml down
docker restart promtail syslog-ng   # needed if new log files appear late
```

## Service architecture

All services share the `mktxp` Docker network. Internal DNS resolves by container name.

| Service | Image | Internal port | Published port | Notes |
|---------|-------|--------------|---------------|-------|
| mktxp | ghcr.io/akpw/mktxp | 49090 | — | Prometheus exporter for RouterOS |
| prometheus | prom/prometheus | 9090 | 9090 | Scrapes mktxp, grafana, loki, promtail |
| grafana | grafana/grafana | 3000 | 3000 | Dashboard UI |
| loki | grafana/loki | 3100 | 3100 | Log aggregation |
| promtail | grafana/promtail | 9080 | 9080, 1514 | Pushes logs to Loki |
| syslog-ng | balabit/syslog-ng | 514/udp, 601/tcp | 514/udp, 601/tcp | Receives RouterOS syslog, forwards to promtail:1514 |

Data flow for logs: RouterOS → syslog-ng:514 → (TCP/RFC5424) → promtail:1514 → loki:3100 → Grafana

## Key configuration files

| File | Purpose |
|------|---------|
| `mktxp/mktxp.conf` | Router entries: IP, credentials, which metrics to collect per device |
| `mktxp/_mktxp.conf` | Global MKTXP daemon settings (listen address, intervals, parallelism) |
| `prometheus/prometheus.yml` | Scrape targets; default retention 1y (fs variant: 90d/10GB) |
| `syslog-ng/syslog-ng.conf` | Receives network syslog, reformats to RFC5424, forwards to promtail TCP |
| `syslog-ng/syslog-ng-fs.conf` | Filesystem variant — also writes log files per device to `/var/log/syslog-ng/` |
| `promtail/promtail-config.yml` | Syslog scrape (network mode); labels `routerboard` from syslog hostname |
| `promtail/promtail-config-fs.yml` | File scrape (fs mode); derives `routerboard` label from filename |
| `loki/loki-config.yml` | Loki storage (TSDB/filesystem, schema v13, inmemory kvstore) |
| `grafana/provisioning/datasources/` | Auto-provisioned Prometheus + Loki datasources |
| `grafana/provisioning/dashboards/` | Auto-provisioned dashboards (mikrotik/ and system/ subdirs) |

## Grafana authentication

The **default** compose file (`docker-compose-mktxp-stack.yml`) runs Grafana with **anonymous Admin access** (no login required).

The **fs variant** (`docker-compose-mktxp-stack-fs.yml`) enables authentication via environment variables:
```
GF_ADMIN_USER=<username>
GF_ADMIN_PASSWORD=<password>
```
Set these in a `.env` file in the repo root before starting the fs variant.

## Adding a router

1. Edit `mktxp/mktxp.conf` — add a named section with `hostname`, `username`, `password`. Override any metric flags from `_mktxp.conf` defaults.
2. On the RouterOS device, create an API-read user:
   ```
   /user group add name=mktxp_group policy=api,read
   /user add name=mktxp_user group=mktxp_group password=mktxp_user_password
   ```
3. For centralized logging, configure the RouterOS remote logging action to point to the docker host IP on UDP 514 with `remote-log-format=syslog`.

## RouterOS syslog note (7.18+)

On RouterOS 7.18+, BSD syslog time format is set with `syslog-time-format=bsd-syslog` separately from `remote-log-format=syslog`. Both must be set for correct parsing.

# InfluxDB for Homelab Monitoring

InfluxDB 2.x deployment for collecting and storing time-series metrics, particularly from Proxmox hosts and other infrastructure components.

## Overview

This deployment provides:
- InfluxDB 2.x for high-performance time series data storage
- Web UI accessible at https://influxdb.sean.local
- Prometheus metrics endpoint for monitoring InfluxDB itself
- 90-day data retention policy
- Integration ready for Proxmox, Telegraf, and other metrics collectors

## Architecture

```
Proxmox Hosts → Telegraf/InfluxDB Plugin → InfluxDB ← Grafana Dashboards
                                              ↓
                                         Prometheus (metrics)
```

## Access

- **URL**: https://influxdb.sean.local
- **Username**: admin
- **Password**: Retrieved from Kubernetes secret (see below)
- **Organization**: homelab
- **Default Bucket**: proxmox

## Configuration

### Get Admin Password

```bash
kubectl get secret influxdb-influxdb2-auth -n monitoring -o jsonpath="{.data.admin-password}" | base64 -d
```

### Create API Token for Proxmox

1. Access the InfluxDB UI
2. Navigate to Data → API Tokens
3. Click "Generate API Token" → "Custom API Token"
4. Configure permissions:
   - Read/Write access to `proxmox` bucket
   - Name: `proxmox-metrics`
5. Copy the generated token

## Proxmox Integration

### Option 1: Built-in InfluxDB Plugin (Recommended)

On each Proxmox node:

```bash
# Add InfluxDB metric server in Proxmox
pvesh create /cluster/metrics/server/influxdb \
  --server influxdb.sean.local \
  --port 443 \
  --protocol https \
  --organization homelab \
  --bucket proxmox \
  --token "YOUR_API_TOKEN_HERE"
```

Or via Proxmox UI:
1. Datacenter → Metric Server → Add → InfluxDB
2. Configure:
   - Server: influxdb.sean.local
   - Port: 443
   - Protocol: HTTPS
   - Organization: homelab
   - Bucket: proxmox
   - Token: (paste API token)

### Option 2: Telegraf Agent

Install Telegraf on Proxmox nodes for more detailed metrics:

```bash
# Install Telegraf
wget -q https://repos.influxdata.com/influxdata-archive_compat.key
echo '393e8779c89ac8d958f81f942f9ad7fb82a25e133faddaf92e15b16e6ac9ce4c influxdata-archive_compat.key' | sha256sum -c && cat influxdata-archive_compat.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg > /dev/null
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/influxdata-archive_compat.gpg] https://repos.influxdata.com/debian stable main' | sudo tee /etc/apt/sources.list.d/influxdata.list
sudo apt-get update && sudo apt-get install telegraf

# Configure Telegraf
cat > /etc/telegraf/telegraf.conf << EOF
[global_tags]
  host = "$HOSTNAME"
  datacenter = "homelab"

[agent]
  interval = "30s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  hostname = "$HOSTNAME"
  omit_hostname = false

[[outputs.influxdb_v2]]
  urls = ["https://influxdb.sean.local"]
  token = "YOUR_API_TOKEN_HERE"
  organization = "homelab"
  bucket = "proxmox"
  insecure_skip_verify = true

[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs", "iso9660", "overlay", "aufs", "squashfs"]

[[inputs.diskio]]

[[inputs.kernel]]

[[inputs.mem]]

[[inputs.processes]]

[[inputs.swap]]

[[inputs.system]]

[[inputs.net]]
  interfaces = ["enp*", "vmbr*"]

[[inputs.procstat]]
  pattern = "pve"

EOF

# Start Telegraf
systemctl enable --now telegraf
```

## Grafana Integration

### Add InfluxDB Data Source

1. In Grafana, go to Configuration → Data Sources
2. Click "Add data source" → InfluxDB
3. Configure:
   - Query Language: Flux
   - URL: http://influxdb.monitoring.svc.cluster.local:8086
   - Auth: Skip TLS Verify
   - Organization: homelab
   - Token: (create a read-only token in InfluxDB)
   - Default Bucket: proxmox

### Import Dashboards

Recommended Grafana dashboards for Proxmox:
- [Proxmox VE Dashboard](https://grafana.com/grafana/dashboards/10048) - ID: 10048
- [Proxmox Cluster](https://grafana.com/grafana/dashboards/15356) - ID: 15356
- [Telegraf System Dashboard](https://grafana.com/grafana/dashboards/928) - ID: 928

## Backup and Restore

### Backup

```bash
# Create backup
kubectl exec -n monitoring influxdb-0 -- influx backup /tmp/backup -t YOUR_ADMIN_TOKEN

# Copy backup locally
kubectl cp monitoring/influxdb-0:/tmp/backup ./influxdb-backup
```

### Restore

```bash
# Copy backup to pod
kubectl cp ./influxdb-backup monitoring/influxdb-0:/tmp/backup

# Restore
kubectl exec -n monitoring influxdb-0 -- influx restore /tmp/backup -t YOUR_ADMIN_TOKEN
```

## Monitoring

InfluxDB exposes Prometheus metrics on port 8086 at `/metrics`. These are automatically scraped by Prometheus via the ServiceMonitor.

Key metrics to monitor:
- `influxdb_write_points_total` - Write throughput
- `influxdb_query_request_duration_seconds` - Query performance
- `influxdb_storage_shard_disk_size` - Storage usage
- `influxdb_http_request_duration_seconds` - API latency

## Troubleshooting

### Check InfluxDB Status

```bash
kubectl logs -n monitoring influxdb-0
kubectl describe pod -n monitoring influxdb-0
```

### Test Connection from Proxmox

```bash
# From Proxmox node
curl -k https://influxdb.sean.local/health
```

### Common Issues

1. **Connection refused from Proxmox**
   - Check DNS resolution
   - Verify certificate trust
   - Check firewall rules

2. **No data in Grafana**
   - Verify API token permissions
   - Check bucket name
   - Test query in InfluxDB UI

3. **High memory usage**
   - Adjust retention policies
   - Configure downsampling tasks
   - Increase resource limits

## Maintenance

### Update Retention Policy

```bash
kubectl exec -n monitoring influxdb-0 -- influx bucket update \
  --id $(kubectl exec -n monitoring influxdb-0 -- influx bucket list -n proxmox --json | jq -r '.[0].id') \
  --retention 180d \
  -t YOUR_ADMIN_TOKEN
```

### Create Downsampling Task

For long-term storage efficiency, create a downsampling task in the InfluxDB UI under Tasks.

## References

- [InfluxDB 2.x Documentation](https://docs.influxdata.com/influxdb/v2/)
- [Proxmox External Metric Server](https://pve.proxmox.com/wiki/External_Metric_Server)
- [Telegraf Documentation](https://docs.influxdata.com/telegraf/)
- [InfluxDB Helm Chart](https://github.com/influxdata/helm-charts/tree/master/charts/influxdb2)
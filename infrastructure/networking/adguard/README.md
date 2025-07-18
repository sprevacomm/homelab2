# AdGuard Home DNS Server

AdGuard Home is a network-wide DNS server with ad/tracker blocking capabilities.

## Features

- **DNS Ad Blocking** - Blocks ads and trackers at the DNS level
- **Modern DNS Protocols** - Supports DoH, DoT, and DoQ
- **Local DNS Records** - Define custom DNS entries for internal services
- **Web UI** - Modern, responsive interface
- **Statistics** - DNS query analytics and blocking stats

## Access

- **Web UI**: https://adguard.susdomain.name
- **DNS Server**: 192.168.1.201:53
- **DNS-over-TLS**: 192.168.1.201:853
- **Default Login**: admin/admin (CHANGE THIS!)

## Configuration

### Network Setup

1. **Configure your router**:
   - Set primary DNS to: `192.168.1.201`
   - Set secondary DNS to: `1.1.1.1` (fallback)

2. **Or configure individual devices**:
   - Windows: Network adapter settings
   - macOS: System Preferences → Network → Advanced → DNS
   - Linux: `/etc/resolv.conf` or NetworkManager

### Local DNS Entries

All `*.susdomain.name` domains are configured to resolve to the Traefik LoadBalancer IP (192.168.1.200).

To add custom entries, edit the `rewrites` section in `configmap.yaml`:

```yaml
rewrites:
- domain: "myapp.susdomain.name"
  answer: "192.168.1.200"
```

### Changing Admin Password

1. Generate new password hash:
   ```bash
   docker run --rm adguard/adguardhome:latest --help | grep -A5 password
   # Or use online bcrypt generator
   ```

2. Update `configmap.yaml` with new hash
3. Sync the application:
   ```bash
   argocd app sync adguard-home
   ```

### Adding Block Lists

Edit the `filters` section in `configmap.yaml` to add/remove block lists:

```yaml
filters:
- enabled: true
  url: https://example.com/blocklist.txt
  name: Custom Blocklist
  id: 10
```

## Monitoring

AdGuard Home exposes Prometheus metrics at `/metrics` endpoint.

ServiceMonitor is included for automatic Prometheus discovery.

## Troubleshooting

### DNS Not Resolving

```bash
# Test DNS resolution
nslookup google.com 192.168.1.201

# Check pod status
kubectl get pods -n adguard
kubectl logs -n adguard deployment/adguard-home
```

### Can't Access Web UI

```bash
# Check ingress
kubectl get ingress -n adguard
kubectl describe ingress adguard-home -n adguard

# Port-forward for direct access
kubectl port-forward -n adguard deployment/adguard-home 3000:3000
# Access at http://localhost:3000
```

### High Memory Usage

AdGuard uses ~250MB RAM by default. To reduce:
- Decrease cache size in config
- Reduce query log retention
- Disable unnecessary block lists

## Backup

Important data to backup:
- `/opt/adguardhome/work/` - Statistics and query logs
- ConfigMap - Your configuration

## Why AdGuard Home?

Chosen over Pi-hole for:
- Better Kubernetes integration
- Modern DNS protocol support (DoH, DoT, DoQ)
- Configuration as code
- Active development
- Better container support
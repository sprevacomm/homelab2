# Infrastructure Bootstrap

This directory contains the unified infrastructure bootstrap system for the homelab platform.

## Architecture Overview

The homelab follows a two-layer architecture:

### Platform Layer (Bootstrap)
Core infrastructure components that are manually deployed once:
- **Storage Class** - Persistent storage provider
- **MetalLB** - LoadBalancer service provider
- **AdGuard Home** - Local DNS server
- **Traefik** - Ingress controller
- **Cert-Manager** - SSL certificate management
- **Rancher** - Kubernetes management UI
- **ArgoCD** - GitOps controller

### Application Layer (GitOps)
Applications managed by ArgoCD:
- Prometheus/Grafana monitoring stack
- InfluxDB for time-series data
- Loki for log aggregation
- Velero for backups
- Future applications

## Quick Start

```bash
# Run the unified bootstrap script
./bootstrap-infrastructure.sh

# Or with custom configuration
./bootstrap-infrastructure.sh \
  --metallb-range "192.168.1.200-192.168.1.250" \
  --domain "homelab.local" \
  --acme-email "admin@homelab.local"
```

## Prerequisites

Before running the bootstrap:

1. **Kubernetes Cluster**: A working K3s/K8s cluster
2. **Tools**: kubectl, helm, git, curl installed
3. **Network Planning**: 
   - Available IP range for MetalLB (outside DHCP range)
   - Domain name for services
   - Valid email for Let's Encrypt

## Configuration Options

The bootstrap script accepts the following options:

| Option | Description | Default |
|--------|-------------|---------|
| `--metallb-range` | IP range for LoadBalancer services | `192.168.1.200-192.168.1.250` |
| `--domain` | Domain name for services | `homelab.local` |
| `--acme-email` | Email for Let's Encrypt certificates | `admin@homelab.local` |
| `--dry-run` | Show what would be installed without making changes | `false` |
| `--yes` | Skip confirmation prompts | `false` |

## Component Details

### Storage Class
- **Implementation**: Rancher local-path-provisioner
- **Purpose**: Provides persistent storage for stateful applications
- **Storage Location**: Node local storage at `/opt/local-path-provisioner`

### MetalLB
- **Purpose**: Provides LoadBalancer service type in bare-metal environments
- **Mode**: Layer 2 (ARP/NDP)
- **Configuration**: IP address pool for service allocation

### AdGuard Home
- **Purpose**: Network-wide DNS server and ad blocker
- **Default Credentials**: admin/admin (CHANGE IMMEDIATELY)
- **Services**:
  - Web UI: Port 3000
  - DNS: Port 53 (TCP/UDP)

### Traefik
- **Purpose**: Kubernetes ingress controller and reverse proxy
- **Features**:
  - Automatic HTTPS with Let's Encrypt
  - HTTP to HTTPS redirect
  - Kubernetes CRD support
  - Prometheus metrics

### Cert-Manager
- **Purpose**: Automatic SSL certificate management
- **Issuers**:
  - `letsencrypt-prod`: Production certificates
  - `letsencrypt-staging`: Testing certificates

### Rancher
- **Purpose**: Kubernetes cluster management UI
- **Features**:
  - Multi-cluster management
  - User/RBAC management
  - Application catalog
  - Monitoring integration

### ArgoCD
- **Purpose**: GitOps continuous delivery
- **Configuration**:
  - Watches `gitops/applications/` directory
  - Auto-sync enabled for applications
  - Prometheus metrics exposed

## Post-Installation Steps

1. **Configure DNS**:
   ```bash
   # Get Traefik LoadBalancer IP
   kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   
   # Add wildcard DNS record
   *.homelab.local → <Traefik-IP>
   ```

2. **Change Default Passwords**:
   - AdGuard: http://<AdGuard-IP>:3000
   - Rancher: https://rancher.homelab.local
   - ArgoCD: https://argocd.homelab.local

3. **Configure AdGuard as DNS Server**:
   - Set router/DHCP to use AdGuard IP as DNS
   - Configure upstream DNS servers in AdGuard
   - Add custom DNS entries for local services

4. **Deploy Applications**:
   ```bash
   # Apply application manifests
   kubectl apply -f ../../gitops/applications/
   ```

## Troubleshooting

### MetalLB Issues
```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# Check IP allocation
kubectl get svc --all-namespaces -o wide | grep LoadBalancer

# Check MetalLB configuration
kubectl get ipaddresspool,l2advertisement -n metallb-system
```

### DNS Resolution Issues
```bash
# Test AdGuard DNS
nslookup google.com <AdGuard-IP>

# Check AdGuard logs
kubectl logs -n adguard deployment/adguard-adguard-home
```

### Certificate Issues
```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Check certificate status
kubectl get certificates --all-namespaces

# Check ClusterIssuers
kubectl get clusterissuers
```

### Access Issues
```bash
# Check ingress routes
kubectl get ingress,ingressroute --all-namespaces

# Check Traefik logs
kubectl logs -n traefik deployment/traefik
```

## Disaster Recovery

To rebuild the platform from scratch:

1. Ensure you have backups of:
   - This Git repository
   - Any customized values files
   - Application data (if using external storage)

2. Run the bootstrap script on a fresh cluster:
   ```bash
   ./bootstrap-infrastructure.sh
   ```

3. Restore application data from backups

4. Apply GitOps applications:
   ```bash
   kubectl apply -f ../../gitops/applications/
   ```

## Security Considerations

1. **Change all default passwords immediately**
2. **Use strong passwords and enable MFA where possible**
3. **Keep the Git repository private if it contains sensitive values**
4. **Regularly update all components**
5. **Configure network policies for additional security**
6. **Use sealed-secrets for sensitive data in Git**

## Maintenance

### Updating Components

Platform components should be updated carefully:

```bash
# Check current versions
helm list --all-namespaces

# Update a component (example: Traefik)
helm upgrade traefik traefik/traefik \
  --namespace traefik \
  --version <new-version> \
  --reuse-values
```

### Backup Recommendations

1. **Git Repository**: Regular commits and remote backup
2. **Persistent Volumes**: Regular snapshots or backup to external storage
3. **Certificates**: Backed up automatically by cert-manager
4. **Application Data**: Use Velero for cluster-wide backups

## Reference

- [MetalLB Documentation](https://metallb.universe.tf/)
- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Cert-Manager Documentation](https://cert-manager.io/docs/)
- [Rancher Documentation](https://rancher.com/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [AdGuard Home Documentation](https://github.com/AdguardTeam/AdGuardHome/wiki)
# Homelab Infrastructure Improvements Roadmap

This document outlines recommended improvements for making the homelab infrastructure more secure, reliable, and production-ready.

## 🏗️ 0. Architecture Refactoring (Priority: Critical)

### Platform/Application Layer Separation
**Status:** In Progress

**Current Issue:**
- ArgoCD manages core infrastructure components (MetalLB, Traefik, etc.)
- Circular dependencies and bootstrap complexity
- Difficult to recover from cluster failures

**New Architecture:**
- **Platform Layer (Manual Bootstrap):**
  1. Storage Class (local-path-provisioner)
  2. MetalLB (LoadBalancer provider)
  3. AdGuard (Local DNS)
  4. Traefik (Ingress controller)
  5. Cert-Manager (SSL certificates)
  6. Rancher (Kubernetes management)
  7. ArgoCD (GitOps for applications)

- **Application Layer (ArgoCD Managed):**
  - Prometheus/Grafana monitoring
  - InfluxDB (time series data)
  - Loki (log aggregation)
  - Velero (backups)
  - Future applications

**Benefits:**
- Clear separation of concerns
- Stable platform foundation
- Easier disaster recovery
- No circular dependencies
- DNS available from the start

**Implementation:**
```bash
# New bootstrap structure
infrastructure/bootstrap/
├── 01-storage-class.sh
├── 02-metallb.sh
├── 03-adguard.sh
├── 04-traefik.sh
├── 05-cert-manager.sh
├── 06-rancher.sh
├── 07-argocd.sh
└── bootstrap-all.sh

# New GitOps structure
gitops/
├── bootstrap/
│   └── applications.yaml    # Parent app-of-apps for applications only
└── applications/           # Renamed from 'infrastructure'
    ├── monitoring.yaml     # Prometheus/Grafana stack
    ├── influxdb.yaml      # Time series database
    ├── loki.yaml          # Log aggregation
    ├── velero.yaml        # Backups
    └── sealed-secrets.yaml # Secret management
```

## 📊 1. Enhanced Observability

### Loki for Logs (Priority: High)
**Status:** Configuration created at `gitops/infrastructure/loki.yaml`

**Features:**
- Centralized log aggregation
- Integration with Grafana
- Log correlation with metrics
- 7-day retention by default

**Implementation:**
```bash
kubectl apply -f gitops/infrastructure/loki.yaml
```

### InfluxDB for Time Series Data (Priority: High)
**Status:** Planned

**Features:**
- High-performance time series database
- Native Proxmox metrics collection support
- Integration with Grafana dashboards
- Long-term metrics retention
- Support for custom metrics and telegraf agents

**Use Cases:**
- Proxmox host metrics (CPU, memory, disk, network)
- VM/Container performance metrics
- Storage performance tracking
- Network throughput monitoring
- Custom application metrics

**Implementation:**
```bash
# To be created at gitops/infrastructure/influxdb.yaml
kubectl apply -f gitops/infrastructure/influxdb.yaml
```

### Additional Prometheus Targets (Priority: High)
**Status:** Created at `infrastructure/monitoring/kube-prometheus-stack/manifests/base/additional-scrape-configs.yaml`

**Monitors:**
- ArgoCD metrics
- cert-manager metrics
- Sealed Secrets metrics
- Blackbox exporter for endpoint monitoring

## 💾 2. Backup & Disaster Recovery

### Velero (Priority: High)
**Status:** Configuration created at `gitops/infrastructure/velero.yaml`

**Features:**
- Automated daily backups
- 30-day retention
- Disaster recovery capability
- Namespace or cluster-level backups

**Implementation:**
```bash
kubectl apply -f gitops/infrastructure/velero.yaml
```

## 🔧 3. Developer Experience

### Makefile (Priority: High)
**Status:** Created at project root

**Commands:**
- `make install` - Complete installation
- `make status` - Check infrastructure
- `make test-ingress` - Test all endpoints
- `make backup` - Create backups

### CI/CD Integration (Priority: Medium)
**Status:** GitHub Actions workflow at `.github/workflows/validate.yaml`

**Features:**
- YAML validation
- Kubernetes manifest validation
- Security scanning with Trivy
- ArgoCD diff on PRs

## 🌍 4. Multi-Environment Support

### Kustomize Overlays (Priority: Medium)
**Status:** Documentation at `infrastructure/docs/ENVIRONMENTS.md`

**Enables:**
- Dev/Staging/Prod environments
- Environment-specific configurations
- Safe testing before production
- GitOps for all environments

## 🔐 5. Certificate Management

### cert-manager (Priority: Medium)
**Status:** Configuration created at `gitops/infrastructure/cert-manager.yaml`

**Advantages over Traefik's built-in:**
- More certificate types (not just Let's Encrypt)
- Better lifecycle management
- Certificate rotation automation
- Wildcard certificate support
- DNS-01 challenge support

## 🚀 6. Additional Features

### Service Mesh (Priority: Low)
Consider Istio or Linkerd for:
- mTLS between services
- Advanced traffic management
- Circuit breaking
- Canary deployments

### GitOps Image Updates (Priority: Low)
**ArgoCD Image Updater** for:
- Automatic container updates
- Security patch automation
- Version pinning policies

### Infrastructure as Code (Priority: Medium)
**Crossplane** for:
- Cloud resource management
- Database provisioning
- Unified control plane

## 🔒 7. Security Enhancements

### Sealed Secrets (Priority: Low)
**Status:** Configuration created at `gitops/infrastructure/sealed-secrets.yaml`

- Encrypts secrets in Git repositories
- Prevents exposing passwords in plain text
- Only the cluster can decrypt

**Implementation:**
```bash
kubectl apply -f gitops/infrastructure/sealed-secrets.yaml
```

### Network Policies (Priority: Low)
**Status:** Basic policies created at `infrastructure/security/network-policies/`

- Zero-trust network security
- Default deny all traffic
- Explicit allow rules only

**Benefits:**
- Prevents lateral movement in case of compromise
- Isolates workloads
- Compliance ready

### Resource Quotas (Priority: Low)
**Status:** Templates created at `infrastructure/security/resource-quotas/`

- Prevents resource exhaustion
- Fair resource distribution
- Cost control in cloud environments

### Policy Enforcement (Priority: Low)
**OPA Gatekeeper** for:
- Enforce security policies
- Compliance requirements
- Resource naming conventions
- Required labels/annotations

### Runtime Security (Priority: Low)
**Falco** for:
- Detect anomalous behavior
- Runtime threat detection
- Compliance monitoring
- Incident response

## 📋 Implementation Priority

### Phase 0: Architecture Refactoring (Immediate)
1. ⏳ Refactor to Platform/Application layer separation
2. ⏳ Create bootstrap scripts for platform components
3. ⏳ Move core infrastructure out of GitOps
4. ⏳ Update ArgoCD to manage only applications

### Phase 1: Observability & Reliability (Week 1)
1. ✅ Enhanced monitoring dashboards
2. ✅ Loki for centralized logs
3. ⏳ InfluxDB for Proxmox metrics
4. ✅ Backup solution (Velero)
5. ✅ Additional Prometheus targets

### Phase 2: Developer Experience (Week 2)
1. ✅ Makefile for common tasks
2. ✅ CI/CD pipeline
3. ⏳ Documentation improvements
4. ⏳ Test automation

### Phase 3: Operations (Week 3)
1. ✅ cert-manager
2. ⏳ Multi-environment setup
3. ⏳ GitOps image updater
4. ⏳ Crossplane evaluation

### Phase 4: Security Hardening (Month 2)
1. ⏳ Sealed Secrets
2. ⏳ Network Policies
3. ⏳ Resource Quotas
4. ⏳ Policy enforcement
5. ⏳ Runtime security

## 💰 Resource Requirements

### Additional CPU/Memory Needs:
- Loki: 200m CPU, 256Mi RAM
- InfluxDB: 1 CPU, 2Gi RAM
- Velero: 500m CPU, 256Mi RAM
- cert-manager: 100m CPU, 128Mi RAM
- Sealed Secrets: 100m CPU, 128Mi RAM
- Service Mesh: 1-2 CPU, 2-4Gi RAM

### Storage Requirements:
- Loki logs: 20-50Gi
- InfluxDB data: 50-100Gi
- Velero backups: 50-100Gi
- Prometheus (extended): +20Gi

## 🎯 Success Metrics

### Observability
- [ ] All services monitored
- [ ] Logs centralized
- [ ] Alerts configured
- [ ] Dashboards created

### Reliability
- [ ] Daily backups running
- [ ] <5 minute recovery time
- [ ] 99.9% uptime
- [ ] Automated testing

### Operations
- [ ] All changes via GitOps
- [ ] Automated certificate renewal
- [ ] Self-healing enabled
- [ ] Multi-env support

### Security
- [ ] All secrets encrypted
- [ ] Network policies enforced
- [ ] Regular security scans passing
- [ ] Resource limits enforced

## 🛠️ Quick Implementation

To implement improvements by priority:

```bash
# Phase 0: Architecture Refactoring (Do this first!)
cd infrastructure/bootstrap
./01-storage-class.sh
./02-metallb.sh
./03-adguard.sh
./04-traefik.sh
./05-cert-manager.sh
./06-rancher.sh
./07-argocd.sh
# OR simply run:
./bootstrap-all.sh

# Phase 1: Observability & Reliability (via ArgoCD)
kubectl apply -f gitops/applications/monitoring.yaml
kubectl apply -f gitops/applications/influxdb.yaml
kubectl apply -f gitops/applications/loki.yaml
kubectl apply -f gitops/applications/velero.yaml

# Phase 2: Developer Experience
# Use the Makefile
make status
make test-applications

# Phase 3: Security (when ready)
kubectl apply -f gitops/applications/sealed-secrets.yaml
kubectl apply -f infrastructure/security/network-policies/base/
kubectl apply -f infrastructure/security/resource-quotas/
```

## 📚 References

- [Loki Documentation](https://grafana.com/docs/loki/)
- [Velero Documentation](https://velero.io/docs/)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Sealed Secrets Documentation](https://sealed-secrets.netlify.app/)
- [Network Policies Guide](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

---

**Note:** This roadmap prioritizes operational improvements and observability over security hardening, making it more suitable for homelab environments where learning and experimentation are primary goals. Security features are still included but scheduled for later implementation.
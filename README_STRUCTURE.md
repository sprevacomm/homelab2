# Homelab Repository Structure

This repository implements a modern infrastructure-as-code approach with three distinct deployment methods: unified bootstrap scripts, Terraform modules, and GitOps for applications.

## Directory Structure

```
homelab2/
├── infrastructure/             # Bootstrap scripts and configurations
│   ├── bootstrap/             # Unified platform deployment
│   │   ├── bootstrap-infrastructure.sh  # Main deployment script
│   │   ├── cleanup-cluster.sh          # Standard cleanup
│   │   ├── force-cleanup.sh            # Nuclear cleanup
│   │   ├── cleanup-helm-hooks.sh       # Helm-specific cleanup
│   │   └── README.md                   # Bootstrap documentation
│   └── monitoring/            # Application configurations
│       ├── influxdb/         # Time-series database
│       │   ├── values/       # Helm values
│       │   └── README.md     # InfluxDB setup guide
│       └── kube-prometheus-stack/
│           └── values/       # Prometheus/Grafana configuration
│
├── infra/                     # Terraform infrastructure-as-code
│   ├── .gitignore            # Terraform-specific ignores
│   ├── versions.tf           # Provider version constraints
│   ├── providers.tf          # Provider configurations
│   ├── variables.tf          # Input variables
│   ├── main.tf              # Root module composition
│   ├── terraform.tfvars.example  # Example configuration
│   └── modules/             # Reusable Terraform modules
│       ├── storage-class/   # Local storage provisioner
│       ├── mlb/            # MetalLB (placeholder)
│       ├── adblock/        # AdGuard (placeholder)
│       ├── traefik/        # Ingress controller (placeholder)
│       ├── certmgr/        # cert-manager (placeholder)
│       ├── rancher/        # Kubernetes management (placeholder)
│       └── promethus/      # Monitoring stack (placeholder)
│
├── gitops/                   # ArgoCD managed applications ONLY
│   ├── bootstrap/           
│   │   └── applications.yaml # App-of-apps for application layer
│   └── applications/        # Application definitions (future)
│       ├── monitoring.yaml  # Prometheus/Grafana
│       ├── influxdb.yaml   # Time-series metrics
│       ├── loki.yaml       # Log aggregation
│       └── velero.yaml     # Backup solution
│
├── docs/                    # Project documentation
│   ├── IMPROVEMENTS_ROADMAP.md  # Architecture evolution
│   └── SECRETS_MANAGEMENT.md    # SOPS + Age guide
│
├── scripts/                 # Utility scripts
│   └── cleanup-cluster.sh  # Legacy cleanup
│
└── README_STRUCTURE.md     # This file
```

## Architecture Overview

### Three-Layer Approach

1. **Platform Layer** (Bootstrap Scripts or Terraform)
   - Core infrastructure that rarely changes
   - Deployed once during initial setup
   - Includes: Storage, Networking, DNS, Ingress, SSL, Management UI

2. **GitOps Layer** (ArgoCD)
   - Manages application deployments
   - Continuous reconciliation from Git
   - Only manages non-platform components

3. **Application Layer** (Via GitOps)
   - Monitoring, logging, backups
   - Business applications
   - Frequently updated components

### Deployment Methods

#### Option 1: Bootstrap Script (Simple)
```bash
cd infrastructure/bootstrap
./bootstrap-infrastructure.sh \
  --metallb-range "192.168.1.200-192.168.1.250" \
  --domain "homelab.local" \
  --acme-email "admin@homelab.local"
```

#### Option 2: Terraform (Infrastructure as Code)
```bash
cd infra
terraform init
terraform plan
terraform apply
```

#### Then: GitOps for Applications
```bash
kubectl apply -f gitops/applications/
```

## Key Design Decisions

### Why Platform/Application Separation?

1. **No Circular Dependencies**
   - ArgoCD doesn't manage itself or its dependencies
   - Platform components don't depend on GitOps

2. **Stability**
   - Platform rarely changes after initial setup
   - Applications can be updated frequently

3. **Disaster Recovery**
   - Platform can be quickly restored with script/Terraform
   - Applications restored via GitOps

### Platform Components

| Component | Purpose | Why Platform? |
|-----------|---------|---------------|
| Storage Class | Persistent volumes | Foundation for all stateful apps |
| MetalLB | LoadBalancer IPs | Required for service exposure |
| AdGuard | DNS server | Name resolution for all services |
| Traefik | Ingress controller | HTTP/HTTPS routing |
| cert-manager | SSL certificates | Security foundation |
| Rancher | K8s management | Cluster operations |
| ArgoCD | GitOps controller | Manages applications |

### Application Components

| Component | Purpose | Why Application? |
|-----------|---------|-----------------|
| Prometheus/Grafana | Monitoring | Frequently updated, many configs |
| InfluxDB | Time-series DB | Application-specific metrics |
| Loki | Log aggregation | Optional component |
| Velero | Backups | Optional, policy-driven |

## Adding New Components

### For Platform Components (Terraform):

1. Create new module:
   ```bash
   mkdir -p infra/modules/component-name
   ```

2. Add module files:
   ```
   modules/component-name/
   ├── README.md      # Module documentation
   ├── main.tf        # Resources
   ├── variables.tf   # Input variables
   ├── outputs.tf     # Output values
   └── versions.tf    # Provider requirements
   ```

3. Use in root module:
   ```hcl
   module "component_name" {
     source = "./modules/component-name"
     # ... configuration
   }
   ```

### For Applications (GitOps):

1. Create application manifest:
   ```yaml
   # gitops/applications/app-name.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: app-name
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: https://github.com/yourusername/homelab2
       path: infrastructure/apps/app-name
       targetRevision: main
     destination:
       server: https://kubernetes.default.svc
       namespace: app-namespace
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   ```

2. Add application configuration:
   ```bash
   mkdir -p infrastructure/apps/app-name/values
   ```

## Migration Path

### From Old Architecture to New

1. **Clean cluster** (if needed):
   ```bash
   infrastructure/bootstrap/cleanup-cluster.sh
   ```

2. **Deploy platform** (choose one):
   - Script: `./bootstrap-infrastructure.sh`
   - Terraform: `terraform apply`

3. **Deploy applications**:
   ```bash
   kubectl apply -f gitops/applications/
   ```

## Benefits of This Structure

1. **Clear Architecture**
   - Platform vs Application separation
   - Multiple deployment options (script/Terraform)
   - GitOps for application management

2. **Flexibility**
   - Choose deployment method that fits your needs
   - Easy to switch between methods
   - Modular design

3. **Maintainability**
   - Platform components rarely change
   - Applications easily updated via Git
   - Clear ownership boundaries

4. **Disaster Recovery**
   - Platform: Re-run script or `terraform apply`
   - Applications: ArgoCD auto-syncs from Git
   - No complex state management

## Directory Purposes

| Directory | Purpose | Deployment Method |
|-----------|---------|-------------------|
| `/infrastructure/bootstrap/` | Unified scripts | Manual execution |
| `/infra/` | Terraform modules | `terraform apply` |
| `/gitops/` | ArgoCD applications | GitOps sync |
| `/infrastructure/monitoring/` | App configurations | Referenced by GitOps |
| `/docs/` | Documentation | N/A |
| `/scripts/` | Utilities | Manual execution |
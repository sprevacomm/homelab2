# Homelab Repository Structure

This repository follows a clean separation between GitOps application definitions and infrastructure components.

## Directory Structure

```
homelab2/
├── gitops/                      # ArgoCD Application definitions ONLY
│   ├── bootstrap/              # Bootstrap applications
│   │   └── infrastructure.yaml # App-of-apps for infrastructure
│   ├── infrastructure/         # Infrastructure application definitions
│   │   ├── metallb.yaml       # MetalLB load balancer
│   │   ├── metallb-config.yaml # MetalLB configuration
│   │   ├── traefik.yaml       # Traefik ingress controller
│   │   ├── traefik-config.yaml # Traefik configuration
│   │   ├── adguard.yaml       # AdGuard DNS server
│   │   ├── monitoring.yaml    # Prometheus/Grafana stack
│   │   └── monitoring-config.yaml # Monitoring configuration
│   └── apps/                   # Future application definitions
│
├── infrastructure/             # Actual infrastructure manifests and configs
│   ├── bootstrap/             # ArgoCD bootstrap files
│   │   ├── bootstrap.sh       # Initial ArgoCD installation script
│   │   ├── values/           # ArgoCD Helm values
│   │   └── manifests/        # Additional ArgoCD resources
│   ├── networking/           # Network layer components
│   │   ├── metallb/         # Load balancer for bare metal
│   │   │   ├── values/      # Helm chart values
│   │   │   └── manifests/   # IP pools, L2 advertisements
│   │   ├── traefik/         # Ingress controller
│   │   │   ├── values/      # Helm chart values  
│   │   │   └── manifests/   # IngressRoutes, middleware
│   │   └── adguard/         # DNS server
│   │       └── manifests/   # Deployment, services, config
│   ├── monitoring/          # Observability stack
│   │   └── kube-prometheus-stack/
│   │       ├── values/      # Prometheus/Grafana configuration
│   │       └── manifests/   # ServiceMonitors, alert rules
│   └── docs/               # Documentation
│       ├── INSTALLATION_SEQUENCE.md
│       ├── TROUBLESHOOTING.md
│       ├── LOCAL_ACCESS.md
│       └── prerequisites.sh
│
└── README_STRUCTURE.md     # This file
```

## Key Concepts

### GitOps Pattern

1. **GitOps Directory** (`/gitops/`)
   - Contains ONLY ArgoCD Application CRDs
   - No actual infrastructure manifests
   - Organized by application type (infrastructure, apps)
   - Each app points to manifests in `/infrastructure/` or `/apps/`

2. **Infrastructure Directory** (`/infrastructure/`)
   - Contains actual Kubernetes manifests
   - Helm values files
   - Configuration files
   - Scripts and documentation

### Application Organization

Each infrastructure component follows this pattern:

```
component/
├── values/              # Helm chart values (if using Helm)
│   └── values.yaml
└── manifests/          # Additional Kubernetes manifests
    └── *.yaml          # ConfigMaps, custom resources, etc.
```

## Installation Flow

1. **Bootstrap ArgoCD**
   ```bash
   cd infrastructure/bootstrap
   ./bootstrap.sh
   ```

2. **Deploy Infrastructure**
   ```bash
   kubectl apply -f gitops/bootstrap/infrastructure.yaml
   ```

3. **Components Deploy in Order** (via sync waves):
   - Wave -3: MetalLB (provides LoadBalancer IPs)
   - Wave -2: MetalLB configuration
   - Wave -1: Traefik, AdGuard (networking layer)
   - Wave 0: Monitoring, Traefik config
   - Wave 1: Monitoring config

## Adding New Components

### For Infrastructure:

1. Create manifest directory:
   ```bash
   mkdir -p infrastructure/category/component/{values,manifests}
   ```

2. Add manifests/values files

3. Create ArgoCD application:
   ```yaml
   # gitops/infrastructure/component.yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: component
     namespace: argocd
   spec:
     source:
       repoURL: https://github.com/sprevacomm/homelab2.git
       targetRevision: main
       path: infrastructure/category/component/manifests
   ```

### For Applications:

Similar pattern but under `/apps/` directory.

## Benefits of This Structure

1. **Clear Separation of Concerns**
   - GitOps definitions separate from actual manifests
   - Easy to understand what deploys what

2. **Reusability**
   - Infrastructure can be referenced by multiple environments
   - GitOps apps can point to different branches/tags

3. **Maintainability**
   - Updates to infrastructure don't require GitOps changes
   - Easy to track what ArgoCD is managing

4. **Scalability**
   - Add new apps without cluttering infrastructure
   - Organize by function (networking, monitoring, security)
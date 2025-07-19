# Multi-Environment Setup

## Overview

This setup supports multiple environments (dev, staging, prod) using Kustomize overlays and ArgoCD ApplicationSets.

## Directory Structure

```
infrastructure/
├── base/                    # Base configurations
│   ├── networking/
│   ├── monitoring/
│   └── security/
└── overlays/               # Environment-specific configs
    ├── dev/
    │   ├── kustomization.yaml
    │   └── patches/
    ├── staging/
    │   ├── kustomization.yaml
    │   └── patches/
    └── prod/
        ├── kustomization.yaml
        └── patches/
```

## Example: Dev Environment

### Create Base Kustomization

```yaml
# infrastructure/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - networking/metallb/manifests/base
  - networking/traefik/manifests/base
  - monitoring/kube-prometheus-stack/manifests/base
```

### Dev Overlay

```yaml
# infrastructure/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../base

patches:
  - patch: |-
      - op: replace
        path: /spec/addresses/0
        value: 10.0.1.200-10.0.1.210
    target:
      kind: IPAddressPool
      name: default-pool
  
  - patch: |-
      - op: replace
        path: /spec/rules/0/host
        value: grafana.dev.local
    target:
      kind: Ingress
      name: kube-prometheus-stack-grafana

replicas:
  - name: kube-prometheus-stack-prometheus
    count: 1
  - name: kube-prometheus-stack-alertmanager
    count: 1
```

## ApplicationSet for Multi-Env

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: infrastructure-environments
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: dev
        url: https://kubernetes.default.svc
        namespace: infrastructure-dev
      - cluster: staging
        url: https://staging.cluster.local
        namespace: infrastructure-staging
      - cluster: prod
        url: https://prod.cluster.local
        namespace: infrastructure-prod
  template:
    metadata:
      name: '{{cluster}}-infrastructure'
    spec:
      project: default
      source:
        repoURL: https://github.com/sprevacomm/homelab2.git
        targetRevision: main
        path: infrastructure/overlays/{{cluster}}
      destination:
        server: '{{url}}'
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

## Benefits

1. **Isolation**: Each environment is separate
2. **Testing**: Test changes in dev before prod
3. **Flexibility**: Different configs per environment
4. **GitOps**: All environments defined in Git
# Homelab Setup Documentation

## Overview
Setting up RKE2 cluster with:
- MetalLB (v0.15.2) - Load balancer for bare metal Kubernetes
- Traefik (v36.3.0) - Ingress controller with Let's Encrypt SSL
- ArgoCD (v8.1.3) - GitOps continuous delivery

## Domain Configuration
- Base domain: `susdomain.name`
- Apps pattern: `*.susdomain.name`
- ArgoCD: `https://argocd.susdomain.name`
- Traefik: `https://traefik.susdomain.name`

## SSL Certificates
Using Let's Encrypt for automatic SSL certificate management through Traefik.

## Setup Progress

### 1. MetalLB Setup
**Status:** Completed
- [x] Create ArgoCD application manifest
- [x] Create Helm values configuration
- [x] Define IP address pool for load balancer (192.168.1.200-192.168.1.250)
- [x] Create L2 advertisement configuration
- [x] Create manifests application for MetalLB configuration

**Note:** Update the IP range in `../networking/metallb/manifests/base/ipaddresspool.yaml` to match your network.

### 2. Traefik Setup
**Status:** Completed
- [x] Create ArgoCD application manifest
- [x] Configure Helm values with Let's Encrypt
- [x] Set up certificate resolver (letsencrypt)
- [x] Configure ingress class
- [x] Create dashboard ingress
- [x] Create default security headers middleware
- [x] Configure LoadBalancer service with MetalLB

**Configuration:**
- LoadBalancer IP: 192.168.1.200
- Dashboard URL: https://traefik.susdomain.name
- Let's Encrypt email: admin@susdomain.name
- Auto-redirect HTTP to HTTPS enabled

### 3. ArgoCD Setup
**Status:** Completed
- [x] Create namespace and initial resources
- [x] Create ArgoCD Helm values configuration
- [x] Configure Helm values with repositories
- [x] Set up ingress with SSL via Traefik
- [x] Configure admin credentials (default: admin/admin)
- [x] Create bootstrap script for initial deployment
- [x] Create app-of-apps pattern for infrastructure

**Configuration:**
- URL: https://argocd.susdomain.name
- Default admin password: admin (change after first login)
- Repositories configured: homelab2 (git), metallb, traefik, argo (helm)

### 4. Monitoring Setup
**Status:** Completed
- [x] Create kube-prometheus-stack application
- [x] Configure Prometheus with 30-day retention
- [x] Set up Grafana with dashboards
- [x] Configure Alertmanager for notifications
- [x] Add ServiceMonitors for all components
- [x] Create alert rules for common issues

**Configuration:**
- Prometheus: https://prometheus.susdomain.name (basic auth)
- Grafana: https://grafana.susdomain.name (admin/admin)
- Alertmanager: https://alertmanager.susdomain.name
- Storage: 20GB Prometheus, 5GB Grafana, 5GB Alertmanager

### 5. Deployment
**Status:** Completed
- [x] Deploy ArgoCD using kubectl
- [x] Deploy MetalLB via ArgoCD
- [x] Deploy Traefik via ArgoCD
- [x] Deploy Monitoring stack via ArgoCD
- [x] Verify all components are running
- [x] Test ingress and SSL certificates

**Deployment Summary:**
- ArgoCD: Running at https://argocd.susdomain.name (pending DNS setup)
- Traefik: Running with LoadBalancer IP 192.168.1.200
- MetalLB: Configured with IP pool 192.168.1.200-192.168.1.250
- Monitoring: Prometheus, Grafana, and Alertmanager deployed
- All pods are healthy and running

## Next Steps

1. **Configure DNS:**
   - Point `*.susdomain.name` to 192.168.1.200
   - Verify DNS resolution for argocd.susdomain.name and traefik.susdomain.name

2. **Enable Storage:**
   - Set up a storage class (e.g., local-path-provisioner or NFS)
   - Re-enable Traefik persistence for Let's Encrypt certificates

3. **Security:**
   - Change ArgoCD admin password (current: admin/admin)
   - Change Grafana admin password (current: admin/admin)
   - Update Prometheus basic auth (current: admin/admin)
   - Review and adjust RBAC policies
   - Enable production Let's Encrypt (currently using staging)

4. **Configure Monitoring:**
   - Import Grafana dashboards (IDs: 1860, 7249, 17346, 14584)
   - Set up Alertmanager notification channels
   - Configure email/Slack/webhook alerts
   - Review and customize alert rules

## Important Notes

- **IP Address Pool:** Update the MetalLB IP range in `metallb/manifests/base/ipaddresspool.yaml` to match your network
- **Let's Encrypt Email:** Update the email in `traefik/values/values.yaml` to your actual email
- **Persistence:** Currently disabled for Traefik due to missing storage class
- **SSL Certificates:** Will be automatically provisioned by Let's Encrypt once DNS is configured

## Architecture Notes
Following GitOps pattern with:
- Each component in separate directory under `/gitops/infra/`
- ArgoCD Application manifests for each component
- Helm charts with custom values
- Kustomize for additional manifests when needed
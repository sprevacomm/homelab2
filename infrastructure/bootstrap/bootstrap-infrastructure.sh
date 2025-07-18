#!/bin/bash
# Unified Infrastructure Bootstrap Script for Homelab
# This script installs all core platform components in the correct order
# Components: Storage, MetalLB, AdGuard, Traefik, Cert-Manager, Rancher, ArgoCD

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_DIR="${SCRIPT_DIR}/.."
LOG_FILE="${SCRIPT_DIR}/bootstrap-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
DRY_RUN=false
SKIP_CONFIRMATIONS=false
METALLB_IP_RANGE="192.168.1.200-192.168.1.250"
DOMAIN="homelab.local"
ACME_EMAIL="admin@homelab.local"

# Component versions
METALLB_VERSION="0.14.8"
TRAEFIK_VERSION="32.1.0"
CERT_MANAGER_VERSION="v1.16.1"
ADGUARD_VERSION="0.9.0"
RANCHER_VERSION="2.10.0"
ARGOCD_VERSION="7.7.7"

# Functions
print_header() {
    echo -e "\n${BLUE}============================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}$1${NC}" | tee -a "$LOG_FILE"
    echo -e "${BLUE}============================================${NC}\n" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}" | tee -a "$LOG_FILE"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --yes|-y)
                SKIP_CONFIRMATIONS=true
                shift
                ;;
            --metallb-range)
                METALLB_IP_RANGE="$2"
                shift 2
                ;;
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --acme-email)
                ACME_EMAIL="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Unified infrastructure bootstrap script for homelab platform components.

OPTIONS:
    --dry-run              Show what would be installed without making changes
    --yes, -y              Skip confirmation prompts
    --metallb-range IP     Set MetalLB IP range (default: $METALLB_IP_RANGE)
    --domain DOMAIN        Set domain name (default: $DOMAIN)
    --acme-email EMAIL     Set ACME email for Let's Encrypt (default: $ACME_EMAIL)
    --help, -h             Show this help message

EXAMPLE:
    $0 --metallb-range "10.0.1.200-10.0.1.250" --domain "lab.example.com"
EOF
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    for tool in kubectl helm git curl; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
            print_error "$tool is not installed"
        else
            print_success "$tool is installed"
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install missing tools and try again."
        exit 1
    fi
    
    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot access Kubernetes cluster"
        echo "Please ensure kubectl is configured correctly"
        exit 1
    fi
    
    print_success "Kubernetes cluster is accessible"
    
    # Check nodes are ready
    local not_ready=$(kubectl get nodes --no-headers | grep -v "Ready" | wc -l)
    if [ "$not_ready" -gt 0 ]; then
        print_error "Some nodes are not ready"
        kubectl get nodes
        exit 1
    fi
    
    print_success "All nodes are ready"
}

# Add Helm repositories
setup_helm_repos() {
    print_header "Setting Up Helm Repositories"
    
    local repos=(
        "metallb|https://metallb.github.io/metallb"
        "traefik|https://helm.traefik.io/traefik"
        "jetstack|https://charts.jetstack.io"
        "k8s-at-home|https://k8s-at-home.com/charts"
        "rancher-stable|https://releases.rancher.com/server-charts/stable"
        "argo|https://argoproj.github.io/argo-helm"
    )
    
    for repo_info in "${repos[@]}"; do
        IFS='|' read -r name url <<< "$repo_info"
        if helm repo list | grep -q "^$name"; then
            print_info "Helm repo '$name' already exists"
        else
            print_info "Adding Helm repo '$name'"
            helm repo add "$name" "$url"
        fi
    done
    
    print_info "Updating Helm repositories..."
    helm repo update
    print_success "Helm repositories ready"
}

# Install storage class
install_storage_class() {
    print_header "Installing Storage Class"
    
    # Check if storage class exists
    if kubectl get storageclass &> /dev/null && [ "$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)" -gt 0 ]; then
        print_info "Storage class already exists:"
        kubectl get storageclass
        return 0
    fi
    
    print_info "Installing local-path-provisioner..."
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
    
    # Wait for deployment
    kubectl wait --for=condition=Available deployment/local-path-provisioner \
        -n local-path-storage --timeout=120s
    
    # Set as default
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    
    print_success "Storage class installed and set as default"
}

# Install MetalLB
install_metallb() {
    print_header "Installing MetalLB"
    
    # Create namespace
    kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Install MetalLB
    helm upgrade --install metallb metallb/metallb \
        --namespace metallb-system \
        --version "$METALLB_VERSION" \
        --wait \
        --timeout 5m
    
    # Wait for MetalLB to be ready
    kubectl wait --namespace metallb-system \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=metallb \
        --timeout=120s
    
    # Apply IP address pool
    cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: main-pool
  namespace: metallb-system
spec:
  addresses:
  - $METALLB_IP_RANGE
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: main-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - main-pool
EOF
    
    print_success "MetalLB installed with IP range: $METALLB_IP_RANGE"
}

# Install AdGuard Home
install_adguard() {
    print_header "Installing AdGuard Home"
    
    # Create namespace
    kubectl create namespace adguard --dry-run=client -o yaml | kubectl apply -f -
    
    # Create values file
    cat <<EOF > /tmp/adguard-values.yaml
image:
  repository: adguard/adguardhome
  tag: latest
  pullPolicy: IfNotPresent

service:
  main:
    type: LoadBalancer
    annotations:
      metallb.universe.tf/loadBalancerIPs: "${METALLB_IP_RANGE%%-*}"
    ports:
      http:
        port: 3000
      dns-tcp:
        enabled: true
        port: 53
        protocol: TCP
        targetPort: 53
      dns-udp:
        enabled: true
        port: 53
        protocol: UDP
        targetPort: 53

persistence:
  config:
    enabled: true
    size: 1Gi
    storageClass: local-path
  data:
    enabled: true
    size: 5Gi
    storageClass: local-path

resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 512Mi
    cpu: 500m

# Initial configuration
config: |
  bind_host: 0.0.0.0
  bind_port: 3000
  users:
    - name: admin
      password: \$2y\$10\$EFmCLZ2rPFXZnFmN3NkBt.fkh0JgYKRJAYBEJMRaBIobsT/w0Mq5i  # admin
  dns:
    bind_hosts:
      - 0.0.0.0
    port: 53
    upstream_dns:
      - 1.1.1.1
      - 8.8.8.8
    bootstrap_dns:
      - 1.1.1.1
      - 8.8.8.8
EOF
    
    # Install AdGuard
    helm upgrade --install adguard k8s-at-home/adguard-home \
        --namespace adguard \
        --version "$ADGUARD_VERSION" \
        --values /tmp/adguard-values.yaml \
        --wait \
        --timeout 5m
    
    # Get LoadBalancer IP
    local adguard_ip=""
    for i in {1..30}; do
        adguard_ip=$(kubectl get svc -n adguard adguard-adguard-home -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        if [ -n "$adguard_ip" ]; then
            break
        fi
        sleep 2
    done
    
    if [ -n "$adguard_ip" ]; then
        print_success "AdGuard installed and accessible at: http://$adguard_ip:3000"
        print_info "DNS server available at: $adguard_ip:53"
        print_info "Default login: admin/admin (change immediately!)"
    else
        print_warning "AdGuard installed but LoadBalancer IP not assigned yet"
    fi
    
    rm -f /tmp/adguard-values.yaml
}

# Install Traefik
install_traefik() {
    print_header "Installing Traefik"
    
    # Create namespace
    kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f -
    
    # Get first IP from MetalLB range for Traefik
    local traefik_ip="${METALLB_IP_RANGE%%-*}"
    # Increment IP by 1 (assuming it's available)
    local ip_parts=(${traefik_ip//./ })
    ((ip_parts[3]++))
    traefik_ip="${ip_parts[0]}.${ip_parts[1]}.${ip_parts[2]}.${ip_parts[3]}"
    
    # Create values file
    cat <<EOF > /tmp/traefik-values.yaml
deployment:
  replicas: 2

service:
  type: LoadBalancer
  annotations:
    metallb.universe.tf/loadBalancerIPs: "$traefik_ip"

ports:
  web:
    redirectTo:
      port: websecure
  websecure:
    tls:
      enabled: true
    middlewares:
      - traefik-compress@kubernetescrd

ingressRoute:
  dashboard:
    enabled: true
    matchRule: Host(\`traefik.$DOMAIN\`)
    entryPoints: ["websecure"]
    tls: {}

providers:
  kubernetesCRD:
    enabled: true
    allowCrossNamespace: true
  kubernetesIngress:
    enabled: true
    publishedService:
      enabled: true

persistence:
  enabled: true
  storageClass: local-path
  size: 1Gi

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi

logs:
  general:
    level: INFO
  access:
    enabled: true

metrics:
  prometheus:
    enabled: true
    service:
      enabled: true
    serviceMonitor:
      enabled: false  # Enable when Prometheus is installed
EOF
    
    # Install Traefik
    helm upgrade --install traefik traefik/traefik \
        --namespace traefik \
        --version "$TRAEFIK_VERSION" \
        --values /tmp/traefik-values.yaml \
        --wait \
        --timeout 5m
    
    print_success "Traefik installed with LoadBalancer IP: $traefik_ip"
    print_info "Dashboard will be available at: https://traefik.$DOMAIN"
    
    rm -f /tmp/traefik-values.yaml
}

# Install cert-manager
install_cert_manager() {
    print_header "Installing cert-manager"
    
    # Create namespace
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    
    # Install cert-manager
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version "$CERT_MANAGER_VERSION" \
        --set crds.enabled=true \
        --set prometheus.enabled=true \
        --wait \
        --timeout 5m
    
    # Wait for cert-manager to be ready
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=120s
    
    # Create ClusterIssuer for Let's Encrypt
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $ACME_EMAIL
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: $ACME_EMAIL
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: traefik
EOF
    
    print_success "cert-manager installed with Let's Encrypt issuers"
}

# Install Rancher
install_rancher() {
    print_header "Installing Rancher"
    
    # Create namespace
    kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Create values file
    cat <<EOF > /tmp/rancher-values.yaml
hostname: rancher.$DOMAIN
replicas: 1
bootstrapPassword: "admin"  # Change this!

ingress:
  enabled: true
  ingressClassName: traefik
  tls:
    source: letsEncrypt
  extraAnnotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod

letsEncrypt:
  email: $ACME_EMAIL
  ingress:
    class: traefik

resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

persistence:
  enabled: true
  storageClass: local-path
  size: 10Gi
EOF
    
    # Install Rancher
    helm upgrade --install rancher rancher-stable/rancher \
        --namespace cattle-system \
        --version "$RANCHER_VERSION" \
        --values /tmp/rancher-values.yaml \
        --wait \
        --timeout 10m
    
    print_success "Rancher installed"
    print_info "Rancher will be available at: https://rancher.$DOMAIN"
    print_warning "Default bootstrap password is 'admin' - CHANGE IT!"
    
    rm -f /tmp/rancher-values.yaml
}

# Install ArgoCD
install_argocd() {
    print_header "Installing ArgoCD"
    
    # Create namespace
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
    
    # Create values file
    cat <<EOF > /tmp/argocd-values.yaml
global:
  domain: argocd.$DOMAIN

server:
  ingress:
    enabled: true
    ingressClassName: traefik
    hostname: argocd.$DOMAIN
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls: true

  metrics:
    enabled: true
    serviceMonitor:
      enabled: false  # Enable when Prometheus is installed

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

controller:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false

  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1000m
      memory: 2Gi

repoServer:
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi

# Configure to watch only the applications namespace
configs:
  params:
    application.namespaces: "argocd,applications"
EOF
    
    # Install ArgoCD
    helm upgrade --install argocd argo/argo-cd \
        --namespace argocd \
        --version "$ARGOCD_VERSION" \
        --values /tmp/argocd-values.yaml \
        --wait \
        --timeout 10m
    
    # Get initial admin password
    local admin_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    print_success "ArgoCD installed"
    print_info "ArgoCD UI available at: https://argocd.$DOMAIN"
    print_info "Username: admin"
    print_info "Password: $admin_password"
    print_warning "Please change the admin password immediately!"
    
    rm -f /tmp/argocd-values.yaml
}

# Create summary
create_summary() {
    print_header "Installation Summary"
    
    echo -e "${GREEN}✓ Infrastructure Platform Installed Successfully!${NC}"
    echo ""
    echo "Components installed:"
    echo "  ✓ Storage Class (local-path)"
    echo "  ✓ MetalLB (LoadBalancer provider)"
    echo "  ✓ AdGuard Home (DNS server)"
    echo "  ✓ Traefik (Ingress controller)"
    echo "  ✓ cert-manager (SSL certificates)"
    echo "  ✓ Rancher (Kubernetes management)"
    echo "  ✓ ArgoCD (GitOps)"
    echo ""
    echo "Access URLs:"
    echo "  - AdGuard: http://$(kubectl get svc -n adguard adguard-adguard-home -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"
    echo "  - Traefik: https://traefik.$DOMAIN"
    echo "  - Rancher: https://rancher.$DOMAIN"
    echo "  - ArgoCD: https://argocd.$DOMAIN"
    echo ""
    echo "Next steps:"
    echo "1. Configure DNS to point *.$DOMAIN to your Traefik LoadBalancer IP"
    echo "2. Change all default passwords (AdGuard, Rancher, ArgoCD)"
    echo "3. Configure AdGuard as your DNS server"
    echo "4. Deploy applications using ArgoCD"
    echo ""
    echo "To deploy applications with ArgoCD:"
    echo "  kubectl apply -f gitops/applications/"
    echo ""
    print_info "Installation log saved to: $LOG_FILE"
}

# Main installation flow
main() {
    print_header "Homelab Infrastructure Platform Bootstrap"
    
    # Start logging
    echo "Bootstrap started at $(date)" > "$LOG_FILE"
    
    # Parse arguments
    parse_args "$@"
    
    # Show configuration
    echo "Configuration:"
    echo "  MetalLB IP Range: $METALLB_IP_RANGE"
    echo "  Domain: $DOMAIN"
    echo "  ACME Email: $ACME_EMAIL"
    echo "  Dry Run: $DRY_RUN"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    # Confirm installation
    if [ "$SKIP_CONFIRMATIONS" = false ]; then
        read -p "Do you want to proceed with the installation? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled"
            exit 0
        fi
    fi
    
    # Run installation steps
    check_prerequisites
    setup_helm_repos
    
    if [ "$DRY_RUN" = false ]; then
        install_storage_class
        install_metallb
        install_adguard
        install_traefik
        install_cert_manager
        install_rancher
        install_argocd
    else
        print_info "DRY RUN: Would install storage class"
        print_info "DRY RUN: Would install MetalLB"
        print_info "DRY RUN: Would install AdGuard"
        print_info "DRY RUN: Would install Traefik"
        print_info "DRY RUN: Would install cert-manager"
        print_info "DRY RUN: Would install Rancher"
        print_info "DRY RUN: Would install ArgoCD"
    fi
    
    # Show summary
    if [ "$DRY_RUN" = false ]; then
        create_summary
    fi
    
    print_success "Bootstrap completed successfully!"
}

# Run main function
main "$@"
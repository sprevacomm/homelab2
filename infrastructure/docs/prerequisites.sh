#!/bin/bash
# Prerequisites Setup Script for Homelab Infrastructure
# This script must be run BEFORE installing ArgoCD

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STORAGE_CLASS_NAME="local-path"
REQUIRED_TOOLS=("kubectl" "helm" "git")
REQUIRED_NAMESPACES=("argocd" "metallb-system" "traefik" "monitoring")

# Functions
print_header() {
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        print_success "$1 is installed"
        return 0
    else
        print_error "$1 is not installed"
        return 1
    fi
}

check_cluster_access() {
    print_header "Checking Cluster Access"
    
    if kubectl cluster-info &> /dev/null; then
        print_success "Kubernetes cluster is accessible"
        kubectl cluster-info
        echo ""
        
        # Check nodes
        print_info "Cluster nodes:"
        kubectl get nodes
        echo ""
        
        # Check if all nodes are ready
        NOT_READY=$(kubectl get nodes | grep -v "Ready" | grep -c "NotReady" || true)
        if [ "$NOT_READY" -eq 0 ]; then
            print_success "All nodes are ready"
        else
            print_error "Some nodes are not ready"
            exit 1
        fi
    else
        print_error "Cannot access Kubernetes cluster"
        echo "Please ensure kubectl is configured correctly"
        exit 1
    fi
}

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local all_good=true
    
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! check_command "$tool"; then
            all_good=false
        fi
    done
    
    if [ "$all_good" = false ]; then
        echo ""
        print_error "Some required tools are missing"
        echo "Please install missing tools and run this script again"
        exit 1
    fi
    
    echo ""
    print_success "All required tools are installed"
}

check_storage_class() {
    print_header "Checking Storage Class"
    
    # Check if any storage class exists
    if kubectl get storageclass &> /dev/null && [ "$(kubectl get storageclass --no-headers 2>/dev/null | wc -l)" -gt 0 ]; then
        print_info "Existing storage classes:"
        kubectl get storageclass
        echo ""
        
        # Check for default storage class
        DEFAULT_SC=$(kubectl get storageclass -o json | grep -c '"storageclass.kubernetes.io/is-default-class":"true"' || true)
        if [ "$DEFAULT_SC" -gt 0 ]; then
            print_success "Default storage class is configured"
            return 0
        else
            print_warning "No default storage class found"
            read -p "Do you want to set up a default storage class? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                setup_storage_class
            fi
        fi
    else
        print_warning "No storage class found"
        print_warning "This is REQUIRED for:"
        print_warning "- Prometheus metrics storage (20GB)"
        print_warning "- Grafana dashboards (5GB)"
        print_warning "- Alertmanager data (5GB)"
        print_warning "- Traefik certificates (1GB)"
        read -p "Do you want to install local-path-provisioner? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            setup_storage_class
        else
            print_error "Cannot proceed without storage class for monitoring stack"
            exit 1
        fi
    fi
}

setup_storage_class() {
    print_header "Setting Up Storage Class"
    
    print_info "Installing local-path-provisioner..."
    
    # Install local-path-provisioner
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
    
    # Wait for deployment
    print_info "Waiting for local-path-provisioner to be ready..."
    kubectl wait --for=condition=Available deployment/local-path-provisioner \
        -n local-path-storage --timeout=120s
    
    # Set as default
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    
    print_success "Storage class installed and set as default"
    
    # Test storage class
    test_storage_class
}

test_storage_class() {
    print_info "Testing storage class..."
    
    # Create test PVC
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
    
    # Wait for PVC to be bound
    local count=0
    while [ $count -lt 30 ]; do
        STATUS=$(kubectl get pvc test-pvc -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$STATUS" = "Bound" ]; then
            print_success "Storage class test successful"
            kubectl delete pvc test-pvc -n default
            return 0
        fi
        sleep 2
        count=$((count + 1))
    done
    
    print_error "Storage class test failed - PVC not bound after 60 seconds"
    kubectl describe pvc test-pvc -n default
    kubectl delete pvc test-pvc -n default
    return 1
}

create_namespaces() {
    print_header "Creating Namespaces"
    
    for ns in "${REQUIRED_NAMESPACES[@]}"; do
        if kubectl get namespace "$ns" &> /dev/null; then
            print_info "Namespace $ns already exists"
        else
            kubectl create namespace "$ns"
            print_success "Created namespace $ns"
        fi
    done
}

check_network_config() {
    print_header "Network Configuration Check"
    
    print_info "Current network configuration:"
    
    # Get node IPs
    echo -e "\n${BLUE}Node IPs:${NC}"
    kubectl get nodes -o wide | awk '{print $1, $6}' | column -t
    
    # Check for existing LoadBalancer services
    echo -e "\n${BLUE}Existing LoadBalancer services:${NC}"
    LB_COUNT=$(kubectl get svc --all-namespaces -o json | grep -c '"type":"LoadBalancer"' || true)
    if [ "$LB_COUNT" -gt 0 ]; then
        kubectl get svc --all-namespaces | grep LoadBalancer
        print_warning "Found existing LoadBalancer services"
        print_warning "Make sure MetalLB IP range doesn't conflict"
    else
        print_info "No existing LoadBalancer services found"
    fi
    
    echo -e "\n${YELLOW}Please ensure your MetalLB IP range:${NC}"
    echo "1. Is outside your DHCP range"
    echo "2. Is on the same subnet as your nodes"
    echo "3. Doesn't conflict with existing services"
    echo ""
    read -p "Press Enter to continue..."
}

check_dns_config() {
    print_header "DNS Configuration Reminder"
    
    echo -e "${YELLOW}After installation, you will need to:${NC}"
    echo "1. Get the LoadBalancer IP from MetalLB (usually the first IP in your range)"
    echo "2. Configure your DNS:"
    echo "   - Add wildcard record: *.yourdomain.com → LoadBalancer_IP"
    echo "   - OR add individual records for each service"
    echo "3. Update all YAML files to use your domain instead of 'susdomain.name'"
    echo ""
    print_info "Example: If MetalLB range is 192.168.1.200-250"
    print_info "         Then LoadBalancer IP will likely be 192.168.1.200"
    echo ""
    read -p "Press Enter to continue..."
}

update_configuration_files() {
    print_header "Configuration Files Update"
    
    echo "You need to update the following configuration files:"
    echo ""
    echo "1. ${YELLOW}metallb/manifests/base/ipaddresspool.yaml${NC}"
    echo "   - Update IP range to match your network"
    echo ""
    echo "2. ${YELLOW}traefik/values/values.yaml${NC}"
    echo "   - Update LoadBalancer IP annotation"
    echo "   - Update Let's Encrypt email"
    echo ""
    echo "3. ${YELLOW}All files with 'susdomain.name'${NC}"
    echo "   - Replace with your actual domain"
    echo ""
    
    read -p "Do you want to see the files that need updating? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "\n${BLUE}Files containing 'susdomain.name':${NC}"
        grep -r "susdomain.name" . --include="*.yaml" --include="*.yml" 2>/dev/null | cut -d: -f1 | sort | uniq
        
        echo -e "\n${BLUE}Files containing IP ranges:${NC}"
        grep -r "192.168.1" . --include="*.yaml" --include="*.yml" 2>/dev/null | grep -v ".git" | cut -d: -f1 | sort | uniq
    fi
    
    echo ""
    print_warning "Please update these files before proceeding with ArgoCD installation"
    read -p "Press Enter when ready to continue..."
}

verify_helm_repos() {
    print_header "Verifying Helm Repositories"
    
    # Add required Helm repos
    local repos=(
        "argo|https://argoproj.github.io/argo-helm"
        "metallb|https://metallb.github.io/metallb"
        "traefik|https://helm.traefik.io/traefik"
        "prometheus-community|https://prometheus-community.github.io/helm-charts"
    )
    
    for repo_info in "${repos[@]}"; do
        IFS='|' read -r name url <<< "$repo_info"
        
        if helm repo list | grep -q "^$name"; then
            print_info "Helm repo '$name' already exists"
        else
            print_info "Adding Helm repo '$name'"
            helm repo add "$name" "$url"
            print_success "Added Helm repo '$name'"
        fi
    done
    
    print_info "Updating Helm repositories..."
    helm repo update
    print_success "Helm repositories updated"
}

create_summary() {
    print_header "Pre-Installation Summary"
    
    echo -e "${GREEN}✓ Cluster Access:${NC} Verified"
    echo -e "${GREEN}✓ Required Tools:${NC} Installed"
    
    # Storage class status
    if kubectl get storageclass -o json 2>/dev/null | grep -q '"storageclass.kubernetes.io/is-default-class":"true"'; then
        echo -e "${GREEN}✓ Storage Class:${NC} Configured with default"
    else
        echo -e "${YELLOW}⚠ Storage Class:${NC} Not configured (Traefik persistence must be disabled)"
    fi
    
    echo -e "${GREEN}✓ Namespaces:${NC} Created"
    echo -e "${GREEN}✓ Helm Repos:${NC} Added"
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo "1. Update configuration files with your values"
    echo "2. Commit changes to your git repository"
    echo "3. Run: cd ../bootstrap && ./bootstrap.sh"
    echo "4. Apply app-of-apps: kubectl apply -f ../../gitops/bootstrap/infrastructure.yaml"
    echo "5. Access monitoring at https://grafana.yourdomain.com"
    
    echo -e "\n${YELLOW}Important Reminders:${NC}"
    echo "- Update MetalLB IP range in ipaddresspool.yaml"
    echo "- Update Traefik LoadBalancer IP in values.yaml"
    echo "- Update Monitoring master node IPs in values.yaml"
    echo "- Replace 'susdomain.name' with your domain"
    echo "- Configure DNS after LoadBalancer IP is assigned"
    
    echo -e "\n${GREEN}Storage Requirements:${NC}"
    echo "- Prometheus: 20GB for metrics (30 days retention)"
    echo "- Grafana: 5GB for dashboards"
    echo "- Alertmanager: 5GB for alerts"
    echo "- Total: ~30GB minimum recommended"
}

# Main execution
main() {
    print_header "Homelab Infrastructure Prerequisites Setup"
    
    echo "This script will prepare your cluster for ArgoCD installation"
    echo "and the complete homelab infrastructure stack."
    echo ""
    read -p "Do you want to continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting..."
        exit 0
    fi
    
    # Run all checks
    check_cluster_access
    check_prerequisites
    verify_helm_repos
    check_storage_class
    create_namespaces
    check_network_config
    check_dns_config
    update_configuration_files
    
    # Show summary
    create_summary
    
    echo ""
    print_success "Prerequisites setup complete!"
    print_info "You can now proceed with ArgoCD installation"
}

# Run main function
main "$@"
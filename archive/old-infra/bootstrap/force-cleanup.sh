#!/bin/bash
# Force Cleanup Script - Nuclear Option
# This script forcefully removes ALL stuck resources
# WARNING: This is extremely destructive!

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}============================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================${NC}\n"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Confirm destruction
print_warning "NUCLEAR CLEANUP - This will forcefully destroy ALL resources!"
echo -e "${RED}This is the most aggressive cleanup possible!${NC}"
read -p "Type 'DESTROY EVERYTHING' to confirm: " confirmation

if [[ "$confirmation" != "DESTROY EVERYTHING" ]]; then
    echo "Cancelled"
    exit 1
fi

print_header "Starting Nuclear Cleanup"

# 1. Delete ALL pods forcefully
print_info "Force deleting ALL pods in ALL namespaces..."
for ns in $(kubectl get ns -o name | cut -d/ -f2); do
    if [[ "$ns" == "kube-system" ]] || [[ "$ns" == "kube-public" ]] || [[ "$ns" == "kube-node-lease" ]]; then
        continue
    fi
    
    print_info "  Cleaning namespace: $ns"
    
    # Get all pods and force delete them
    kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '{print $1}' | while read -r pod; do
        print_info "    Force deleting pod: $pod"
        kubectl delete pod "$pod" -n "$ns" --force --grace-period=0 &>/dev/null || true
    done
    
    # Remove pod finalizers
    kubectl get pods -n "$ns" -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.finalizers != null) | .metadata.name' | \
        while read -r pod; do
            print_info "    Removing finalizers from pod: $pod"
            kubectl patch pod "$pod" -n "$ns" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' &>/dev/null || true
        done
done

# 2. Delete ALL deployments, statefulsets, daemonsets, jobs
print_info "Force deleting all workloads..."
for ns in $(kubectl get ns -o name | cut -d/ -f2); do
    if [[ "$ns" =~ ^kube- ]]; then
        continue
    fi
    
    for resource in deployment statefulset daemonset job cronjob replicaset; do
        kubectl delete "$resource" --all -n "$ns" --force --grace-period=0 &>/dev/null || true
    done
done

# 3. Delete services and endpoints
print_info "Deleting services and endpoints..."
for ns in $(kubectl get ns -o name | cut -d/ -f2); do
    if [[ "$ns" =~ ^kube- ]]; then
        continue
    fi
    
    kubectl delete service --all -n "$ns" --force --grace-period=0 &>/dev/null || true
    kubectl delete endpoints --all -n "$ns" --force --grace-period=0 &>/dev/null || true
done

# 4. Clean up PVCs and PVs
print_info "Cleaning up persistent volumes..."
kubectl delete pvc --all -A --force --grace-period=0 &>/dev/null || true
kubectl delete pv --all --force --grace-period=0 &>/dev/null || true

# 5. Force delete all custom resources
print_info "Force deleting all custom resources..."

# Delete all instances of CRDs
for crd in $(kubectl get crd -o name | cut -d/ -f2); do
    # Get the resource name from CRD
    resource=$(echo "$crd" | cut -d. -f1)
    
    print_info "  Deleting all $resource resources..."
    kubectl delete "$resource" --all -A --force --grace-period=0 &>/dev/null || true
    
    # Patch to remove finalizers
    kubectl get "$resource" -A -o json 2>/dev/null | \
        jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | \
        while read -r ns name; do
            kubectl patch "$resource" "$name" -n "$ns" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' &>/dev/null || true
        done
done

# 6. Delete all CRDs
print_info "Deleting all CRDs..."
kubectl get crd -o name | while read -r crd; do
    print_info "  Deleting CRD: $crd"
    # Remove finalizers first
    kubectl patch "$crd" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' &>/dev/null || true
    kubectl delete "$crd" --force --grace-period=0 &>/dev/null || true
done

# 7. Force namespace deletion
print_info "Force deleting namespaces..."
NAMESPACES=(
    "argocd"
    "cattle-system"
    "cert-manager"
    "traefik"
    "adguard"
    "metallb-system"
    "monitoring"
    "external-secrets-system"
    "external-secrets"
    "loki"
    "velero"
    "rke2-ingress-nginx"
)

for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        print_info "  Force deleting namespace: $ns"
        
        # Delete all resources in namespace first
        kubectl delete all --all -n "$ns" --force --grace-period=0 &>/dev/null || true
        
        # Remove finalizers via API
        kubectl get namespace "$ns" -o json | \
            jq '.spec = {"finalizers":[]} | .status = {"phase":"Terminating"}' | \
            kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - &>/dev/null || true
        
        # Force delete
        kubectl delete namespace "$ns" --force --grace-period=0 &>/dev/null || true
    fi
done

# 8. Clean up cluster roles and bindings
print_info "Cleaning up RBAC..."
kubectl delete clusterrolebinding --all --force --grace-period=0 2>/dev/null | grep -v "kubernetes-" || true
kubectl delete clusterrole --all --force --grace-period=0 2>/dev/null | grep -v "kubernetes-" || true

# 9. Delete webhooks
print_info "Deleting webhooks..."
kubectl delete validatingwebhookconfigurations --all --force --grace-period=0 &>/dev/null || true
kubectl delete mutatingwebhookconfigurations --all --force --grace-period=0 &>/dev/null || true

# 10. Final cleanup of any remaining namespaces
print_info "Final namespace cleanup..."
for ns in $(kubectl get namespaces -o json | jq -r '.items[] | select(.status.phase=="Terminating") | .metadata.name'); do
    print_warning "  Namespace $ns is stuck, applying final fix..."
    
    # Get namespace JSON and remove all finalizers
    kubectl get namespace "$ns" -o json | \
        jq '.metadata.finalizers = [] | .spec.finalizers = [] | .status = {"phase":"Terminating"}' > /tmp/ns-$ns.json
    
    # Replace via API
    kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f /tmp/ns-$ns.json &>/dev/null || true
    rm -f /tmp/ns-$ns.json
done

# 11. Wait and verify
print_info "Waiting for cleanup to complete..."
sleep 10

# Check what's left
print_header "Cleanup Status"

echo "Remaining namespaces:"
kubectl get namespaces | grep -v "kube-"

echo -e "\nRemaining pods:"
kubectl get pods -A | grep -v "kube-system"

echo -e "\nRemaining CRDs:"
kubectl get crds

print_success "Nuclear cleanup completed!"
print_info "You may need to run this script again if resources are still stuck"
print_info "After cleanup, run: ./bootstrap-infrastructure.sh"
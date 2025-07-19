#!/bin/bash
# Cluster Cleanup Script
# This script removes all homelab infrastructure components from the cluster
# WARNING: This is a destructive operation! Use with caution.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DRY_RUN=false
FORCE=false
KEEP_STORAGE_CLASS=false
TIMEOUT=300 # 5 minutes timeout for namespace deletion

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

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Removes all homelab infrastructure components from the Kubernetes cluster.

OPTIONS:
    --dry-run              Show what would be removed without making changes
    --force                Skip confirmation prompts
    --keep-storage-class   Keep the storage class (useful for data persistence)
    --help, -h             Show this help message

WARNING: This script will remove:
    - ArgoCD and all applications
    - Rancher
    - Cert-Manager
    - Traefik
    - AdGuard Home
    - MetalLB
    - All monitoring components
    - Storage class (unless --keep-storage-class is used)

EXAMPLE:
    $0 --dry-run           # See what would be removed
    $0 --force             # Remove everything without confirmation
    $0 --keep-storage-class # Keep storage class for next deployment
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --keep-storage-class)
                KEEP_STORAGE_CLASS=true
                shift
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

confirm_deletion() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    print_warning "This will PERMANENTLY DELETE all homelab infrastructure!"
    print_warning "Including:"
    echo "  - All applications managed by ArgoCD"
    echo "  - All platform components (ArgoCD, Rancher, Traefik, etc.)"
    echo "  - All persistent data (unless backed up externally)"
    echo ""
    echo -e "${RED}This action cannot be undone!${NC}"
    echo ""
    read -p "Type 'DELETE' to confirm: " confirmation
    
    if [[ "$confirmation" != "DELETE" ]]; then
        print_error "Deletion cancelled"
        exit 1
    fi
    
    echo ""
    read -p "Are you REALLY sure? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Deletion cancelled"
        exit 1
    fi
}

force_delete_namespace() {
    local namespace=$1
    
    if ! kubectl get namespace "$namespace" &>/dev/null; then
        return 0
    fi
    
    print_info "Force deleting namespace: $namespace"
    
    # First, delete all resources in the namespace
    print_info "  Deleting all resources in $namespace..."
    
    # Get all resource types and delete them
    kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | while read -r resource; do
        # Skip events and some system resources
        if [[ "$resource" =~ (events|nodes) ]]; then
            continue
        fi
        
        # Delete all resources of this type in the namespace
        kubectl delete "$resource" --all -n "$namespace" --force --grace-period=0 &>/dev/null || true
    done
    
    # Remove finalizers from all resources in the namespace
    print_info "  Removing finalizers from resources in $namespace..."
    kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | while read -r resource; do
        kubectl get "$resource" -n "$namespace" -o json 2>/dev/null | \
            jq -r '.items[]? | .metadata.name' | \
            while read -r name; do
                if [ -n "$name" ]; then
                    kubectl patch "$resource" "$name" -n "$namespace" --type='merge' -p '{"metadata":{"finalizers":[]}}' &>/dev/null || true
                fi
            done
    done
    
    # Remove finalizers from namespace itself
    print_info "  Removing namespace finalizers..."
    kubectl get namespace "$namespace" -o json | \
        jq '.spec.finalizers = [] | .metadata.finalizers = []' | \
        kubectl replace --raw "/api/v1/namespaces/$namespace/finalize" -f - &>/dev/null || true
    
    # Force delete the namespace
    kubectl delete namespace "$namespace" --force --grace-period=0 &>/dev/null || true
}

wait_for_namespace_deletion() {
    local namespace=$1
    local timeout=$2
    local elapsed=0
    
    while kubectl get namespace "$namespace" &>/dev/null; do
        if [ $elapsed -ge $timeout ]; then
            print_warning "Timeout waiting for namespace $namespace to delete, forcing..."
            force_delete_namespace "$namespace"
            return
        fi
        
        echo -n "."
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo ""
}

delete_argocd_applications() {
    print_header "Removing ArgoCD Applications"
    
    if kubectl get namespace argocd &>/dev/null; then
        # Delete all applications
        if [ "$DRY_RUN" = true ]; then
            print_info "[DRY RUN] Would delete all ArgoCD applications"
            kubectl get applications -n argocd 2>/dev/null || true
        else
            print_info "Deleting all ArgoCD applications..."
            kubectl delete applications --all -n argocd --force --grace-period=0 &>/dev/null || true
            sleep 10 # Give time for applications to start terminating
        fi
    else
        print_info "ArgoCD namespace not found, skipping"
    fi
}

delete_helm_releases() {
    print_header "Removing Helm Releases"
    
    # Get all helm releases across all namespaces
    if command -v helm &>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
            print_info "[DRY RUN] Would delete the following Helm releases:"
            helm list --all-namespaces
        else
            for ns in $(helm list --all-namespaces -o json | jq -r '.[].namespace' | sort | uniq); do
                print_info "Deleting Helm releases in namespace: $ns"
                helm list -n "$ns" -o json | jq -r '.[].name' | while read -r release; do
                    print_info "  Uninstalling: $release"
                    # Use --no-hooks and --cascade=orphan to force deletion
                    helm uninstall "$release" -n "$ns" --no-hooks --wait=false 2>/dev/null || true
                done
            done
        fi
    else
        print_warning "Helm not found, skipping Helm release cleanup"
    fi
}

delete_crds() {
    print_header "Removing Custom Resource Definitions"
    
    # First delete all custom resources before deleting CRDs
    print_info "Deleting custom resources..."
    
    # ArgoCD resources
    for res in applications applicationsets appprojects; do
        kubectl delete "$res" --all -A --force --grace-period=0 &>/dev/null || true
    done
    
    # Cert-manager resources
    for res in certificates certificaterequests issuers clusterissuers challenges orders; do
        kubectl delete "$res" --all -A --force --grace-period=0 &>/dev/null || true
    done
    
    # Traefik resources
    for res in ingressroutes ingressroutetcps ingressrouteudps middlewares middlewaretcps serverstransports tlsoptions tlsstores traefikservices; do
        kubectl delete "$res" --all -A --force --grace-period=0 &>/dev/null || true
    done
    
    # MetalLB resources
    for res in ipaddresspools l2advertisements bgppeers bgpadvertisements communities bfdprofiles; do
        kubectl delete "$res" --all -A --force --grace-period=0 &>/dev/null || true
    done
    
    # External Secrets resources
    for res in externalsecrets secretstores clustersecretstores; do
        kubectl delete "$res" --all -A --force --grace-period=0 &>/dev/null || true
    done
    
    print_info "Removing CRD finalizers and deleting CRDs..."
    
    local crds=(
        "applications.argoproj.io"
        "applicationsets.argoproj.io"
        "appprojects.argoproj.io"
        "certificates.cert-manager.io"
        "certificaterequests.cert-manager.io"
        "issuers.cert-manager.io"
        "clusterissuers.cert-manager.io"
        "challenges.acme.cert-manager.io"
        "orders.acme.cert-manager.io"
        "ingressroutes.traefik.containo.us"
        "ingressroutetcps.traefik.containo.us"
        "ingressrouteudps.traefik.containo.us"
        "middlewares.traefik.containo.us"
        "middlewaretcps.traefik.containo.us"
        "serverstransports.traefik.containo.us"
        "tlsoptions.traefik.containo.us"
        "tlsstores.traefik.containo.us"
        "traefikservices.traefik.containo.us"
        "ipaddresspools.metallb.io"
        "l2advertisements.metallb.io"
        "bgppeers.metallb.io"
        "bgpadvertisements.metallb.io"
        "communities.metallb.io"
        "bfdprofiles.metallb.io"
        "externalsecrets.external-secrets.io"
        "secretstores.external-secrets.io"
        "clustersecretstores.external-secrets.io"
    )
    
    for crd in "${crds[@]}"; do
        if kubectl get crd "$crd" &>/dev/null; then
            if [ "$DRY_RUN" = true ]; then
                print_info "[DRY RUN] Would delete CRD: $crd"
            else
                print_info "Deleting CRD: $crd"
                # Remove finalizers first
                kubectl patch crd "$crd" --type='merge' -p '{"metadata":{"finalizers":[]}}' &>/dev/null || true
                # Force delete
                kubectl delete crd "$crd" --force --grace-period=0 &>/dev/null || true
            fi
        fi
    done
}

delete_namespaces() {
    print_header "Removing Namespaces"
    
    local namespaces=(
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
    )
    
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            if [ "$DRY_RUN" = true ]; then
                print_info "[DRY RUN] Would delete namespace: $ns"
            else
                print_info "Deleting namespace: $ns"
                kubectl delete namespace "$ns" --grace-period=30 &>/dev/null || true
            fi
        fi
    done
    
    if [ "$DRY_RUN" = false ]; then
        # Wait for namespaces to be deleted
        print_info "Waiting for namespaces to be deleted..."
        for ns in "${namespaces[@]}"; do
            wait_for_namespace_deletion "$ns" "$TIMEOUT"
        done
    fi
}

delete_cluster_resources() {
    print_header "Removing Cluster-wide Resources"
    
    # Delete cluster roles and bindings
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would delete cluster roles and bindings"
    else
        print_info "Deleting cluster roles and bindings..."
        kubectl delete clusterrolebindings -l app.kubernetes.io/part-of=argocd &>/dev/null || true
        kubectl delete clusterroles -l app.kubernetes.io/part-of=argocd &>/dev/null || true
        kubectl delete clusterrolebindings -l app.kubernetes.io/name=metallb &>/dev/null || true
        kubectl delete clusterroles -l app.kubernetes.io/name=metallb &>/dev/null || true
        kubectl delete clusterrolebindings -l app.kubernetes.io/name=traefik &>/dev/null || true
        kubectl delete clusterroles -l app.kubernetes.io/name=traefik &>/dev/null || true
        kubectl delete clusterrolebindings -l app.kubernetes.io/name=cert-manager &>/dev/null || true
        kubectl delete clusterroles -l app.kubernetes.io/name=cert-manager &>/dev/null || true
    fi
    
    # Delete validating/mutating webhooks
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would delete webhooks"
    else
        print_info "Deleting webhooks..."
        kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/name=cert-manager &>/dev/null || true
        kubectl delete mutatingwebhookconfigurations -l app.kubernetes.io/name=cert-manager &>/dev/null || true
        kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/name=metallb &>/dev/null || true
    fi
}

delete_storage_class() {
    if [ "$KEEP_STORAGE_CLASS" = true ]; then
        print_info "Keeping storage class as requested"
        return
    fi
    
    print_header "Removing Storage Class"
    
    if kubectl get namespace local-path-storage &>/dev/null; then
        if [ "$DRY_RUN" = true ]; then
            print_info "[DRY RUN] Would delete local-path-storage"
        else
            print_info "Deleting local-path-storage..."
            kubectl delete namespace local-path-storage --grace-period=30 &>/dev/null || true
            kubectl delete storageclass local-path &>/dev/null || true
            wait_for_namespace_deletion "local-path-storage" "$TIMEOUT"
        fi
    fi
}

cleanup_finalizers() {
    print_header "Cleaning up stuck resources"
    
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would clean up resources with finalizers"
        return
    fi
    
    # First, clean up ArgoCD resources specifically
    print_info "Removing ArgoCD finalizers..."
    for resource in applications applicationsets appprojects; do
        kubectl get "$resource" -A -o json 2>/dev/null | \
            jq -r '.items[] | "\(.metadata.namespace)/\(.kind)/\(.metadata.name)"' | \
            while IFS='/' read -r ns kind name; do
                print_info "  Removing finalizers from $kind/$name in namespace $ns"
                kubectl patch "$resource" "$name" -n "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' &>/dev/null || true
                kubectl delete "$resource" "$name" -n "$ns" --force --grace-period=0 &>/dev/null || true
            done
    done
    
    # Remove finalizers from all namespaces that might be stuck
    print_info "Removing namespace finalizers..."
    for ns in argocd cattle-system cert-manager traefik adguard metallb-system monitoring external-secrets-system external-secrets loki velero; do
        if kubectl get namespace "$ns" &>/dev/null; then
            kubectl get namespace "$ns" -o json | \
                jq '.spec.finalizers = [] | .status.phase = "Terminating"' | \
                kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - &>/dev/null || true
        fi
    done
    
    # Find and clean up all resources with finalizers in target namespaces
    print_info "Removing resource finalizers..."
    for ns in $(kubectl get namespaces -o name | cut -d/ -f2); do
        # Skip kube-system namespaces
        if [[ "$ns" =~ ^kube- ]] || [[ "$ns" == "default" ]]; then
            continue
        fi
        
        # More aggressive finalizer removal
        kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | while read -r resource; do
            # Skip if resource doesn't exist
            kubectl get "$resource" -n "$ns" &>/dev/null || continue
            
            kubectl get "$resource" -n "$ns" -o json 2>/dev/null | \
                jq -r '.items[]? | select(.metadata.finalizers != null) | .metadata.name' | \
                while read -r name; do
                    if [ -n "$name" ]; then
                        print_info "  Removing finalizers from $resource/$name in $ns"
                        kubectl patch "$resource" "$name" -n "$ns" --type='merge' -p '{"metadata":{"finalizers":[]}}' &>/dev/null || true
                    fi
                done
        done
    done
    
    # Clean up cluster-scoped resources with finalizers
    print_info "Removing cluster-scoped resource finalizers..."
    kubectl api-resources --verbs=list --namespaced=false -o name 2>/dev/null | while read -r resource; do
        # Skip certain resources
        if [[ "$resource" =~ (nodes|namespaces|persistentvolumes) ]]; then
            continue
        fi
        
        kubectl get "$resource" -o json 2>/dev/null | \
            jq -r '.items[]? | select(.metadata.finalizers != null) | select(.metadata.name | test("(argocd|metallb|traefik|cert-manager|rancher|adguard)")) | .metadata.name' | \
            while read -r name; do
                if [ -n "$name" ]; then
                    print_info "  Removing finalizers from $resource/$name"
                    kubectl patch "$resource" "$name" --type='merge' -p '{"metadata":{"finalizers":[]}}' &>/dev/null || true
                fi
            done
    done
}

verify_cleanup() {
    print_header "Verifying Cleanup"
    
    local issues=0
    
    # Check for remaining namespaces
    for ns in argocd cattle-system cert-manager traefik adguard metallb-system monitoring; do
        if kubectl get namespace "$ns" &>/dev/null; then
            print_error "Namespace still exists: $ns"
            ((issues++))
        fi
    done
    
    # Check for remaining CRDs
    if kubectl get crds | grep -E "(argoproj|cert-manager|traefik|metallb)" &>/dev/null; then
        print_error "Some CRDs still exist"
        kubectl get crds | grep -E "(argoproj|cert-manager|traefik|metallb)" || true
        ((issues++))
    fi
    
    # Check for helm releases
    if command -v helm &>/dev/null; then
        if [ "$(helm list --all-namespaces 2>/dev/null | wc -l)" -gt 1 ]; then
            print_error "Some Helm releases still exist"
            helm list --all-namespaces
            ((issues++))
        fi
    fi
    
    if [ $issues -eq 0 ]; then
        print_success "Cleanup completed successfully!"
    else
        print_warning "Cleanup completed with $issues issues"
        print_info "You may need to manually clean up remaining resources"
    fi
}

# Main execution
main() {
    print_header "Homelab Infrastructure Cleanup"
    
    # Parse arguments
    parse_args "$@"
    
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi
    
    # Check kubectl access
    if ! kubectl cluster-info &>/dev/null; then
        print_error "Cannot access Kubernetes cluster"
        echo "Please ensure kubectl is configured correctly"
        exit 1
    fi
    
    # Confirm deletion
    if [ "$DRY_RUN" = false ]; then
        confirm_deletion
    fi
    
    # Start cleanup process
    print_info "Starting cleanup process..."
    
    # Order matters! Delete applications first, then infrastructure
    delete_argocd_applications
    
    # Clean up finalizers early to prevent stuck resources
    cleanup_finalizers
    
    # Delete helm releases without waiting
    delete_helm_releases
    
    # Delete CRDs before namespaces to avoid stuck resources
    delete_crds
    
    # Delete cluster-wide resources
    delete_cluster_resources
    
    # Clean up finalizers again after CRD deletion
    cleanup_finalizers
    
    # Now delete namespaces
    delete_namespaces
    
    # Final cleanup pass
    cleanup_finalizers
    
    # Delete storage class last
    delete_storage_class
    
    # Verify cleanup
    if [ "$DRY_RUN" = false ]; then
        verify_cleanup
        
        echo ""
        print_info "Cluster is ready for fresh installation"
        print_info "Run './bootstrap-infrastructure.sh' to start over"
    else
        echo ""
        print_info "Dry run completed. Run without --dry-run to actually remove resources"
    fi
}

# Run main function
main "$@"
#!/bin/bash
# Cleanup Helm Hook Pods
# Specifically targets stuck helm-delete pods

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}Cleaning up stuck Helm hook pods...${NC}"

# Find all helm-delete pods
echo -e "${BLUE}Finding helm-delete pods...${NC}"
kubectl get pods -A | grep -E "(helm-delete|hook-)" | while read line; do
    namespace=$(echo $line | awk '{print $1}')
    pod=$(echo $line | awk '{print $2}')
    
    echo -e "${BLUE}Deleting $pod in namespace $namespace${NC}"
    
    # First try normal delete
    kubectl delete pod "$pod" -n "$namespace" --force --grace-period=0 &>/dev/null || true
    
    # Remove finalizers
    kubectl patch pod "$pod" -n "$namespace" --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' &>/dev/null || true
    
    # If still exists, try raw API
    if kubectl get pod "$pod" -n "$namespace" &>/dev/null 2>&1; then
        echo -e "${YELLOW}Pod $pod still exists, using raw API...${NC}"
        kubectl get pod "$pod" -n "$namespace" -o json | jq '.metadata.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$namespace/pods/$pod" -f - &>/dev/null || true
    fi
done

# Also clean up any completed/failed jobs that might be holding these pods
echo -e "${BLUE}Cleaning up Helm jobs...${NC}"
kubectl get jobs -A | grep -E "(helm-|hook-)" | while read line; do
    namespace=$(echo $line | awk '{print $1}')
    job=$(echo $line | awk '{print $2}')
    
    echo -e "${BLUE}Deleting job $job in namespace $namespace${NC}"
    kubectl delete job "$job" -n "$namespace" --force --grace-period=0 &>/dev/null || true
done

# Clean up the parent deployments/replicasets if any
echo -e "${BLUE}Cleaning up Helm deployments...${NC}"
for resource in deployment replicaset daemonset; do
    kubectl get "$resource" -A | grep -E "(helm-|hook-)" | while read line; do
        namespace=$(echo $line | awk '{print $1}')
        name=$(echo $line | awk '{print $2}')
        
        echo -e "${BLUE}Deleting $resource $name in namespace $namespace${NC}"
        kubectl delete "$resource" "$name" -n "$namespace" --force --grace-period=0 &>/dev/null || true
    done
done

echo -e "${GREEN}Helm hook cleanup completed!${NC}"

# Show remaining pods
echo -e "${BLUE}Remaining pods with helm in name:${NC}"
kubectl get pods -A | grep -E "(helm-|hook-)" || echo "None found!"
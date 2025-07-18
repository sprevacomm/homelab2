#!/bin/bash
# Script to verify RKE2 cluster health after adding nodes

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== RKE2 Cluster Verification ===${NC}"
echo ""

# Check if kubectl is configured
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}Error: kubectl not configured or cluster not accessible${NC}"
    echo "Please ensure your kubeconfig is set up correctly"
    exit 1
fi

# 1. Check nodes
echo -e "${YELLOW}1. Cluster Nodes:${NC}"
kubectl get nodes -o wide
echo ""

# Count nodes
TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)
READY_NODES=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
NOT_READY_NODES=$(kubectl get nodes --no-headers | grep " NotReady " | wc -l)

echo -e "Total nodes: ${BLUE}$TOTAL_NODES${NC}"
echo -e "Ready nodes: ${GREEN}$READY_NODES${NC}"
if [ $NOT_READY_NODES -gt 0 ]; then
    echo -e "Not ready nodes: ${RED}$NOT_READY_NODES${NC}"
fi
echo ""

# 2. Check system pods
echo -e "${YELLOW}2. System Pods Status:${NC}"
kubectl get pods -n kube-system -o wide | grep -E "(rke2|etcd|kube-proxy|kube-controller|kube-scheduler|cloud-controller|coredns)"
echo ""

# 3. Check node resources
echo -e "${YELLOW}3. Node Resources:${NC}"
kubectl top nodes 2>/dev/null || echo "Note: Metrics server not installed"
echo ""

# 4. Check storage
echo -e "${YELLOW}4. Storage Classes:${NC}"
kubectl get storageclass
echo ""

# 5. Check for any issues
echo -e "${YELLOW}5. Recent Events (Warnings/Errors):${NC}"
kubectl get events --all-namespaces --field-selector type=Warning --sort-by='.lastTimestamp' | tail -10
echo ""

# 6. Node labels and taints
echo -e "${YELLOW}6. Node Labels and Taints:${NC}"
for node in $(kubectl get nodes -o name); do
    echo -e "${BLUE}$node:${NC}"
    kubectl describe $node | grep -A5 "Labels:" | head -6
    kubectl describe $node | grep -A5 "Taints:" | head -6
    echo ""
done

# 7. Test pod scheduling on new nodes
echo -e "${YELLOW}7. Testing Pod Scheduling:${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-test
  namespace: default
spec:
  selector:
    matchLabels:
      app: node-test
  template:
    metadata:
      labels:
        app: node-test
    spec:
      containers:
      - name: busybox
        image: busybox:latest
        command: ["sleep", "3600"]
        resources:
          requests:
            memory: "10Mi"
            cpu: "10m"
          limits:
            memory: "50Mi"
            cpu: "50m"
EOF

sleep 5
echo "Checking pod distribution:"
kubectl get pods -o wide -l app=node-test
echo ""

# Cleanup test
kubectl delete daemonset node-test

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [ $READY_NODES -eq $TOTAL_NODES ]; then
    echo -e "${GREEN}✓ All $TOTAL_NODES nodes are ready!${NC}"
else
    echo -e "${RED}✗ Only $READY_NODES out of $TOTAL_NODES nodes are ready${NC}"
fi

# Expected state after adding 4 nodes
EXPECTED_NODES=7  # 1 master + 6 workers
if [ $TOTAL_NODES -eq $EXPECTED_NODES ]; then
    echo -e "${GREEN}✓ Expected node count matches ($EXPECTED_NODES nodes)${NC}"
else
    echo -e "${YELLOW}⚠ Node count is $TOTAL_NODES, expected $EXPECTED_NODES${NC}"
fi
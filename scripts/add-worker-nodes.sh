#!/bin/bash
# Script to add RKE2 worker nodes to the cluster
# Run this on the Proxmox host

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default Configuration
MASTER_IP="192.168.0.201"
TEMPLATE_VM=200  # Master VM to clone from
NUM_NEW_WORKERS=4
DRY_RUN=false

# Function to display help
show_help() {
    cat << EOF
${BLUE}RKE2 Worker Node Addition Script${NC}

${YELLOW}Usage:${NC}
    $0 [OPTIONS]

${YELLOW}Options:${NC}
    -h, --help              Show this help message
    -n, --nodes NUMBER      Number of worker nodes to add (default: 4)
    -t, --template VMID     Template VM ID to clone from (default: 200)
    -m, --master IP         Master node IP address (default: 192.168.0.201)
    -d, --dry-run          Show what would be done without making changes
    -l, --list             List existing VMs and exit

${YELLOW}Examples:${NC}
    # Add 4 worker nodes (default)
    $0

    # Add 2 worker nodes
    $0 -n 2

    # Add 6 worker nodes using different template
    $0 -n 6 -t 200

    # Dry run to see what would happen
    $0 -n 3 --dry-run

    # List existing VMs
    $0 --list

${YELLOW}Current Configuration:${NC}
    Master IP: $MASTER_IP
    Template VM: $TEMPLATE_VM
    Number of workers to add: $NUM_NEW_WORKERS

EOF
}

# Function to list VMs
list_vms() {
    echo -e "${BLUE}=== Current VMs ===${NC}"
    qm list | grep -E "(rke2|VMID)" || true
    echo ""
    echo -e "${BLUE}=== Current Cluster Nodes ===${NC}"
    ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide' 2>/dev/null || echo "Could not connect to master"
}

# Function to find next available VM ID
find_next_worker_id() {
    local highest_worker=$(qm list | grep "rke2-worker" | awk '{print $1}' | sort -n | tail -1)
    if [ -z "$highest_worker" ]; then
        echo "203"  # Start with worker-03 if no workers exist
    else
        echo $((highest_worker + 1))
    fi
}

# Function to find next worker number
find_next_worker_num() {
    local highest_num=$(qm list | grep -oP 'rke2-worker-\K\d+' | sort -n | tail -1)
    if [ -z "$highest_num" ]; then
        echo "3"  # Start with worker-03
    else
        echo $((highest_num + 1))
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -n|--nodes)
            NUM_NEW_WORKERS="$2"
            shift 2
            ;;
        -t|--template)
            TEMPLATE_VM="$2"
            shift 2
            ;;
        -m|--master)
            MASTER_IP="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -l|--list)
            list_vms
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Main script starts here
echo -e "${GREEN}=== RKE2 Worker Node Addition Script ===${NC}"
echo -e "Adding ${BLUE}$NUM_NEW_WORKERS${NC} worker nodes"
echo -e "Using template VM: ${BLUE}$TEMPLATE_VM${NC}"
echo -e "Master node IP: ${BLUE}$MASTER_IP${NC}"

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
fi

# Check if template VM exists
if ! qm status $TEMPLATE_VM &>/dev/null; then
    echo -e "${RED}Error: Template VM $TEMPLATE_VM not found${NC}"
    echo "Available VMs:"
    qm list
    exit 1
fi

# Find starting points
BASE_WORKER_ID=$(find_next_worker_id)
BASE_WORKER_NUM=$(find_next_worker_num)

echo -e "\nStarting from:"
echo -e "  VM ID: ${BLUE}$BASE_WORKER_ID${NC}"
echo -e "  Worker number: ${BLUE}$BASE_WORKER_NUM${NC}"
echo ""

# Confirm before proceeding
if [ "$DRY_RUN" = false ]; then
    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
fi

echo -e "${YELLOW}Creating new worker VMs...${NC}"

# Create worker nodes
for i in $(seq 0 $((NUM_NEW_WORKERS-1))); do
    WORKER_ID=$((BASE_WORKER_ID + i))
    WORKER_NUM=$((BASE_WORKER_NUM + i))
    WORKER_NUM_PADDED=$(printf "%02d" $WORKER_NUM)
    WORKER_IP="192.168.0.$((201 + WORKER_NUM))"
    
    echo -e "${GREEN}Creating rke2-worker-${WORKER_NUM_PADDED} (VM $WORKER_ID) with IP $WORKER_IP${NC}"
    
    if [ "$DRY_RUN" = false ]; then
        # Clone the template VM
        qm clone $TEMPLATE_VM $WORKER_ID --name rke2-worker-${WORKER_NUM_PADDED} --full
        
        # Configure network and cloud-init
        qm set $WORKER_ID \
            --ipconfig0 ip=${WORKER_IP}/24,gw=192.168.0.1 \
            --sshkeys /root/.ssh/id_rsa.pub
        
        # Start the VM
        qm start $WORKER_ID
        
        echo -e "${GREEN}✓ Created and started VM $WORKER_ID${NC}"
    else
        echo -e "${YELLOW}[DRY RUN] Would create VM $WORKER_ID${NC}"
    fi
done

if [ "$DRY_RUN" = true ]; then
    echo -e "\n${YELLOW}DRY RUN complete. No changes were made.${NC}"
    exit 0
fi

echo -e "${YELLOW}Waiting for VMs to boot (60 seconds)...${NC}"
sleep 60

# Clear known hosts for new IPs
echo -e "${YELLOW}Clearing SSH known hosts...${NC}"
for i in $(seq 0 $((NUM_NEW_WORKERS-1))); do
    WORKER_NUM=$((BASE_WORKER_NUM + i))
    WORKER_IP="192.168.0.$((201 + WORKER_NUM))"
    ssh-keygen -f '/root/.ssh/known_hosts' -R "$WORKER_IP" 2>/dev/null || true
done

# Get the node token from master
echo -e "${YELLOW}Getting node token from master...${NC}"
NODE_TOKEN=$(ssh -o StrictHostKeyChecking=no ubuntu@$MASTER_IP 'sudo cat /var/lib/rancher/rke2/server/node-token')

if [ -z "$NODE_TOKEN" ]; then
    echo -e "${RED}Error: Could not retrieve node token from master${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved node token${NC}"

# Install RKE2 on new workers
echo -e "${YELLOW}Installing RKE2 on new worker nodes...${NC}"

for i in $(seq 0 $((NUM_NEW_WORKERS-1))); do
    WORKER_NUM=$((BASE_WORKER_NUM + i))
    WORKER_NUM_PADDED=$(printf "%02d" $WORKER_NUM)
    WORKER_IP="192.168.0.$((201 + WORKER_NUM))"
    
    echo -e "${GREEN}Installing RKE2 on worker-${WORKER_NUM_PADDED} ($WORKER_IP)${NC}"
    
    # Install RKE2 agent
    ssh -o StrictHostKeyChecking=no ubuntu@$WORKER_IP 'curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sudo sh -'
    
    # Configure RKE2 agent
    ssh ubuntu@$WORKER_IP "sudo mkdir -p /etc/rancher/rke2 && \
        echo 'server: https://$MASTER_IP:9345' | sudo tee /etc/rancher/rke2/config.yaml && \
        echo 'token: $NODE_TOKEN' | sudo tee -a /etc/rancher/rke2/config.yaml"
    
    # Enable and start RKE2 agent
    ssh ubuntu@$WORKER_IP 'sudo systemctl enable rke2-agent.service && sudo systemctl start rke2-agent.service'
    
    echo -e "${GREEN}✓ RKE2 agent installed and started on worker-${WORKER_NUM_PADDED}${NC}"
done

echo -e "${YELLOW}Waiting for nodes to join cluster (60 seconds)...${NC}"
sleep 60

# Verify nodes joined the cluster
echo -e "${YELLOW}Verifying cluster nodes...${NC}"
ssh ubuntu@$MASTER_IP 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide'

echo -e "${GREEN}=== Worker Node Addition Complete ===${NC}"
echo ""
echo "New worker nodes created:"
for i in $(seq 0 $((NUM_NEW_WORKERS-1))); do
    WORKER_ID=$((BASE_WORKER_ID + i))
    WORKER_NUM=$((BASE_WORKER_NUM + i))
    WORKER_NUM_PADDED=$(printf "%02d" $WORKER_NUM)
    WORKER_IP="192.168.0.$((201 + WORKER_NUM))"
    echo "  - VM $WORKER_ID: rke2-worker-${WORKER_NUM_PADDED} (IP: $WORKER_IP)"
done

echo ""
echo "To check node status from your workstation:"
echo "  kubectl get nodes -o wide"
echo ""
echo "To SSH to a worker node:"
for i in $(seq 0 $((NUM_NEW_WORKERS-1))); do
    WORKER_NUM=$((BASE_WORKER_NUM + i))
    WORKER_NUM_PADDED=$(printf "%02d" $WORKER_NUM)
    WORKER_IP="192.168.0.$((201 + WORKER_NUM))"
    echo "  ssh ubuntu@$WORKER_IP  # (worker-${WORKER_NUM_PADDED})"
done
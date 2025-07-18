# Homelab Scripts Documentation

This document describes all the scripts available in this repository.

## Table of Contents

- [Prerequisites Scripts](#prerequisites-scripts)
- [Installation Scripts](#installation-scripts)
- [Worker Management Scripts](#worker-management-scripts)
- [Verification Scripts](#verification-scripts)
- [SSH Setup Scripts](#ssh-setup-scripts)

## Prerequisites Scripts

### prerequisites.sh
**Location:** `infrastructure/docs/prerequisites.sh`  
**Purpose:** Prepares the cluster for ArgoCD and infrastructure installation

**Features:**
- Checks cluster access and node readiness
- Verifies required tools (kubectl, helm, git)
- Installs storage class if missing
- Creates required namespaces
- Configures Helm repositories
- Validates network configuration

**Usage:**
```bash
cd infrastructure/docs
./prerequisites.sh
```

## Installation Scripts

### bootstrap.sh
**Location:** `infrastructure/bootstrap/bootstrap.sh`  
**Purpose:** Installs ArgoCD on the cluster

**Features:**
- Checks prerequisites
- Adds ArgoCD Helm repository
- Installs ArgoCD with custom values
- Waits for ArgoCD to be ready
- Provides access instructions

**Usage:**
```bash
cd infrastructure/bootstrap
./bootstrap.sh
```

## Worker Management Scripts

### add-worker-nodes.sh
**Location:** `scripts/add-worker-nodes.sh`  
**Purpose:** Adds 4 RKE2 worker nodes to the cluster (static configuration)

**Features:**
- Clones master VM template
- Configures networking for each worker
- Installs RKE2 agent
- Joins workers to cluster
- Verifies node joining

**Usage:**
```bash
# Run on Proxmox server
/tmp/add-worker-nodes.sh
```

### add-worker-nodes-v2.sh
**Location:** `scripts/add-worker-nodes-v2.sh`  
**Purpose:** Advanced script with options for adding worker nodes

**Features:**
- Command-line options for flexibility
- Dry-run mode for preview
- Automatic VM ID detection
- List existing VMs
- Configurable number of workers
- Help documentation

**Options:**
```bash
-h, --help              Show help message
-n, --nodes NUMBER      Number of worker nodes to add (default: 4)
-t, --template VMID     Template VM ID to clone from (default: 200)
-m, --master IP         Master node IP address (default: 192.168.0.201)
-d, --dry-run          Preview without making changes
-l, --list             List existing VMs and nodes
```

**Usage Examples:**
```bash
# Show help
./add-worker-nodes-v2.sh --help

# List existing VMs
./add-worker-nodes-v2.sh --list

# Add 4 workers (default)
./add-worker-nodes-v2.sh

# Add 2 workers
./add-worker-nodes-v2.sh -n 2

# Dry run
./add-worker-nodes-v2.sh -n 4 --dry-run
```

## Verification Scripts

### verify-cluster.sh
**Location:** `scripts/verify-cluster.sh`  
**Purpose:** Comprehensive cluster health check

**Features:**
- Shows all cluster nodes and their status
- Checks system pods health
- Displays node resources (if metrics server installed)
- Lists storage classes
- Shows recent warning events
- Tests pod scheduling across nodes
- Provides summary of cluster state

**Usage:**
```bash
# Run from workstation with kubectl configured
./scripts/verify-cluster.sh
```

**Output includes:**
- Node count and readiness
- System pod status
- Resource utilization
- Storage configuration
- Recent issues/warnings

## SSH Setup Scripts

### ssh-agent-setup.sh
**Location:** `scripts/ssh-agent-setup.sh`  
**Purpose:** Template for .zshrc SSH agent configuration

**Features:**
- Automatic SSH agent startup
- Key loading on shell start
- Agent reuse across terminals
- Convenient aliases for all nodes

**Usage:**
```bash
# View the configuration
cat scripts/ssh-agent-setup.sh

# Add to your shell configuration
cat scripts/ssh-agent-setup.sh >> ~/.zshrc
source ~/.zshrc
```

**Aliases created:**
- `proxmox` - SSH to Proxmox server
- `rke-master` - SSH to master node
- `rke-worker1` through `rke-worker6` - SSH to worker nodes

## Script Execution Flow

### Complete Installation Flow

1. **Prepare cluster:**
   ```bash
   ./infrastructure/docs/prerequisites.sh
   ```

2. **Install ArgoCD:**
   ```bash
   ./infrastructure/bootstrap/bootstrap.sh
   ```

3. **Deploy infrastructure:**
   ```bash
   kubectl apply -f gitops/bootstrap/infrastructure.yaml
   ```

4. **Add worker nodes (on Proxmox):**
   ```bash
   ./add-worker-nodes-v2.sh -n 4
   ```

5. **Verify cluster:**
   ```bash
   ./scripts/verify-cluster.sh
   ```

## Best Practices

### Running Scripts

1. **Always check prerequisites first**
   - Run verification scripts before making changes
   - Use dry-run mode when available

2. **Use version control**
   - Commit changes before running scripts
   - Document any customizations

3. **Monitor progress**
   - Watch script output for errors
   - Verify results after completion

### Script Maintenance

1. **Keep scripts updated**
   - Update IP ranges and versions as needed
   - Test scripts in dev environment first

2. **Document changes**
   - Update this documentation when modifying scripts
   - Add comments in scripts for clarity

3. **Error handling**
   - Scripts use `set -euo pipefail` for safety
   - Check return codes and handle failures

## Troubleshooting

### Common Issues

1. **Permission denied**
   - Ensure scripts are executable: `chmod +x script.sh`
   - Check SSH keys are loaded: `ssh-add -l`

2. **Command not found**
   - Verify required tools are installed
   - Check PATH includes script locations

3. **Connection failures**
   - Verify network connectivity
   - Check firewall rules
   - Ensure services are running

### Debug Mode

Most scripts support verbose output:
```bash
# Run with bash debug mode
bash -x ./script.sh

# Or modify script temporarily
set -x  # Add at beginning for debug output
```
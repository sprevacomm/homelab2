# Adding Additional RKE2 Worker Nodes

This guide explains how to add 4 more worker nodes to your existing RKE2 cluster.

## Current State

- **Master**: rke2-master-01 (192.168.0.201) - VM 200
- **Worker 1**: rke2-worker-01 (192.168.0.202) - VM 201
- **Worker 2**: rke2-worker-02 (192.168.0.203) - VM 202

## New Workers to Add

- **Worker 3**: rke2-worker-03 (192.168.0.204) - VM 203
- **Worker 4**: rke2-worker-04 (192.168.0.205) - VM 204
- **Worker 5**: rke2-worker-05 (192.168.0.206) - VM 205
- **Worker 6**: rke2-worker-06 (192.168.0.207) - VM 206

## Prerequisites

### SSH Access Setup

Before you can run the scripts, ensure SSH access is working:

```bash
# If you get "Permission denied (publickey)", run:
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/workm4

# Or better, set up automatic SSH agent loading
# See: docs/SSH_SETUP.md
```

## Automated Installation

### Option 1: Using the Basic Script

```bash
# Copy script to Proxmox
scp -P 2222 scripts/add-worker-nodes.sh root@192.168.0.20:/tmp/

# SSH to Proxmox
ssh -p 2222 root@192.168.0.20
# Or use alias if configured: proxmox

# Run the script (adds 4 workers)
chmod +x /tmp/add-worker-nodes.sh
/tmp/add-worker-nodes.sh
```

### Option 2: Using the Advanced Script

```bash
# Copy improved script with options
scp -P 2222 scripts/add-worker-nodes-v2.sh root@192.168.0.20:/tmp/

# SSH to Proxmox
proxmox

# Make executable
chmod +x /tmp/add-worker-nodes-v2.sh

# Show help and options
/tmp/add-worker-nodes-v2.sh --help

# List existing VMs first
/tmp/add-worker-nodes-v2.sh --list

# Add specific number of workers
/tmp/add-worker-nodes-v2.sh -n 4  # Add 4 workers
/tmp/add-worker-nodes-v2.sh -n 2  # Add 2 workers

# Dry run to preview
/tmp/add-worker-nodes-v2.sh -n 4 --dry-run
```

#### Script Options:
- `-h, --help` - Show usage information
- `-n, --nodes NUMBER` - Number of workers to add (default: 4)
- `-t, --template VMID` - Template VM to clone (default: 200)
- `-m, --master IP` - Master node IP (default: 192.168.0.201)
- `-d, --dry-run` - Preview without making changes
- `-l, --list` - List existing VMs and nodes

## Manual Installation Steps

If you prefer to do it manually or need to troubleshoot:

### 1. SSH to Proxmox

```bash
ssh -p 2222 root@192.168.0.20
```

### 2. Create Worker VMs

```bash
# Create worker-03
qm clone 200 203 --name rke2-worker-03 --full
qm set 203 --ipconfig0 ip=192.168.0.204/24,gw=192.168.0.1 --sshkeys /root/.ssh/id_rsa.pub
qm start 203

# Create worker-04
qm clone 200 204 --name rke2-worker-04 --full
qm set 204 --ipconfig0 ip=192.168.0.205/24,gw=192.168.0.1 --sshkeys /root/.ssh/id_rsa.pub
qm start 204

# Create worker-05
qm clone 200 205 --name rke2-worker-05 --full
qm set 205 --ipconfig0 ip=192.168.0.206/24,gw=192.168.0.1 --sshkeys /root/.ssh/id_rsa.pub
qm start 205

# Create worker-06
qm clone 200 206 --name rke2-worker-06 --full
qm set 206 --ipconfig0 ip=192.168.0.207/24,gw=192.168.0.1 --sshkeys /root/.ssh/id_rsa.pub
qm start 206
```

### 3. Wait for VMs to Boot

```bash
# Wait 60 seconds for cloud-init
sleep 60

# Clear SSH known hosts
for i in 204 205 206 207; do
    ssh-keygen -f '/root/.ssh/known_hosts' -R "192.168.0.$i"
done
```

### 4. Get Node Token from Master

```bash
NODE_TOKEN=$(ssh ubuntu@192.168.0.201 'sudo cat /var/lib/rancher/rke2/server/node-token')
echo "Node token: $NODE_TOKEN"
```

### 5. Install RKE2 on Each Worker

For each worker (204-207):

```bash
# Worker-03 (192.168.0.204)
ssh -o StrictHostKeyChecking=no ubuntu@192.168.0.204 'curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sudo sh -'

ssh ubuntu@192.168.0.204 "sudo mkdir -p /etc/rancher/rke2 && \
  echo 'server: https://192.168.0.201:9345' | sudo tee /etc/rancher/rke2/config.yaml && \
  echo 'token: $NODE_TOKEN' | sudo tee -a /etc/rancher/rke2/config.yaml"

ssh ubuntu@192.168.0.204 'sudo systemctl enable rke2-agent.service && sudo systemctl start rke2-agent.service'
```

Repeat for workers 205, 206, and 207.

### 6. Verify Nodes Joined

```bash
# Check from master
ssh ubuntu@192.168.0.201 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes'
```

## Verification from Workstation

After adding the nodes:

```bash
# Update local kubeconfig if needed
scp -P 2222 root@192.168.0.20:~/.kube/config ~/.kube/rke2-config

# Check nodes
kubectl get nodes -o wide

# Expected output:
NAME              STATUS   ROLES                       AGE   VERSION
rke2-master-01    Ready    control-plane,etcd,master   24h   v1.31.x+rke2
rke2-worker-01    Ready    <none>                      24h   v1.31.x+rke2
rke2-worker-02    Ready    <none>                      24h   v1.31.x+rke2
rke2-worker-03    Ready    <none>                      5m    v1.31.x+rke2
rke2-worker-04    Ready    <none>                      5m    v1.31.x+rke2
rke2-worker-05    Ready    <none>                      5m    v1.31.x+rke2
rke2-worker-06    Ready    <none>                      5m    v1.31.x+rke2
```

## Run Verification Script

```bash
# From your workstation
cd ~/gits/homelab2
chmod +x scripts/verify-cluster.sh
./scripts/verify-cluster.sh
```

## Troubleshooting

### If a node doesn't join:

1. **Check agent logs:**
   ```bash
   ssh ubuntu@192.168.0.204 'sudo journalctl -u rke2-agent -f'
   ```

2. **Verify network connectivity:**
   ```bash
   ssh ubuntu@192.168.0.204 'ping -c 3 192.168.0.201'
   ssh ubuntu@192.168.0.204 'curl -k https://192.168.0.201:9345'
   ```

3. **Check token is correct:**
   ```bash
   ssh ubuntu@192.168.0.204 'sudo cat /etc/rancher/rke2/config.yaml'
   ```

4. **Restart agent if needed:**
   ```bash
   ssh ubuntu@192.168.0.204 'sudo systemctl restart rke2-agent'
   ```

## Resource Recommendations

With 7 nodes total (1 master + 6 workers), you now have:
- **CPU**: 28 cores total (4 per node)
- **RAM**: 56GB total (8GB per node)
- **Capacity**: Can handle production workloads

Consider:
1. Labeling nodes for specific workloads
2. Setting up node affinity rules
3. Implementing pod disruption budgets
4. Configuring resource quotas per namespace
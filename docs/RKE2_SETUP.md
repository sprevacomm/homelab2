# Proxmox RKE2 Kubernetes Cluster Setup Guide

This guide documents the complete setup of a Proxmox server with 10Gb networking and RKE2 Kubernetes cluster deployment.

## Proxmox Network Configuration

### 1. Adding SFP+ 10Gb Network Adapter

```bash
# SSH into Proxmox server
ssh -p 2222 root@192.168.0.10

# Check network interfaces
ip link show

# Identify SFP+ interfaces (enp5s0f0np0 and enp5s0f1np1)
# Bring up interfaces to detect link
ip link set enp5s0f0np0 up
ip link set enp5s0f1np1 up

# Create bridge for 10Gb network
cat >> /etc/network/interfaces << 'EOF'

auto vmbr1
iface vmbr1 inet static
	address 192.168.0.20/24
	gateway 192.168.0.1
	bridge-ports enp5s0f0np0
	bridge-stp off
	bridge-fd 0
	mtu 9000
EOF

# Apply configuration
ifup vmbr1
```

### 2. Migrating Proxmox to 10Gb Interface

```bash
# Backup network configuration
cp /etc/network/interfaces /etc/network/interfaces.backup-$(date +%Y%m%d-%H%M%S)

# Create new network configuration
cat > /etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

iface enp3s0 inet manual

auto vmbr0
iface vmbr0 inet manual
	bridge-ports enp3s0
	bridge-stp off
	bridge-fd 0

auto vmbr1
iface vmbr1 inet static
	address 192.168.0.20/24
	gateway 192.168.0.1
	bridge-ports enp5s0f0np0
	bridge-stp off
	bridge-fd 0
	mtu 9000

source /etc/network/interfaces.d/*
EOF

# Restart networking
systemctl restart networking
```

### 3. Disabling Subscription Popup

```bash
# Backup original file
cp /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.bak

# Apply patch for Proxmox 8.x
sed -i.bak "s/res === null || res === undefined || \\!res || res/false || res === null || res === undefined || \\!res || res/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js

# Restart proxy service
systemctl restart pveproxy

# Update DNS
echo 'nameserver 1.1.1.1' >> /etc/resolv.conf
```

## RKE2 Kubernetes Cluster Deployment

### Prerequisites

```bash
# Install required packages on Proxmox
apt-get update -qq
apt-get install -y sshpass

# Generate SSH key for cloud-init
ssh-keygen -t rsa -N '' -f /root/.ssh/id_rsa -q

# Download Ubuntu cloud image
cd /var/lib/vz/template/iso
wget -q https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
```

### Creating RKE2 Master Node

```bash
# Create VM for master node
qm create 200 \
  --name rke2-master-01 \
  --memory 8192 \
  --cores 4 \
  --net0 virtio,bridge=vmbr1 \
  --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:32 \
  --ide2 local-lvm:cloudinit \
  --boot c \
  --bootdisk scsi0 \
  --serial0 socket \
  --vga serial0 \
  --agent enabled=1

# Import Ubuntu cloud image
qm importdisk 200 /var/lib/vz/template/iso/jammy-server-cloudimg-amd64.img local-lvm

# Set imported disk as boot disk
qm set 200 --scsi0 local-lvm:vm-200-disk-1 --boot c --bootdisk scsi0

# Configure cloud-init
qm set 200 \
  --ipconfig0 ip=192.168.0.201/24,gw=192.168.0.1 \
  --nameserver 1.1.1.1 \
  --ciuser ubuntu \
  --sshkeys /root/.ssh/id_rsa.pub

# Clean up and resize disk
qm disk unlink 200 --idlist unused0
qm disk resize 200 scsi0 +28G

# Start master node
qm start 200
```

### Creating Worker Nodes

```bash
# Clone master VM for workers
for i in 1 2; do 
  qm clone 200 20$i --name rke2-worker-0$i --full
  qm set 20$i --ipconfig0 ip=192.168.0.20$((i+1))/24,gw=192.168.0.1
  qm set 20$i --sshkeys /root/.ssh/id_rsa.pub
done

# Start worker nodes
qm start 201
qm start 202
```

### Installing RKE2

```bash
# Wait for VMs to boot
sleep 45

# Clear known hosts
ssh-keygen -f '/root/.ssh/known_hosts' -R '192.168.0.201'
ssh-keygen -f '/root/.ssh/known_hosts' -R '192.168.0.202'
ssh-keygen -f '/root/.ssh/known_hosts' -R '192.168.0.203'

# Install RKE2 on master node
ssh -o StrictHostKeyChecking=no ubuntu@192.168.0.201 'curl -sfL https://get.rke2.io | sudo sh -'

# Enable and start RKE2 server
ssh ubuntu@192.168.0.201 'sudo systemctl enable rke2-server.service && sudo systemctl start rke2-server.service'

# Wait for RKE2 to initialize
sleep 60

# Get node token
NODE_TOKEN=$(ssh ubuntu@192.168.0.201 'sudo cat /var/lib/rancher/rke2/server/node-token')

# Install RKE2 agent on worker nodes
for i in 202 203; do 
  ssh -o StrictHostKeyChecking=no ubuntu@192.168.0.$i 'curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sudo sh -'
done

# Configure worker nodes to join cluster
for i in 202 203; do 
  ssh ubuntu@192.168.0.$i "sudo mkdir -p /etc/rancher/rke2 && \
    echo 'server: https://192.168.0.201:9345' | sudo tee /etc/rancher/rke2/config.yaml && \
    echo 'token: $NODE_TOKEN' | sudo tee -a /etc/rancher/rke2/config.yaml"
done

# Enable and start RKE2 agents
for i in 202 203; do 
  ssh ubuntu@192.168.0.$i 'sudo systemctl enable rke2-agent.service && sudo systemctl start rke2-agent.service'
done

# Wait for nodes to join
sleep 60

# Verify cluster nodes
ssh ubuntu@192.168.0.201 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes'
```

### Setting up kubectl Access

```bash
# Copy kubeconfig to Proxmox host
mkdir -p ~/.kube
ssh ubuntu@192.168.0.201 'sudo cat /etc/rancher/rke2/rke2.yaml' | sed 's/127.0.0.1/192.168.0.201/' > ~/.kube/config

# Install kubectl
curl -LO https://dl.k8s.io/release/v1.32.0/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl /usr/local/bin/

# Test kubectl access
kubectl get nodes -o wide
```

## VM Details

| VM ID | Name | IP Address | CPU | RAM | Role |
|-------|------|------------|-----|-----|------|
| 200 | rke2-master-01 | 192.168.0.201 | 4 | 8GB | Master |
| 201 | rke2-worker-01 | 192.168.0.202 | 4 | 8GB | Worker |
| 202 | rke2-worker-02 | 192.168.0.203 | 4 | 8GB | Worker |

## Access Information

- **Proxmox Web UI**: https://192.168.0.20:8006
- **SSH Access**: `ssh -p 2222 root@192.168.0.20`
- **Network**: 10Gb SFP+ on vmbr1
- **DNS**: 1.1.1.1

### SSH Key Setup

If you get "Permission denied (publickey)" when trying to SSH:

```bash
# Quick fix - manually load key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/workm4

# Permanent fix - add to ~/.zshrc
# See docs/SSH_SETUP.md for automatic SSH agent configuration
```

Or use the web console at https://192.168.0.20:8006

## Cluster Verification

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Deploy a test application
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get svc nginx
```

## Accessing the Cluster from Your Workstation

### 1. Copy kubeconfig to your workstation
```bash
# From your workstation
scp -P 2222 root@192.168.0.20:~/.kube/config ~/.kube/proxmox-rke2
```

### 2. Merge into your existing kubeconfig

```bash
# Copy the RKE2 kubeconfig to a temporary file
scp -P 2222 root@192.168.0.20:~/.kube/config /tmp/rke2-config

# Backup your existing config
cp ~/.kube/config ~/.kube/config.backup

# Merge the configs
KUBECONFIG=~/.kube/config:/tmp/rke2-config kubectl config view --flatten > ~/.kube/config.new
mv ~/.kube/config.new ~/.kube/config

# Clean up temp file
rm /tmp/rke2-config

# Rename the context to something descriptive
kubectl config rename-context default rke2-proxmox

# List all contexts
kubectl config get-contexts
```

### 3. Use with kubectx/kubens (recommended)

```bash
# List all contexts
kubectx

# Switch to RKE2 cluster
kubectx rke2-proxmox

# Switch back to another cluster
kubectx your-other-cluster
```

### 4. Verify connection
```bash
kubectl cluster-info
kubectl get nodes -o wide
```

The cluster is accessible at `https://192.168.0.201:6443` from your workstation.

## Useful Commands

```bash
# SSH to nodes from Proxmox
ssh ubuntu@192.168.0.201  # Master
ssh ubuntu@192.168.0.202  # Worker 1
ssh ubuntu@192.168.0.203  # Worker 2

# Check RKE2 service status
ssh ubuntu@192.168.0.201 'sudo systemctl status rke2-server'
ssh ubuntu@192.168.0.202 'sudo systemctl status rke2-agent'

# View RKE2 logs
ssh ubuntu@192.168.0.201 'sudo journalctl -u rke2-server -f'
ssh ubuntu@192.168.0.202 'sudo journalctl -u rke2-agent -f'
```

## Troubleshooting

### If a node fails to join:
```bash
# Check agent logs
ssh ubuntu@192.168.0.202 'sudo journalctl -u rke2-agent -n 50'

# Verify token
ssh ubuntu@192.168.0.201 'sudo cat /var/lib/rancher/rke2/server/node-token'

# Restart agent
ssh ubuntu@192.168.0.202 'sudo systemctl restart rke2-agent'
```

### Reset a node:
```bash
# Stop RKE2
ssh ubuntu@192.168.0.202 'sudo systemctl stop rke2-agent'

# Uninstall RKE2
ssh ubuntu@192.168.0.202 'sudo /usr/local/bin/rke2-uninstall.sh'

# Reinstall following the worker node steps above
```

## Next Steps

1. Install Helm: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`
2. Deploy ingress controller (nginx/traefik)
3. Configure storage classes (Longhorn/OpenEBS)
4. Set up monitoring (Prometheus/Grafana)
5. Deploy sample applications
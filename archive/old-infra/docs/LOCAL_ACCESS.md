# Local Access Without Public DNS

## Quick Start - /etc/hosts Method

For immediate access without setting up DNS, add these entries to your local machine's hosts file:

### On macOS/Linux
```bash
# Edit hosts file
sudo nano /etc/hosts

# Add these lines (replace 192.168.1.200 with your actual LoadBalancer IP)
192.168.1.200 argocd.susdomain.name
192.168.1.200 traefik.susdomain.name
192.168.1.200 grafana.susdomain.name
192.168.1.200 prometheus.susdomain.name
192.168.1.200 alertmanager.susdomain.name
192.168.1.200 adguard.susdomain.name
```

### On Windows
```powershell
# Run as Administrator
notepad C:\Windows\System32\drivers\etc\hosts

# Add the same entries as above
```

## AdGuard Home Setup (Recommended)

AdGuard Home provides local DNS for your entire network:

1. **Deploy AdGuard Home**
   ```bash
   kubectl apply -f ../../gitops/infrastructure/adguard.yaml
   ```

2. **Configure Router**
   - Set router's DNS server to: `192.168.1.201`
   - Or configure individual devices

3. **Access AdGuard Admin**
   - URL: `https://adguard.susdomain.name`
   - Or directly: `http://192.168.1.201:3000`
   - Password: `admin` (change immediately!)

## Benefits of Each Approach

### /etc/hosts
- ✅ Immediate access
- ✅ No additional services
- ❌ Must configure each device
- ❌ No wildcard support

### AdGuard Home
- ✅ Network-wide DNS
- ✅ Ad blocking included
- ✅ Easy management UI
- ✅ Wildcard DNS support
- ❌ Requires dedicated IP

### CoreDNS Custom
- ✅ Integrated with Kubernetes
- ✅ No additional services
- ❌ Only works within cluster
- ❌ Complex configuration

## SSL Certificates with Local DNS

When using local DNS only:

1. **Self-Signed Certificates**
   - Traefik can generate self-signed certs
   - Browser warnings will appear

2. **Let's Encrypt with DNS Challenge**
   - Requires DNS provider API access
   - Works without public access
   - Need to install cert-manager

3. **Use HTTP Only** (Not Recommended)
   - Disable HTTPS redirects in Traefik
   - Only for testing

## Recommended Setup

1. **For Homelab**: Use AdGuard Home
   - Provides DNS for entire network
   - Includes useful features
   - Easy to manage

2. **For Testing**: Use /etc/hosts
   - Quick setup
   - No dependencies
   - Good for development

3. **For Production**: Use proper DNS
   - Public or private DNS server
   - Proper SSL certificates
   - Professional setup
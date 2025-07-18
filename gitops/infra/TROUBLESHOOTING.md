# Troubleshooting Guide

This guide covers common issues and their solutions for the homelab infrastructure components.

## Table of Contents

- [General Troubleshooting](#general-troubleshooting)
- [ArgoCD Issues](#argocd-issues)
- [MetalLB Issues](#metallb-issues)
- [Traefik Issues](#traefik-issues)
- [DNS Issues](#dns-issues)
- [SSL/TLS Issues](#ssltls-issues)
- [Network Issues](#network-issues)
- [Storage Issues](#storage-issues)

## General Troubleshooting

### Checking Component Health

```bash
# Check all pods across namespaces
kubectl get pods --all-namespaces | grep -E "(argocd|metallb|traefik)"

# Check specific namespace
kubectl get all -n argocd
kubectl get all -n metallb-system
kubectl get all -n traefik

# Check events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### Viewing Logs

```bash
# Pod logs
kubectl logs -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name> -f  # Follow logs
kubectl logs -n <namespace> <pod-name> --previous  # Previous container

# Deployment logs
kubectl logs -n <namespace> deployment/<deployment-name>

# All containers in pod
kubectl logs -n <namespace> <pod-name> --all-containers
```

### Describing Resources

```bash
# Describe pod for detailed info
kubectl describe pod -n <namespace> <pod-name>

# Describe service
kubectl describe svc -n <namespace> <service-name>

# Describe ingress/ingressroute
kubectl describe ingress -n <namespace> <ingress-name>
kubectl describe ingressroute -n <namespace> <ingressroute-name>
```

## ArgoCD Issues

### Application Won't Sync

**Symptoms:**
- Application shows "OutOfSync" status
- Sync fails with error

**Solutions:**

1. **Check application details:**
   ```bash
   kubectl describe application <app-name> -n argocd
   argocd app get <app-name>
   ```

2. **Force refresh:**
   ```bash
   argocd app get <app-name> --refresh
   kubectl patch application <app-name> -n argocd --type merge -p '{"metadata": {"annotations": {"argocd.argoproj.io/refresh": "normal"}}}'
   ```

3. **Check repository access:**
   ```bash
   argocd repo list
   kubectl get secret -n argocd repo-* -o yaml
   ```

4. **Manual sync with retry:**
   ```bash
   argocd app sync <app-name> --retry-limit 5
   ```

### Cannot Access ArgoCD UI

**Symptoms:**
- Connection refused or timeout
- 404 error

**Solutions:**

1. **Check if server pod is running:**
   ```bash
   kubectl get pods -n argocd | grep argocd-server
   kubectl logs -n argocd deployment/argocd-server
   ```

2. **Verify ingress configuration:**
   ```bash
   kubectl get ingress -n argocd
   kubectl describe ingress argocd-server -n argocd
   ```

3. **Test with port-forward:**
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   # Access at https://localhost:8080
   ```

### Authentication Issues

**Symptoms:**
- Cannot login with admin password
- "Invalid username or password"

**Solutions:**

1. **Get initial admin password:**
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

2. **Reset admin password:**
   ```bash
   # Using bcrypt generator
   htpasswd -nbBC 10 "" "newpassword" | tr -d ':\n' | sed 's/$2y/$2a/'
   
   # Update secret
   kubectl -n argocd patch secret argocd-secret \
     -p '{"data": {"admin.password": "'$(htpasswd -nbBC 10 "" "newpassword" | tr -d ':\n' | sed 's/$2y/$2a/' | base64 -w 0)'"}}'
   ```

3. **Restart server:**
   ```bash
   kubectl rollout restart deployment argocd-server -n argocd
   ```

## MetalLB Issues

### Service Stuck in Pending

**Symptoms:**
- LoadBalancer service shows `<pending>` for EXTERNAL-IP
- No IP assigned

**Solutions:**

1. **Check MetalLB pods:**
   ```bash
   kubectl get pods -n metallb-system
   kubectl logs -n metallb-system -l app.kubernetes.io/component=controller
   ```

2. **Verify IP pool configuration:**
   ```bash
   kubectl get ipaddresspool -n metallb-system
   kubectl describe ipaddresspool default-pool -n metallb-system
   ```

3. **Check for IP exhaustion:**
   ```bash
   kubectl get svc --all-namespaces | grep LoadBalancer
   ```

4. **Verify L2Advertisement:**
   ```bash
   kubectl get l2advertisement -n metallb-system
   ```

### IP Not Accessible

**Symptoms:**
- IP assigned but cannot connect
- ARP not responding

**Solutions:**

1. **Check speaker logs:**
   ```bash
   kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker --all-containers
   ```

2. **Verify network connectivity:**
   ```bash
   # From a node
   arping <service-ip>
   
   # Check ARP table
   arp -a | grep <service-ip>
   ```

3. **Check speaker is running on all nodes:**
   ```bash
   kubectl get pods -n metallb-system -l app.kubernetes.io/component=speaker -o wide
   ```

### IP Conflicts

**Symptoms:**
- Intermittent connectivity
- ARP warnings in logs

**Solutions:**

1. **Scan for conflicts:**
   ```bash
   # From a Linux machine on the network
   nmap -sn 192.168.1.200-250  # Your IP range
   ```

2. **Check DHCP server configuration:**
   - Ensure MetalLB range is outside DHCP pool
   - Reserve IPs in DHCP server

3. **Change IP pool:**
   ```yaml
   # Edit ipaddresspool.yaml
   spec:
     addresses:
       - 192.168.1.240-192.168.1.250  # New range
   ```

## Traefik Issues

### Cannot Access Services

**Symptoms:**
- 404 page not found
- Bad gateway errors
- Connection refused

**Solutions:**

1. **Check Traefik pod:**
   ```bash
   kubectl get pods -n traefik
   kubectl logs -n traefik deployment/traefik
   ```

2. **Verify ingress/ingressroute:**
   ```bash
   kubectl get ingress,ingressroute --all-namespaces
   kubectl describe ingressroute <name> -n <namespace>
   ```

3. **Test service directly:**
   ```bash
   # Port-forward to service
   kubectl port-forward -n <namespace> svc/<service> 8080:80
   curl http://localhost:8080
   ```

4. **Check Traefik dashboard:**
   ```bash
   kubectl port-forward -n traefik deployment/traefik 8080:8080
   # Open http://localhost:8080/dashboard/
   ```

### SSL Certificate Issues

**Symptoms:**
- Certificate warnings
- ERR_CERT_AUTHORITY_INVALID
- No certificate generated

**Solutions:**

1. **Check ACME logs:**
   ```bash
   kubectl logs -n traefik deployment/traefik | grep -i acme
   ```

2. **Verify DNS is correct:**
   ```bash
   nslookup myapp.susdomain.name
   # Should return your LoadBalancer IP
   ```

3. **Check certificate resolver:**
   ```bash
   # If using persistence
   kubectl exec -n traefik deployment/traefik -- ls -la /data/
   kubectl exec -n traefik deployment/traefik -- cat /data/acme.json
   ```

4. **Switch to staging for testing:**
   ```yaml
   # In values.yaml
   additionalArguments:
     - "--certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory"
   ```

### Middleware Not Working

**Symptoms:**
- Headers not applied
- Authentication bypassed
- Rate limiting not working

**Solutions:**

1. **Verify middleware exists:**
   ```bash
   kubectl get middleware --all-namespaces
   kubectl describe middleware <name> -n <namespace>
   ```

2. **Check middleware reference:**
   ```yaml
   # IngressRoute should reference correctly
   middlewares:
     - name: default-headers
       namespace: traefik  # Include namespace if different
   ```

3. **Test with curl:**
   ```bash
   curl -v https://myapp.susdomain.name
   # Check response headers
   ```

## DNS Issues

### DNS Not Resolving

**Symptoms:**
- Cannot resolve *.susdomain.name
- NXDOMAIN errors

**Solutions:**

1. **Verify DNS configuration:**
   ```bash
   # Check DNS propagation
   dig myapp.susdomain.name
   nslookup myapp.susdomain.name 8.8.8.8
   ```

2. **Test from different locations:**
   - Use online DNS checkers
   - Test from different networks

3. **Check wildcard setup:**
   ```bash
   dig *.susdomain.name
   dig argocd.susdomain.name
   dig traefik.susdomain.name
   ```

### Wrong IP Returned

**Symptoms:**
- DNS resolves to wrong IP
- Old IP cached

**Solutions:**

1. **Clear DNS cache:**
   ```bash
   # Linux
   sudo systemctl restart systemd-resolved
   
   # macOS
   sudo dscacheutil -flushcache
   
   # Windows
   ipconfig /flushdns
   ```

2. **Check TTL:**
   ```bash
   dig +nocmd +noall +answer myapp.susdomain.name
   ```

3. **Wait for propagation:**
   - DNS changes can take up to 48 hours
   - Use low TTL (300s) for faster updates

## SSL/TLS Issues

### Certificate Not Trusted

**Symptoms:**
- Browser shows warning
- NET::ERR_CERT_AUTHORITY_INVALID

**Solutions:**

1. **Check if using staging:**
   ```bash
   kubectl logs -n traefik deployment/traefik | grep staging
   ```

2. **Verify certificate details:**
   ```bash
   echo | openssl s_client -connect myapp.susdomain.name:443 -servername myapp.susdomain.name 2>/dev/null | openssl x509 -text -noout
   ```

3. **Force certificate renewal:**
   ```bash
   # Delete acme.json if using persistence
   kubectl exec -n traefik deployment/traefik -- rm /data/acme.json
   kubectl rollout restart deployment/traefik -n traefik
   ```

### Let's Encrypt Rate Limits

**Symptoms:**
- "too many certificates" error
- Rate limit exceeded

**Solutions:**

1. **Use staging environment:**
   ```yaml
   additionalArguments:
     - "--certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory"
   ```

2. **Check rate limit status:**
   - Visit: https://crt.sh/?q=susdomain.name
   - Count certificates issued

3. **Wait for reset:**
   - Most limits reset after 1 week
   - Staging has much higher limits

## Network Issues

### Cannot Connect Between Pods

**Symptoms:**
- Services cannot reach each other
- Connection timeouts

**Solutions:**

1. **Check network policies:**
   ```bash
   kubectl get networkpolicies --all-namespaces
   ```

2. **Test connectivity:**
   ```bash
   # Run debug pod
   kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
   
   # Inside debug pod
   nslookup kubernetes.default
   nc -zv service-name.namespace 80
   ```

3. **Check CoreDNS:**
   ```bash
   kubectl get pods -n kube-system | grep coredns
   kubectl logs -n kube-system -l k8s-app=kube-dns
   ```

### LoadBalancer IP Not Reachable from Outside

**Symptoms:**
- Can access from nodes but not external
- Firewall blocking

**Solutions:**

1. **Check node firewall:**
   ```bash
   # On each node
   sudo iptables -L -n
   sudo ufw status
   ```

2. **Verify routing:**
   ```bash
   ip route
   traceroute 192.168.1.200
   ```

3. **Check cloud provider security groups:**
   - Ensure ports 80/443 are open
   - Check source IP restrictions

## Storage Issues

### PVC Stuck in Pending

**Symptoms:**
- PersistentVolumeClaim pending
- Pod waiting for volume

**Solutions:**

1. **Check storage class:**
   ```bash
   kubectl get storageclass
   kubectl get pv
   kubectl describe pvc <pvc-name> -n <namespace>
   ```

2. **Install local-path-provisioner:**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml
   ```

3. **Use hostPath for testing:**
   ```yaml
   volumes:
     - name: data
       hostPath:
         path: /tmp/traefik-data
         type: DirectoryOrCreate
   ```

### No Space Left

**Symptoms:**
- Pods crashing with disk errors
- Cannot write to volume

**Solutions:**

1. **Check disk usage:**
   ```bash
   kubectl exec -n <namespace> <pod> -- df -h
   ```

2. **Clean up unused resources:**
   ```bash
   # Remove unused images
   kubectl get nodes -o wide
   # SSH to each node
   docker system prune -a
   ```

3. **Expand PVC:**
   ```yaml
   # Edit PVC
   spec:
     resources:
       requests:
         storage: 10Gi  # Increase size
   ```

## General Tips

### Enable Debug Logging

**ArgoCD:**
```yaml
configs:
  params:
    controller.log.level: debug
    server.log.level: debug
```

**Traefik:**
```yaml
logs:
  general:
    level: DEBUG
```

**MetalLB:**
```bash
kubectl logs -n metallb-system -l app.kubernetes.io/component=controller --v=5
```

### Useful Commands

```bash
# Get all resources in a namespace
kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --show-kind --ignore-not-found -n <namespace>

# Watch resources
kubectl get pods -n <namespace> -w

# Get YAML of running resource
kubectl get <resource> <name> -n <namespace> -o yaml

# Explain resource fields
kubectl explain <resource>.<field>

# Dry run to test
kubectl apply -f manifest.yaml --dry-run=client

# Force delete stuck resources
kubectl delete <resource> <name> -n <namespace> --force --grace-period=0
```

## Getting Help

If these solutions don't resolve your issue:

1. **Check component logs thoroughly**
2. **Search GitHub issues for the component**
3. **Review official documentation**
4. **Ask in component community channels**
5. **Create detailed issue with:**
   - Component versions
   - Error messages
   - Steps to reproduce
   - What you've tried
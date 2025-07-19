# Monitoring Stack Quick Start Guide

This guide helps you get the monitoring stack up and running quickly.

## Prerequisites

✅ **Before starting, ensure:**
- ArgoCD is installed and running
- MetalLB is providing LoadBalancer IPs
- Traefik is handling ingress
- Storage class is available (30GB+ free space)
- You've updated domain names in YAML files

## 1. Quick Deployment

```bash
# The monitoring stack is already included in the infrastructure
# Just sync the ArgoCD app
argocd app sync infrastructure

# Or apply manually
kubectl apply -f ../../../gitops/infrastructure/monitoring.yaml
kubectl apply -f ../../../gitops/infrastructure/monitoring-config.yaml
```

## 2. Verify Deployment

```bash
# Check all pods are running
kubectl get pods -n monitoring

# Expected output (may take 5-10 minutes):
# NAME                                                     READY   STATUS    
# alertmanager-kube-prometheus-stack-alertmanager-0        2/2     Running
# kube-prometheus-stack-grafana-xxx                        3/3     Running   
# kube-prometheus-stack-kube-state-metrics-xxx             1/1     Running   
# kube-prometheus-stack-operator-xxx                       1/1     Running   
# kube-prometheus-stack-prometheus-node-exporter-xxx       1/1     Running   
# prometheus-kube-prometheus-stack-prometheus-0            2/2     Running   

# Check PVCs are bound
kubectl get pvc -n monitoring
```

## 3. Access Web UIs

### Grafana (Primary Interface)
```bash
# URL: https://grafana.yourdomain.com
# Default login: admin / admin
# Change password on first login!
```

### Prometheus (Metrics Database)
```bash
# URL: https://prometheus.yourdomain.com
# Basic auth: admin / admin
# For queries and target debugging
```

### Alertmanager (Alert Management)
```bash
# URL: https://alertmanager.yourdomain.com
# View active alerts and silences
```

## 4. Import Essential Dashboards

In Grafana UI:
1. Click **+** → **Import**
2. Enter dashboard ID → **Load**
3. Select **Prometheus** data source → **Import**

**Must-Have Dashboards:**
- `1860` - Node Exporter Full (System metrics)
- `7249` - Kubernetes Cluster Overview
- `17346` - Traefik 3.0+ (Ingress metrics)
- `14584` - ArgoCD (GitOps metrics)

## 5. Quick Configuration Changes

### Change Grafana Admin Password
```bash
kubectl exec -n monitoring deployment/kube-prometheus-stack-grafana -- \
  grafana-cli admin reset-admin-password 'newSecurePassword'
```

### Update Prometheus Basic Auth
```bash
# Generate new password
htpasswd -nb admin 'newPassword' | base64

# Edit the secret
kubectl edit secret basic-auth-secret -n monitoring
# Replace the users data with new base64 string
```

### Configure Email Alerts
```yaml
# Edit infrastructure/monitoring/kube-prometheus-stack/values/values.yaml
alertmanager:
  config:
    receivers:
      - name: 'email-notifications'
        email_configs:
          - to: 'your-email@domain.com'
            from: 'alerts@yourdomain.com'
            smarthost: 'smtp.gmail.com:587'
            auth_username: 'your-gmail@gmail.com'
            auth_password: 'app-specific-password'
            
# Apply changes
git add -A && git commit -m "Configure email alerts" && git push
argocd app sync kube-prometheus-stack
```

## 6. Test Monitoring

### Check Metrics Collection
```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Open http://localhost:9090
# Go to Status → Targets
# All targets should be "UP"
```

### Create Test Alert
```bash
# This will trigger a test alert
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -X POST http://alertmanager-operated.monitoring.svc.cluster.local:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning"
    },
    "annotations": {
      "summary": "This is a test alert"
    }
  }]'
```

## 7. Common Tasks

### View Container Logs
```bash
# Prometheus logs
kubectl logs -n monitoring prometheus-kube-prometheus-stack-prometheus-0

# Grafana logs
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana

# Alertmanager logs
kubectl logs -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0
```

### Restart Components
```bash
# Restart Grafana (preserves data)
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring

# Restart Prometheus (brief metrics gap)
kubectl delete pod prometheus-kube-prometheus-stack-prometheus-0 -n monitoring
```

### Check Resource Usage
```bash
# See memory/CPU usage
kubectl top pods -n monitoring

# If Prometheus uses too much memory, reduce retention:
# Edit infrastructure/monitoring/kube-prometheus-stack/values/values.yaml
# Change retention: 30d to retention: 15d
```

## 8. Quick Wins

### Enable Traefik Metrics
Already configured! Check the Traefik dashboard (ID: 17346)

### Monitor Certificate Expiry
Alert rule already included! You'll get warnings 7 days before expiry.

### Pod Crash Notifications
Pre-configured alert! Any pod crashing will trigger an alert.

### High Resource Usage Alerts
CPU > 80% or Memory > 85% will trigger warnings.

## 9. Troubleshooting Quick Fixes

### No Data in Dashboards
```bash
# Check Prometheus is scraping
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets
```

### Grafana Won't Load
```bash
# Check ingress
kubectl get ingress -n monitoring
kubectl describe ingress kube-prometheus-stack-grafana -n monitoring

# Test direct access
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Visit http://localhost:3000
```

### Alerts Not Sending
```bash
# Check Alertmanager config
kubectl logs -n monitoring alertmanager-kube-prometheus-stack-alertmanager-0

# Verify SMTP settings
kubectl get secret -n monitoring alertmanager-kube-prometheus-stack-alertmanager -o yaml
```

## 10. What's Next?

1. **Customize Alerts**
   - Edit `manifests/base/prometheus-rules.yaml`
   - Add business-specific alerts

2. **Create Custom Dashboards**
   - Build in Grafana UI
   - Export JSON
   - Add to ConfigMaps

3. **Add More Exporters**
   - PostgreSQL exporter
   - Redis exporter
   - Custom app metrics

4. **Integrate with Apps**
   - Add `/metrics` endpoint
   - Create ServiceMonitor
   - Build custom dashboard

## Need Help?

- Check logs: `kubectl logs -n monitoring <pod-name>`
- See events: `kubectl get events -n monitoring --sort-by='.lastTimestamp'`
- Review targets: https://prometheus.yourdomain.com/targets
- Check the [full documentation](./README.md)
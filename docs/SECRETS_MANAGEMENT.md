# Secrets Management with SOPS and Age

This guide covers how to manage secrets in your homelab using SOPS (Secrets OPerationS) with Age encryption.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Initial Setup](#initial-setup)
- [Encrypting Secrets](#encrypting-secrets)
- [GitOps Integration](#gitops-integration)
- [External Secrets Operator](#external-secrets-operator)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Backup and Recovery](#backup-and-recovery)

## Overview

Our secrets management approach uses:
- **SOPS**: Mozilla's tool for encrypting files (only values, not keys)
- **Age**: Modern encryption tool (replacement for GPG)
- **ESO**: External Secrets Operator to inject secrets into Kubernetes
- **Git**: Encrypted secrets stored directly in Git

### Why This Approach?

1. **No external dependencies** - Perfect for homelab
2. **GitOps compatible** - Encrypted secrets in Git
3. **Simple key management** - Age is much simpler than GPG
4. **Selective encryption** - Only encrypt sensitive values

## Prerequisites

Install required tools:

```bash
# Install age
# macOS
brew install age

# Linux
wget -O age.tar.gz https://github.com/FiloSottile/age/releases/latest/download/age-v1.1.1-linux-amd64.tar.gz
tar -xzf age.tar.gz
sudo mv age/age /usr/local/bin/
sudo mv age/age-keygen /usr/local/bin/

# Install SOPS
# macOS
brew install sops

# Linux
wget -O sops https://github.com/mozilla/sops/releases/latest/download/sops-v3.8.1.linux.amd64
chmod +x sops
sudo mv sops /usr/local/bin/

# Verify installation
age --version
sops --version
```

## Initial Setup

### 1. Generate Age Key Pair

```bash
# Create config directory
mkdir -p ~/.config/sops/age

# Generate key pair
age-keygen -o ~/.config/sops/age/keys.txt

# View your public key
age-keygen -y ~/.config/sops/age/keys.txt
```

Example output:
```
Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

### 2. Configure SOPS

Create `.sops.yaml` in your repository root:

```yaml
# .sops.yaml
creation_rules:
  # Encrypt specific files
  - path_regex: .*\.secret\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p  # Your public key

  # Encrypt all yaml files in secrets directory
  - path_regex: secrets/.*\.yaml$
    encrypted_regex: ^(data|stringData|spec)$
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p

  # Different key for production
  - path_regex: production/.*\.yaml$
    encrypted_regex: ^(data|stringData)$
    age: age1different7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

### 3. Set Environment Variable

Add to your shell profile:

```bash
# ~/.bashrc or ~/.zshrc
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

## Encrypting Secrets

### Basic Encryption

1. **Create a secret file**:
```yaml
# secrets/database.secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: default
type: Opaque
data:
  username: YWRtaW4=  # base64 encoded "admin"
  password: c3VwZXJzZWNyZXQ=  # base64 encoded "supersecret"
```

2. **Encrypt the file**:
```bash
# SOPS will automatically use .sops.yaml rules
sops -e -i secrets/database.secret.yaml
```

3. **View encrypted file**:
```yaml
apiVersion: v1
kind: Secret
metadata:
    name: database-credentials
    namespace: default
type: Opaque
data:
    username: ENC[AES256_GCM,data:YJzCglk=,iv:...,tag:...,type:str]
    password: ENC[AES256_GCM,data:VghTz5JmHdk=,iv:...,tag:...,type:str]
sops:
    kms: []
    gcp_kms: []
    azure_kv: []
    hc_vault: []
    age:
        - recipient: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
          enc: |
            -----BEGIN AGE ENCRYPTED FILE-----
            ...
            -----END AGE ENCRYPTED FILE-----
    lastmodified: "2024-01-01T00:00:00Z"
    mac: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
    pgp: []
    encrypted_regex: ^(data|stringData)$
    version: 3.8.1
```

### Common Operations

```bash
# Edit encrypted file (opens in $EDITOR)
sops secrets/database.secret.yaml

# Decrypt to stdout
sops -d secrets/database.secret.yaml

# Decrypt to new file
sops -d secrets/database.secret.yaml > decrypted.yaml

# Encrypt specific values only
sops -e --encrypted-regex '^(data|password)$' plain.yaml > encrypted.yaml

# Rotate to new key
sops -r -i --add-age age1newkey... --rm-age age1oldkey... secrets.yaml
```

## GitOps Integration

### ArgoCD with SOPS

1. **Install SOPS plugin for ArgoCD**:

Add to `bootstrap-infrastructure.sh`:
```bash
install_argocd_sops() {
    # Create plugin configuration
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-sops-plugin
  namespace: argocd
data:
  plugin.yaml: |
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: argocd-sops-plugin
    spec:
      version: v1.0
      generate:
        command: ["sh", "-c"]
        args:
          - |
            sops -d "$ARGOCD_ENV_SECRETS_FILE" | kubectl apply -f -
      discover:
        find:
          glob: "*.secret.yaml"
EOF

    # Patch ArgoCD repo server to include SOPS
    kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/initContainers",
        "value": [{
          "name": "install-sops",
          "image": "alpine:3.18",
          "command": ["/bin/sh", "-c"],
          "args": ["wget -O /custom-tools/sops https://github.com/mozilla/sops/releases/download/v3.8.1/sops-v3.8.1.linux.amd64 && chmod +x /custom-tools/sops"],
          "volumeMounts": [{
            "name": "custom-tools",
            "mountPath": "/custom-tools"
          }]
        }]
      }
    ]'
}
```

2. **Mount Age key as secret**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: sops-age-key
  namespace: argocd
type: Opaque
stringData:
  keys.txt: |
    # created: 2024-01-01T00:00:00Z
    # public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
    AGE-SECRET-KEY-1ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890ABCDEFGHIJKLMNOPQR
```

### External Secrets Operator Setup

1. **Install ESO**:
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

2. **Create SOPS SecretStore**:
```yaml
# infrastructure/security/external-secrets/sops-secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: sops-backend
  namespace: default
spec:
  provider:
    kubernetes:
      remoteNamespace: secrets
      server:
        caProvider:
          type: ConfigMap
          name: kube-root-ca.crt
          key: ca.crt
      auth:
        serviceAccount:
          name: external-secrets-sa
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets-sa
  namespace: secrets
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-secrets-sa-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-secrets-controller
subjects:
- kind: ServiceAccount
  name: external-secrets-sa
  namespace: secrets
```

3. **Create ExternalSecret**:
```yaml
# applications/myapp/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
  namespace: myapp
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: sops-backend
    kind: SecretStore
  target:
    name: app-secrets
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: myapp-encrypted-secret  # Reference to K8s secret with encrypted data
```

## Best Practices

### 1. Key Management

```bash
# Create separate keys for different environments
age-keygen -o ~/.config/sops/age/production.txt
age-keygen -o ~/.config/sops/age/staging.txt
age-keygen -o ~/.config/sops/age/development.txt

# Use multiple recipients for team access
sops -e -a age1user1... -a age1user2... secrets.yaml
```

### 2. File Naming Convention

```
secrets/
├── production/
│   ├── database.secret.yaml      # Auto-encrypted by SOPS
│   └── api-keys.secret.yaml
├── staging/
│   └── *.secret.yaml
└── development/
    └── *.secret.yaml
```

### 3. Git Workflow

```bash
# .gitignore
*.decrypted.yaml
*.plain.yaml
!*.secret.yaml  # Only commit encrypted files

# Pre-commit hook (.git/hooks/pre-commit)
#!/bin/bash
# Prevent committing unencrypted secrets
if git diff --cached --name-only | grep -E "\.secret\.yaml$"; then
    for file in $(git diff --cached --name-only | grep -E "\.secret\.yaml$"); do
        if ! grep -q "sops:" "$file"; then
            echo "ERROR: $file appears to be unencrypted!"
            exit 1
        fi
    done
fi
```

### 4. Rotation Policy

```bash
# Quarterly key rotation script
#!/bin/bash
OLD_KEY=$(age-keygen -y ~/.config/sops/age/keys.txt)
age-keygen -o ~/.config/sops/age/keys.new.txt
NEW_KEY=$(age-keygen -y ~/.config/sops/age/keys.new.txt)

# Update all encrypted files
find . -name "*.secret.yaml" -exec sops -r -i --add-age "$NEW_KEY" --rm-age "$OLD_KEY" {} \;

# Update .sops.yaml
sed -i "s/$OLD_KEY/$NEW_KEY/g" .sops.yaml

# Backup old key
mv ~/.config/sops/age/keys.txt ~/.config/sops/age/keys.backup.$(date +%Y%m%d)
mv ~/.config/sops/age/keys.new.txt ~/.config/sops/age/keys.txt
```

## Troubleshooting

### Common Issues

1. **"no key found" error**:
```bash
# Check if key file exists
ls -la ~/.config/sops/age/keys.txt

# Verify environment variable
echo $SOPS_AGE_KEY_FILE

# Try explicit key file
sops -d --age-keyfile ~/.config/sops/age/keys.txt secrets.yaml
```

2. **"mac mismatch" error**:
```bash
# File was modified outside SOPS
# Re-encrypt from backup or known good version
```

3. **ArgoCD not decrypting**:
```bash
# Check SOPS plugin logs
kubectl logs -n argocd deployment/argocd-repo-server

# Verify age key secret
kubectl get secret sops-age-key -n argocd -o yaml
```

## Backup and Recovery

### Critical Backups

1. **Age Private Key** (MOST IMPORTANT):
```bash
# Backup methods (use multiple!):
# 1. Encrypted USB drive
cp ~/.config/sops/age/keys.txt /mnt/secure-usb/

# 2. Password manager
cat ~/.config/sops/age/keys.txt | base64

# 3. Paper backup (seriously!)
age-keygen -y ~/.config/sops/age/keys.txt  # Public key
cat ~/.config/sops/age/keys.txt           # Private key

# 4. Encrypted cloud backup
age -r age1public... ~/.config/sops/age/keys.txt > keys.txt.age
```

2. **Recovery Process**:
```bash
# Restore age key
mkdir -p ~/.config/sops/age
echo "AGE-SECRET-KEY-1..." > ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Verify by decrypting a file
sops -d secrets/test.secret.yaml
```

### Emergency Access

Create a "break glass" key:
```bash
# Generate emergency key
age-keygen -o emergency-key.txt

# Add to all secrets
find . -name "*.secret.yaml" -exec sops -r -i --add-age $(age-keygen -y emergency-key.txt) {} \;

# Store in safe location (physical safe, etc.)
```

## Integration Example

Complete example for a database secret:

```bash
# 1. Create plain secret
cat > database.yaml << EOF
apiVersion: v1
kind: Secret
metadata:
  name: postgres-credentials
  namespace: default
type: Opaque
stringData:
  username: postgres
  password: MySecurePassword123!
  connection-string: postgresql://postgres:MySecurePassword123!@postgres:5432/mydb
EOF

# 2. Encrypt it
sops -e database.yaml > database.secret.yaml
rm database.yaml  # Remove plain version

# 3. Commit to Git
git add database.secret.yaml
git commit -m "Add encrypted database credentials"

# 4. ArgoCD will automatically decrypt when deploying
```

## Summary

This setup provides:
- ✅ No external dependencies (perfect for homelab)
- ✅ GitOps compatible (encrypted secrets in Git)
- ✅ Simple key management (Age > GPG)
- ✅ Team collaboration (multiple recipients)
- ✅ Audit trail (Git history)
- ✅ Easy rotation and recovery

Remember: **ALWAYS backup your Age private key in multiple secure locations!**
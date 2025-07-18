#!/bin/bash
# Bootstrap script for ArgoCD installation

set -e

echo "ArgoCD Bootstrap Script"
echo "======================"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "kubectl could not be found. Please install kubectl first."
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "helm could not be found. Please install helm first."
    exit 1
fi

# Check if prerequisites have been run
echo "Checking prerequisites..."
if ! kubectl get namespace argocd &> /dev/null; then
    echo "ERROR: ArgoCD namespace not found!"
    echo "Please run the prerequisites.sh script first:"
    echo "  cd .. && ./prerequisites.sh"
    exit 1
fi

# Check for storage class
if ! kubectl get storageclass -o json 2>/dev/null | grep -q '"storageclass.kubernetes.io/is-default-class":"true"'; then
    echo "WARNING: No default storage class found!"
    echo "This may cause issues with persistent volumes."
    read -p "Do you want to continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "ArgoCD namespace already exists (created by prerequisites.sh)"

echo "Installing ArgoCD..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 8.1.3 \
  --values values/values.yaml \
  --wait \
  --timeout 10m

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

echo "ArgoCD installation complete!"
echo ""
echo "To access ArgoCD:"
echo "1. The default admin password is: admin"
echo "2. Access the UI at: https://argocd.susdomain.name"
echo "3. Change the admin password after first login using:"
echo "   argocd account update-password"
echo ""
echo "To install the ArgoCD CLI:"
echo "   brew install argocd (macOS)"
echo "   or download from https://github.com/argoproj/argo-cd/releases"
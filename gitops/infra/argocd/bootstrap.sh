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

echo "Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "Creating ArgoCD namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

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
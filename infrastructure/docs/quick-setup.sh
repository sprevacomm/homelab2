#!/bin/bash
# Quick Setup Script - Runs prerequisites and installs ArgoCD
# For experienced users who want to run everything in sequence

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Homelab Quick Setup Script${NC}"
echo -e "${BLUE}================================${NC}"
echo ""
echo -e "${YELLOW}This script will:${NC}"
echo "1. Run prerequisites check and setup"
echo "2. Install ArgoCD"
echo "3. Guide you through configuration"
echo ""
echo -e "${YELLOW}WARNING:${NC} Make sure you have:"
echo "- A working RKE2 cluster"
echo "- kubectl configured"
echo "- Your network IP ranges planned"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Exiting..."
    exit 0
fi

# Run prerequisites
echo -e "\n${BLUE}Running prerequisites...${NC}"
if [ -f ./prerequisites.sh ]; then
    ./prerequisites.sh
else
    echo "ERROR: prerequisites.sh not found!"
    echo "Make sure you're in the gitops/infra directory"
    exit 1
fi

# Check if prerequisites completed successfully
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Prerequisites script did not complete successfully${NC}"
    exit 1
fi

# Configuration reminder
echo -e "\n${YELLOW}IMPORTANT: Before continuing, you must:${NC}"
echo "1. Edit metallb/manifests/base/ipaddresspool.yaml"
echo "   - Update IP range (default: 192.168.1.200-192.168.1.250)"
echo ""
echo "2. Edit traefik/values/values.yaml"
echo "   - Update LoadBalancer IP"
echo "   - Update Let's Encrypt email"
echo ""
echo "3. Replace 'susdomain.name' with your domain in all files"
echo ""
read -p "Have you updated these files? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please update the configuration files first, then run:"
    echo "  cd argocd && ./bootstrap.sh"
    exit 0
fi

# Check if changes are committed
echo -e "\n${BLUE}Checking git status...${NC}"
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}You have uncommitted changes:${NC}"
    git status --short
    echo ""
    read -p "Do you want to commit these changes now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git add -A
        read -p "Enter commit message: " commit_msg
        git commit -m "$commit_msg"
        echo "Changes committed. Don't forget to push to your repository!"
    else
        echo -e "${YELLOW}WARNING: Uncommitted changes detected${NC}"
        echo "ArgoCD will sync from your Git repository, so these changes won't be deployed"
        echo "until they are committed and pushed."
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
fi

# Install ArgoCD
echo -e "\n${BLUE}Installing ArgoCD...${NC}"
cd argocd
./bootstrap.sh

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}ArgoCD installation failed${NC}"
    exit 1
fi

# Post-installation steps
echo -e "\n${GREEN}✓ Installation completed!${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Apply the app-of-apps to deploy infrastructure:"
echo "   kubectl apply -f manifests/base/app-of-apps.yaml"
echo ""
echo "2. Watch the deployment:"
echo "   watch kubectl get applications -n argocd"
echo ""
echo "3. Once Traefik is running, get the LoadBalancer IP:"
echo "   kubectl get svc -n traefik traefik"
echo ""
echo "4. Configure your DNS to point to the LoadBalancer IP"
echo ""
echo "5. Access ArgoCD at https://argocd.yourdomain.com"
echo "   Default password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
echo ""
echo -e "${GREEN}Happy GitOps! 🚀${NC}"
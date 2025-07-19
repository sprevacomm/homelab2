# Kubernetes Configuration
variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "The context to use from the kubeconfig file"
  type        = string
  default     = ""
}

# MetalLB Configuration
variable "metallb_ip_range" {
  description = "IP range for MetalLB to allocate LoadBalancer IPs"
  type        = string
  default     = "192.168.1.200-192.168.1.250"
}

# Domain Configuration
variable "domain" {
  description = "Base domain for all services"
  type        = string
  default     = "homelab.local"
}

# Let's Encrypt Configuration
variable "acme_email" {
  description = "Email address for Let's Encrypt certificates"
  type        = string
  default     = "admin@homelab.local"
}

# Feature Flags
variable "enable_monitoring" {
  description = "Enable monitoring stack (Prometheus, Grafana)"
  type        = bool
  default     = true
}

variable "enable_rancher" {
  description = "Enable Rancher for Kubernetes management"
  type        = bool
  default     = true
}

variable "enable_argocd" {
  description = "Enable ArgoCD for GitOps"
  type        = bool
  default     = true
}
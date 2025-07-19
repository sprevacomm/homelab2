output "storage_class_name" {
  description = "Name of the created storage class"
  value       = kubernetes_storage_class.local_path.metadata[0].name
}

output "namespace" {
  description = "Namespace where local-path-provisioner is installed"
  value       = kubernetes_namespace.local_path_storage.metadata[0].name
}

output "is_default" {
  description = "Whether this is the default storage class"
  value       = var.is_default_class
}
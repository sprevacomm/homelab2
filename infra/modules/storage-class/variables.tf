variable "storage_class_name" {
  description = "Name of the storage class"
  type        = string
  default     = "local-path"
}

variable "is_default_class" {
  description = "Whether this should be the default storage class"
  type        = bool
  default     = true
}

variable "local_path_provisioner_version" {
  description = "Version of local-path-provisioner to install"
  type        = string
  default     = "0.0.28"
}
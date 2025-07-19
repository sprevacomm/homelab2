# Storage Class - Foundation for all persistent storage
module "storage_class" {
  source = "./modules/storage-class"
  
  storage_class_name             = "local-path"
  is_default_class              = true
  local_path_provisioner_version = "0.0.28"
}
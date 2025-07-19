# Storage Class Module

This module deploys the Rancher Local Path Provisioner to provide dynamic persistent volume provisioning using local storage on Kubernetes nodes.

## Features

- Deploys local-path-provisioner
- Creates a default storage class
- Configures automatic volume provisioning
- Supports volume expansion

## Usage

```hcl
module "storage_class" {
  source = "./modules/storage-class"
  
  storage_class_name             = "local-path"
  is_default_class              = true
  local_path_provisioner_version = "0.0.28"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| storage_class_name | Name of the storage class | string | "local-path" | no |
| is_default_class | Whether this should be the default storage class | bool | true | no |
| local_path_provisioner_version | Version of local-path-provisioner to install | string | "0.0.28" | no |

## Outputs

| Name | Description |
|------|-------------|
| storage_class_name | Name of the created storage class |
| namespace | Namespace where local-path-provisioner is installed |
| is_default | Whether this is the default storage class |

## Storage Location

By default, volumes are created at `/opt/local-path-provisioner` on each node. Ensure this directory exists and has appropriate permissions on all nodes.
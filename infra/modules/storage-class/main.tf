# Deploy local-path-provisioner using Helm
# There's no official Helm chart, so we'll create the resources directly

resource "kubernetes_namespace" "local_path_storage" {
  metadata {
    name = "local-path-storage"
  }
}

resource "kubernetes_service_account" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner-service-account"
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "local_path_provisioner" {
  metadata {
    name = "local-path-provisioner-role"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "persistentvolumeclaims", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["endpoints", "persistentvolumes", "pods"]
    verbs      = ["*"]
  }

  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "local_path_provisioner" {
  metadata {
    name = "local-path-provisioner-bind"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.local_path_provisioner.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.local_path_provisioner.metadata[0].name
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }
}

resource "kubernetes_deployment" "local_path_provisioner" {
  metadata {
    name      = "local-path-provisioner"
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "local-path-provisioner"
      }
    }

    template {
      metadata {
        labels = {
          app = "local-path-provisioner"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.local_path_provisioner.metadata[0].name

        container {
          name  = "local-path-provisioner"
          image = "rancher/local-path-provisioner:v${var.local_path_provisioner_version}"

          command = [
            "local-path-provisioner",
            "--debug",
            "start",
            "--config",
            "/etc/config/config.json"
          ]

          volume_mount {
            name       = "config-volume"
            mount_path = "/etc/config/"
          }

          env {
            name = "POD_NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
        }

        volume {
          name = "config-volume"
          config_map {
            name = kubernetes_config_map.local_path_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_storage_class" "local_path" {
  metadata {
    name = var.storage_class_name
    annotations = var.is_default_class ? {
      "storageclass.kubernetes.io/is-default-class" = "true"
    } : {}
  }

  storage_provisioner    = "rancher.io/local-path"
  reclaim_policy        = "Delete"
  volume_binding_mode   = "WaitForFirstConsumer"
  allow_volume_expansion = true
}

resource "kubernetes_config_map" "local_path_config" {
  metadata {
    name      = "local-path-config"
    namespace = kubernetes_namespace.local_path_storage.metadata[0].name
  }

  data = {
    "config.json" = jsonencode({
      nodePathMap = [
        {
          node  = "DEFAULT_PATH_FOR_NON_LISTED_NODES"
          paths = ["/opt/local-path-provisioner"]
        }
      ]
      sharedFileSystemPath = ""
    })
    "setup" = <<-EOT
      #!/bin/sh
      set -eu
      mkdir -m 0777 -p "$VOL_DIR"
    EOT
    "teardown" = <<-EOT
      #!/bin/sh
      set -eu
      rm -rf "$VOL_DIR"
    EOT
    "helperPod.yaml" = <<-EOT
      apiVersion: v1
      kind: Pod
      metadata:
        name: helper-pod
      spec:
        containers:
        - name: helper-pod
          image: busybox
    EOT
  }
}
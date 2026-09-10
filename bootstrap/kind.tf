resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = "kindest/node:v1.31.0"
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    dynamic "node" {
      for_each = var.nodes
      content {
        role = node.value.role
      }
    }
  }
}

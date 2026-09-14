resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true

  # This ensures we don't try to install ArgoCD until the kind cluster is fully up
  depends_on = [kind_cluster.this]

  # Service + get rid of excessive controllers to improve MEM footprint
  set = [
    {
      name  = "server.service.type"
      value = "ClusterIP"
    },
    {
      name  = "dex.enabled"
      value = "false"
    },
    {
      name  = "notifications.enabled"
      value = "false"
    },
    {
      name  = "applicationSet.enabled"
      value = "false"
    },
    {
      name  = "configs.cm.application.resourceTrackingMethod"
      value = "annotation"
    },
    {
      name  = "server.extraArgs[0]"
      value = "--insecure"
    }
  ]
}
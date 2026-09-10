resource "kubectl_manifest" "argocd_root_app" {
  # This guarantees the Application CRD is installed before we try to create an Application
  depends_on = [helm_release.argocd]

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root-manifests
      namespace: ${var.argocd_namespace}
    spec:
      project: default
      source:
        repoURL: ${var.git_repo_url}
        targetRevision: ${var.git_target_revision}
        path: ${var.git_path}
        directory:
          recurse: true
      destination:
        server: https://kubernetes.default.svc
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  YAML
}

resource "kubectl_manifest" "root_crds" {
  depends_on = [helm_release.argocd]

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root-crds
      namespace: ${var.argocd_namespace}
    spec:
      project: default
      source:
        repoURL: ${var.git_repo_url}
        targetRevision: ${var.git_target_revision}
        path: manifests/crds
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

resource "kubectl_manifest" "root_apps" {
  depends_on = [kubectl_manifest.root_crds]

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root-apps
      namespace: ${var.argocd_namespace}
    spec:
      project: default
      source:
        repoURL: ${var.git_repo_url}
        targetRevision: ${var.git_target_revision}
        path: manifests/apps
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

resource "kubectl_manifest" "root_resources" {
  depends_on = [kubectl_manifest.root_apps]

  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: root-resources
      namespace: ${var.argocd_namespace}
    spec:
      project: default
      source:
        repoURL: ${var.git_repo_url}
        targetRevision: ${var.git_target_revision}
        path: manifests/app-resources
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

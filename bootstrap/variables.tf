variable "cluster_name" {
  type        = string
  description = "The name of the kind cluster"
  default     = "ai-harness"
}

variable "nodes" {
  type = list(object({
    role = string
  }))
  description = "The nodes to configure in the kind cluster"
  default = [
    {
      role = "control-plane"
    }
  ]
}

variable "argocd_namespace" {
  type        = string
  description = "The namespace where Argo CD will be installed"
  default     = "argocd"
}

variable "argocd_chart_version" {
  type        = string
  description = "The version of the Argo CD Helm chart"
  default     = "6.7.11"
}

variable "git_repo_url" {
  type        = string
  description = "The URL of the Git repository containing the manifests"
  default     = "https://github.com/replace-me/ai-harness.git"
}

variable "git_target_revision" {
  type        = string
  description = "The Git branch, tag, or commit to sync"
  default     = "main"
}

variable "git_path" {
  type        = string
  description = "The path within the Git repository to sync"
  default     = "manifests"
}

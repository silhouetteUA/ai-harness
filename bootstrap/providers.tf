terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "kind-ai-harness"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "kind-ai-harness"
}

provider "kubectl" {
  config_path      = "~/.kube/config"
  config_context   = "kind-ai-harness"
  load_config_file = true
}

# CODEBASE.md

Ground truth for the ai-harness repository. Covers architecture, component roles, conventions, and forbidden patterns.

---

## What this repo is

ai-harness is a **local AI infrastructure sandbox**. A single `make deploy` provisions a KinD cluster and reconciles a full AI stack via Argo CD GitOps. There is no application code — the repo is entirely Kubernetes manifests, OpenTofu, and shell scripts.

---

## Tech Stack

| Layer | Tech | Version |
|---|---|---|
| Cluster | KinD | v1.31.0 |
| GitOps operator | Argo CD | latest (Helm) |
| Infrastructure as code | OpenTofu | v1.8+ |
| AI gateway | agentgateway | v1.5.0 |
| Agent runtime | kagent | 0.10.1 |
| Gateway API | gateway-api (standard channel) | v1.2+ |
| Vector database | qdrant | 1.19.1 |
| LLM observability | Arize Phoenix | 12.0.10 |
| Artifact store | OCI Registries (ghcr.io, cr.agentgateway.dev) | — |

---

## Architecture

### Bootstrap flow

A single `make deploy` produces a running cluster:

```
make deploy
  → tofu apply (bootstrap/)
      → KinD cluster (using kindest/node:v1.31.0 for ValidatingAdmissionPolicy support)
      → helm_release.argocd
      → kubectl_manifest.root_crds (depends_on ArgoCD)
      → kubectl_manifest.root_apps (depends_on root_crds)
      → kubectl_manifest.root_resources (depends_on root_apps)
```

The bootstrap enforces a strict sequence using OpenTofu `depends_on` and Argo CD isolated directories to prevent dry-run failures on missing CRDs.

### GitOps via Argo CD

Argo CD tracks this Git repository. OpenTofu provisions three Root Applications that point to three different directories:

1. **`root-crds`** — `path: manifests/crds` — installs CRD Applications.
2. **`root-apps`** — `path: manifests/apps` — installs Helm-based Applications.
3. **`root-resources`** — `path: manifests/app-resources` — installs raw Custom Resources (Gateway, HTTPRoute).

This directory separation is non-negotiable. If raw Custom Resources are placed in the same directory as the CRD applications, Argo CD's directory generator will fail the dry-run validation because the CRD won't exist at plan time.

### Directory layout

```
bootstrap/           OpenTofu: kind.tf, argocd.tf, argocd_apps.tf, variables.tf
manifests/
  crds/              Argo CD Applications for CRDs
    gateway-api-crds.yaml
    agentgateway-crds.yaml
    kagent-crds.yaml
  apps/              Argo CD Applications for Helm charts
    agentgateway.yaml
    kagent.yaml
    phoenix.yaml
    qdrant.yaml
    agentregistry.yaml
    cluster-resources.yaml
  app-resources/     Raw Custom Resources
    agentgateway-resources.yaml  (Gateway)
    kagent-resources.yaml        (HTTPRoute + ReferenceGrant)
scripts/
  createKind.sh           Installs Kind
  installOpenTofu.sh      Installs OpenTofu
  checkPrerequisites.sh   Verifies tools exist
Makefile
GEMINI.md            Project rules for AI agents
```

### Component roles

| Component | Namespace | What it does |
|---|---|---|
| agentgateway | `agentgateway-system` | Gateway API controller; handles AI/MCP-aware routing |
| Gateway `agentgateway-external` | `agentgateway-system` | Single ingress point, port 80, allows routes from all namespaces |
| kagent | `kagent` | AI agent runtime; exposes MCP server on `:8083`, UI on `:8080` |
| HTTPRoute `kagent` | `kagent` | Routes `/api` → kagent MCP, `/` → kagent UI |
| ReferenceGrant `kagent` | `kagent` | Allows the HTTPRoute to reference the gateway in a different namespace |

---

## Conventions

### Adding a new component

1. **CRD Applications go in `manifests/crds/`**. Use `ServerSideApply=true` in `syncOptions`.
2. **App Applications go in `manifests/apps/`**. 
3. **Raw Custom Resources go in `manifests/app-resources/`**.
4. **Cross-namespace routing** — always add a ReferenceGrant in the app's namespace when an HTTPRoute references the gateway.

### Argo CD Optimizations
- **Resource Tracking:** Configured to use `annotation` tracking (`application.resourceTrackingMethod=annotation`) in the Argo CD ConfigMap to avoid the 63-character limit on Kubernetes labels when tracking long CRD names.
- **Server-Side Apply:** Large CRDs (like `agents.kagent.dev`) exceed the 256KB annotation limit. `ServerSideApply=true` is mandatory for CRD Apps.

---

## Forbidden Patterns

| Pattern | Why |
|---|---|
| Raw Custom Resources in `manifests/apps/` or `manifests/crds/` | Causes Argo CD dry-run validation to fail on sync because CRDs do not exist yet. |
| Omission of `ServerSideApply=true` on CRD Applications | Large CRDs will fail to apply due to the 256KB `kubectl.kubernetes.io/last-applied-configuration` limit. |
| KinD nodes < v1.30.0 | Gateway API strictly requires `ValidatingAdmissionPolicy/v1` which is only fully supported in v1.30+. We use v1.31.0. |
| Gateway API Experimental Channel | The `xbackends` CRD contains an alpha CEL rule (`format.dns1123Label`) that crashes cluster upgrades/syncs. Stick to the standard channel. |

---

## Key Design Decisions

**Three Root Applications instead of One** — Argo CD's directory generator merges all files. To solve the CRD chicken-and-egg problem natively, we split the root into `root-crds`, `root-apps`, and `root-resources` and sequence them via OpenTofu `depends_on`.

**`ignoreDifferences` on ValidatingAdmissionPolicy** — Kubernetes mutates default values onto ValidatingAdmissionPolicy and its Binding. We added `ignoreDifferences` to the Gateway API Argo CD Application to prevent infinite out-of-sync flapping.

**Empty Kustomize Blocks** — Do not leave empty `kustomize: {}` blocks in Argo CD Application YAMLs, as the diffing engine will mark them permanently out of sync. Remove the block entirely if unused.

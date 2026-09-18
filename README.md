# AI Harness

> One command. Full AI infrastructure.

`make deploy` gives you a local Kubernetes cluster with everything an AI project needs: an AI-aware API gateway, an agent runtime, vector database, observability, and an eval harness — ready to use.

## What's included

| Component | Role |
|---|---|
| **agentgateway v1.5.0** | AI-aware API gateway (Gateway API–native, MCP-aware) |
| **kagent 0.10.1** | Kubernetes-native AI agent framework |
| **agentregistry** | Inventory and registry for AI agents |
| **Qdrant 1.19.1** | Vector database for retrieval |
| **Arize Phoenix 12.0.10** | LLM observability — tracing, evals, prompt playground |
| **Argo CD** | GitOps operator — keeps the cluster in sync with definitions |
| **KinD** | Local Kubernetes (1 control-plane) running v1.37.0 |

## Quickstart

```bash
make deploy
```

That's it. It checks prerequisites, provisions the KinD cluster, bootstraps Argo CD via OpenTofu, and sets up the root applications. When it finishes:

```bash
kubectl get gateway,httproute -A        # gateway is up
kubectl get applications -n argocd      # check sync status of all apps
kubectl get pods -A                     # verify all components are running
```

## 2. Setting the API Key

Because the cluster is configured to use Gemini via GitOps, the `default-model-config` will look for a Kubernetes Secret containing your API key. If this secret is missing, your agents will be in an unavailable state.

Run the following command to populate the secret (replace `YOUR_API_KEY` with your actual Google AI Studio key, or use an environment variable):

```bash
kubectl create secret generic kagent-gemini \
  --namespace kagent \
  --from-literal=GOOGLE_API_KEY="YOUR_API_KEY"
```

Alternatively, if you have your key saved in a local `.env` file as `GEMINI_API_KEY`, you can run this command. It uses a subshell `()` to securely pull the key without permanently exposing it in your terminal environment:

```bash
(set -a; source .env; kubectl create secret generic kagent-gemini \
  --namespace kagent \
  --from-literal=GOOGLE_API_KEY="$GEMINI_API_KEY")
```

## 3. Usage

After the infrastructure has settled, load up the kagent UI via your local port forward.

```bash
kubectl port-forward -n agentgateway-system svc/agentgateway-external 8081:80
```

To clean everything up, simply run:
```bash
make destroy
```

## How it works

```
make deploy
  → tofu apply (bootstrap/)
      → KinD cluster (v1.37.0)
      → Argo CD (Helm)
      → root-crds (Argo CD Application pointing to manifests/crds/)
      → root-apps (Argo CD Application pointing to manifests/apps/)
      → root-resources (Argo CD Application pointing to manifests/app-resources/)
```

We use a strictly sequenced **App of Apps** pattern. OpenTofu provisions the three root Argo CD Applications sequentially to solve the chicken-and-egg problem:
1. **CRDs** are installed first.
2. **Applications** are installed next.
3. **Raw Custom Resources** (Gateways, HTTPRoutes) are installed last since they rely on the CRDs being present.

## Directory layout

| Path | Purpose |
|---|---|
| `bootstrap/` | OpenTofu: KinD + Argo CD bootstrap and Root Application definitions |
| `manifests/crds/` | Argo CD Applications for deploying CRDs |
| `manifests/apps/` | Argo CD Applications for deploying the Helm charts |
| `manifests/app-resources/` | Raw Custom Resources (Gateway, HTTPRoute, ReferenceGrant) |
| `scripts/` | Shell scripts for installing prerequisites and creating KinD |
| `Makefile` | One-touch `deploy` and `destroy` commands with logging |

## Adding components

1. Put CRD Argo CD Applications in `manifests/crds/`. Ensure they use `ServerSideApply=true`.
2. Put application Argo CD Applications in `manifests/apps/`.
3. Put any raw Custom Resources (like HTTPRoutes) in `manifests/app-resources/`.
4. Commit and push your changes. Argo CD will automatically sync them.

## License

Apache 2.0 — see [LICENSE](./LICENSE).

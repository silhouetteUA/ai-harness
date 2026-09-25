# Plan: Decouple Model and MCP configurations from Agents

This document outlines the step-by-step plan to migrate from tightly coupled `Agent` resources to a Gateway-routed architecture using `agentgateway`. All raw custom resources will be placed in `manifests/app-resources/` to comply with the Argo CD sequence rules.

## Step 1: Create HTTPRoutes for AI Traffic
We will expose dedicated routes on the `agentgateway-external` Gateway. These routes will act as the entry points for our customized AI pipelines.

**File:** `manifests/app-resources/agent-routes.yaml`
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: retrieval-routes
  namespace: agentgateway-system
spec:
  parentRefs:
  - name: agentgateway-external
    namespace: agentgateway-system
  rules:
  # Route 1: Custom implementation (uses qdrant-mcp-custom)
  - matches:
    - path:
        type: PathPrefix
        value: /v1/retrieval/custom
    backendRefs:
    - name: kagent-controller  # Or the upstream LLM backend the gateway proxies to
      namespace: kagent
      port: 8083

  # Route 2: Official implementation (uses qdrant-mcp-official)
  - matches:
    - path:
        type: PathPrefix
        value: /v1/retrieval/official
    backendRefs:
    - name: kagent-controller
      namespace: kagent
      port: 8083
```

## Step 2: Create Agentgateway Policies
We will attach an `AgentgatewayPolicy` to the `HTTPRoute` created above. This policy will dynamically inject the `modelConfig` overrides and MCP servers (`backend.mcp` / `backend.ai`).

**File:** `manifests/app-resources/agent-policies.yaml`
```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: policy-retrieval-custom
  namespace: agentgateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: retrieval-routes
  backend:
    ai:
      defaults:
        # Dynamically inject the model configuration
        - field: "model"
          value: "default-model-config"
    mcp:
      # Inject the MCP tool endpoints that were previously on the Agent
      endpoints:
        - "http://qdrant-mcp-custom.kagent.svc.cluster.local"
        - "http://neo4j-mcp.kagent.svc.cluster.local"
        - "http://k8s-agent.kagent.svc.cluster.local"

---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: policy-retrieval-official
  namespace: agentgateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: retrieval-routes
  backend:
    ai:
      defaults:
        - field: "model"
          value: "default-model-config"
    mcp:
      endpoints:
        - "http://qdrant-mcp-official.kagent.svc.cluster.local"
        - "http://neo4j-mcp.kagent.svc.cluster.local"
        - "http://k8s-agent.kagent.svc.cluster.local"
```
*(Note: The exact syntax under `backend.mcp` and `backend.ai` should be adjusted to match the specific version of your `agentgateway.dev/v1alpha1` CRD implementation).*

## Step 3: Refactor the Agent Manifests
Strip the `modelConfig` and `tools` array from the `Agent` custom resources. 

**File:** `manifests/app-resources/agent-retrieval.yaml`
```yaml
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: retrieval-agent-custom
  namespace: kagent
spec:
  type: Declarative
  description: Ingests and retrieves data across a vector store and a graph.
  declarative:
    stream: true
    # Point the agent to the Gateway API route instead of hardcoding models/tools
    baseUrl: "http://agentgateway-external.agentgateway-system.svc.cluster.local/v1/retrieval/custom"
    systemMessage: |
      You are a data agent over two stores in this cluster. Which products
      back them is not your concern and can change; the tools are the contract.
      ... (keep existing systemMessage)
      
---
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: retrieval-agent-official
  namespace: kagent
spec:
  type: Declarative
  description: Ingests and retrieves data across a vector store and a graph.
  declarative:
    stream: true
    # Point the agent to the alternative Gateway API route
    baseUrl: "http://agentgateway-external.agentgateway-system.svc.cluster.local/v1/retrieval/official"
    systemMessage: |
      You are a data agent over two stores in this cluster. Which products
      back them is not your concern and can change; the tools are the contract.
      ... (keep existing systemMessage)
```

## Step 4: Apply and Verify via GitOps
Because we placed all resources in `manifests/app-resources/`, Argo CD's `root-resources` application will automatically pick them up during its next sync loop without causing dry-run CRD failures.

1. Commit the changes.
2. Wait for Argo CD to sync.
3. Observe the `agentgateway` routing logs to verify that requests to `/v1/retrieval/*` are successfully injecting the MCP tools and LLM config before hitting the backend.

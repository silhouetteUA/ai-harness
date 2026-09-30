# The LLM Router (Triage) Pattern

This document describes how to implement a cost-efficient "Triage" or "LLM Router" pattern using `kagent` and `agentgateway`.

## The Concept

Instead of sending every request to an expensive model like Claude Sonnet 4.6 (Thinking), you can place the cheapest, fastest model in front. This "Router Agent" analyzes the user's prompt and decides which worker agent should actually perform the task based on complexity.

### The Pricing Tiers (Cheapest to Most Expensive)
1. **Router Agent**: Powered by **Gemini 3.8 Flash**. Historically and currently, Gemini's Flash tier is significantly cheaper per million tokens than Claude Haiku. Because of this rock-bottom pricing and blazing speed, it serves as the perfect Router to evaluate task complexity.
2. **Easy Coder**: Powered by **Claude Haiku 4.6**. Slightly more expensive than Flash but highly capable for code. It handles easy syntax fixes and quick script modifications.
3. **Complex Coder**: Powered by **Claude Sonnet 4.6 (Thinking)**. The most expensive and capable model. It handles complex system design, multi-file refactoring, and difficult debugging tasks.

## 1. Gateway Backends & Authentication

First, we define the backends. The Gateway needs to know how to authenticate with Google (for Gemini) and Anthropic (for Claude).

```yaml
---
# Pre-requisite: create these secrets in agentgateway-system
# kubectl create secret generic google-secret -n agentgateway-system --from-literal=GOOGLE_API_KEY="your-key"
# kubectl create secret generic anthropic-secret -n agentgateway-system --from-literal=ANTHROPIC_API_KEY="your-key"
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: anthropic-backend
  namespace: agentgateway-system
spec:
  ai:
    provider:
      anthropic: {}
  policies:
    auth:
      secretRef:
        name: anthropic-secret
      location:
        header:
          name: x-api-key
```

*(Note: The `gemini-backend` for Gemini 3.8 Flash is assumed to already be deployed in your cluster via previous setup).*

## 2. Gateway Routes & Policies

Next, we create the paths the agents will send their OpenAI-formatted traffic to, and the policies that inject the exact 2026 model strings into the payloads.

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: triage-routes
  namespace: agentgateway-system
spec:
  parentRefs:
  - name: agentgateway-external
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v1/triage/router
    backendRefs:
    - name: gemini-backend
      group: agentgateway.dev
      kind: AgentgatewayBackend
  - matches:
    - path:
        type: PathPrefix
        value: /v1/triage/easy
    backendRefs:
    - name: anthropic-backend
      group: agentgateway.dev
      kind: AgentgatewayBackend
  - matches:
    - path:
        type: PathPrefix
        value: /v1/triage/complex
    backendRefs:
    - name: anthropic-backend
      group: agentgateway.dev
      kind: AgentgatewayBackend
---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: policy-triage-router
  namespace: agentgateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: triage-routes
  backend:
    ai:
      defaults:
        - field: "model"
          value: "gemini-3.8-flash"
---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: policy-triage-easy
  namespace: agentgateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: triage-routes
  backend:
    ai:
      defaults:
        - field: "model"
          value: "claude-4-6-haiku"
---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: policy-triage-complex
  namespace: agentgateway-system
spec:
  targetRefs:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    name: triage-routes
  backend:
    ai:
      defaults:
        - field: "model"
          value: "claude-4-6-sonnet-thinking"
```

## 3. Kagent ModelConfigs

Now we configure the dummy `ModelConfigs` so our Kubernetes agents know where to send their traffic.

```yaml
---
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: triage-router-model
  namespace: kagent
spec:
  provider: OpenAI
  model: "dummy-model"
  openAI:
    baseUrl: "http://agentgateway-external.agentgateway-system.svc.cluster.local/v1/triage/router"
  apiKeyPassthrough: true
---
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: triage-easy-model
  namespace: kagent
spec:
  provider: OpenAI
  model: "dummy-model"
  openAI:
    baseUrl: "http://agentgateway-external.agentgateway-system.svc.cluster.local/v1/triage/easy"
  apiKeyPassthrough: true
---
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: triage-complex-model
  namespace: kagent
spec:
  provider: OpenAI
  model: "dummy-model"
  openAI:
    baseUrl: "http://agentgateway-external.agentgateway-system.svc.cluster.local/v1/triage/complex"
  apiKeyPassthrough: true
```

## 4. SandboxAgents (The AI Logic)

Finally, we define the three distinct agents. The `router-agent` acts as the supervisor, using the cheap Gemini 3.8 Flash model to delegate work downstream.

```yaml
---
apiVersion: kagent.dev/v1alpha2
kind: SandboxAgent
metadata:
  name: easy-coder
  namespace: kagent
spec:
  declarative:
    modelConfig:
      name: triage-easy-model
    systemPrompt: >
      You are a fast coding agent. You handle simple syntax errors,
      quick script fixes, and basic refactoring. Provide the code directly.
---
apiVersion: kagent.dev/v1alpha2
kind: SandboxAgent
metadata:
  name: complex-coder
  namespace: kagent
spec:
  declarative:
    modelConfig:
      name: triage-complex-model
    systemPrompt: >
      You are an expert, senior software architect. You handle complex system
      design, multi-file refactoring, and difficult debugging tasks.
---
apiVersion: kagent.dev/v1alpha2
kind: SandboxAgent
metadata:
  name: router-agent
  namespace: kagent
spec:
  declarative:
    modelConfig:
      name: triage-router-model
    systemPrompt: >
      You are a routing supervisor. Analyze the user's coding request.
      If it requires simple syntax fixing, delegate to the 'easy-coder' agent.
      If it requires complex architecture design or spans multiple files, delegate it to the 'complex-coder' agent.
      Return their answer exactly.
    tools:
      - type: Agent
        agent:
          name: easy-coder
      - type: Agent
        agent:
          name: complex-coder
```

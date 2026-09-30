# The LLM Router (Triage) Pattern

This document describes how to implement a cost-efficient "Triage" or "LLM Router" pattern using `kagent` and `agentgateway`.

## The Concept

Instead of sending every request to an expensive model like Claude 3.5 Sonnet, you can place a fast, cheap model (like Gemini Flash) in front. This "Router Agent" analyzes the user's prompt and decides which worker agent should actually perform the task.

- **Router Agent**: Powered by Gemini Flash. Fast, cheap. Evaluates complexity.
- **Haiku Coder**: Powered by Claude Haiku. Handles easy syntax fixes.
- **Sonnet Coder**: Powered by Claude Sonnet. Handles complex architecture.

## 1. Gateway Backends & Authentication

First, we need to define the backends that the Gateway will translate traffic to. We assume you already have a `gemini-backend` for the router. We will create an `anthropic-backend` for the workers.

```yaml
---
# Pre-requisite: create this secret in agentgateway-system
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

## 2. Gateway Routes & Policies

Next, we create the paths the agents will send their OpenAI-formatted traffic to, and the policies that intercept that traffic to enforce the actual model names.

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
        value: /v1/triage/haiku
    backendRefs:
    - name: anthropic-backend
      group: agentgateway.dev
      kind: AgentgatewayBackend
  - matches:
    - path:
        type: PathPrefix
        value: /v1/triage/sonnet
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
          value: "gemini-1.5-flash"
---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: policy-triage-haiku
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
          value: "claude-3-haiku-20240307"
---
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: policy-triage-sonnet
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
          value: "claude-3-5-sonnet-20241022"
```

## 3. Kagent ModelConfigs

Now we configure the `ModelConfigs` so our Kubernetes agents know where to send traffic.

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
  name: triage-haiku-model
  namespace: kagent
spec:
  provider: OpenAI
  model: "dummy-model"
  openAI:
    baseUrl: "http://agentgateway-external.agentgateway-system.svc.cluster.local/v1/triage/haiku"
  apiKeyPassthrough: true
---
apiVersion: kagent.dev/v1alpha2
kind: ModelConfig
metadata:
  name: triage-sonnet-model
  namespace: kagent
spec:
  provider: OpenAI
  model: "dummy-model"
  openAI:
    baseUrl: "http://agentgateway-external.agentgateway-system.svc.cluster.local/v1/triage/sonnet"
  apiKeyPassthrough: true
```

## 4. SandboxAgents (The AI Logic)

Finally, we define the three agents. The most important is the `router-agent`, which is configured with `type: Agent` tools to delegate work.

```yaml
---
apiVersion: kagent.dev/v1alpha2
kind: SandboxAgent
metadata:
  name: haiku-coder
  namespace: kagent
spec:
  declarative:
    modelConfig:
      name: triage-haiku-model
    systemPrompt: >
      You are a fast coding agent. You handle simple syntax errors,
      quick script fixes, and basic refactoring. Provide the code directly.
---
apiVersion: kagent.dev/v1alpha2
kind: SandboxAgent
metadata:
  name: sonnet-coder
  namespace: kagent
spec:
  declarative:
    modelConfig:
      name: triage-sonnet-model
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
      If it requires simple syntax fixing, delegate to the 'haiku-coder' agent.
      If it requires complex architecture design or spans multiple files, delegate it to the 'sonnet-coder' agent.
      Return their answer exactly.
    tools:
      - type: Agent
        agent:
          name: haiku-coder
      - type: Agent
        agent:
          name: sonnet-coder
```

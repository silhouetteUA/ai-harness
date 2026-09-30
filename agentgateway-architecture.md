# Agentgateway Decoupled Architecture

This diagram illustrates how the `k8s-agent` and retrieval agents are decoupled from their underlying models and tools using the Agentgateway architecture.

```mermaid
flowchart TD
    %% Define styles
    classDef agent fill:#e1f5fe,stroke:#0288d1,stroke-width:2px,color:#000
    classDef config fill:#fff3e0,stroke:#f57c00,stroke-width:2px,color:#000
    classDef gateway fill:#e8f5e9,stroke:#388e3c,stroke-width:2px,color:#000
    classDef policy fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px,color:#000
    classDef external fill:#eceff1,stroke:#455a64,stroke-width:2px,color:#000
    classDef tool fill:#ffebee,stroke:#d32f2f,stroke-width:2px,color:#000

    %% Agents
    subgraph "Agents (Kagent)"
        K8sAgent["SandboxAgent<br>(k8s-agent)"]:::agent
        RetrievalAgent["SandboxAgent<br>(retrieval-agent)"]:::agent
    end

    %% Routing Configs (OpenAI interface)
    subgraph "Routing Configuration"
        GatewayModelK8s["ModelConfig (OpenAI)<br>gateway-model-k8s<br>baseUrl: /v1/k8s"]:::config
        GatewayModelRetrieval["ModelConfig (OpenAI)<br>gateway-model-*<br>baseUrl: /v1/retrieval/*"]:::config
    end

    %% Gateway Layer
    subgraph "Agentgateway System"
        Gateway["Gateway<br>(agentgateway-external)"]:::gateway
        
        K8sRoute["HTTPRoute<br>(k8s-agent-routes)"]:::gateway
        RetrievalRoute["HTTPRoute<br>(retrieval-routes)"]:::gateway
        
        K8sPolicy["AgentgatewayPolicy<br>(policy-k8s-agent)<br>+ model: default-model-config"]:::policy
        RetrievalPolicy["AgentgatewayPolicy<br>(policy-retrieval-*)<br>+ model: default-model-config"]:::policy
    end

    %% True Backend Configs
    subgraph "Actual Providers & Tools"
        DefaultModel["ModelConfig (Gemini)<br>default-model-config"]:::config
        GoogleAPI["Google APIs<br>(Gemini Model)"]:::external
        
        K8sToolServer["MCPServer<br>kagent-tool-server"]:::tool
        RetrievalTools["MCPServers & Delegates<br>qdrant-mcp / neo4j-mcp<br>k8s-agent"]:::tool
    end

    %% Connections
    K8sAgent -- "spec.declarative.modelConfig" --> GatewayModelK8s
    RetrievalAgent -- "spec.declarative.modelConfig" --> GatewayModelRetrieval
    
    K8sAgent -- "spec.declarative.tools" --> K8sToolServer
    RetrievalAgent -- "spec.declarative.tools" --> RetrievalTools

    GatewayModelK8s -- "OpenAI Request" --> K8sRoute
    GatewayModelRetrieval -- "OpenAI Request" --> RetrievalRoute

    K8sRoute -- "Attached To" --> Gateway
    RetrievalRoute -- "Attached To" --> Gateway
    
    K8sPolicy -. "Injects Settings" .-> K8sRoute
    RetrievalPolicy -. "Injects Settings" .-> RetrievalRoute

    Gateway -- "Resolves & Translates" --> DefaultModel
    Gateway -- "Gemini Request" --> GoogleAPI
```

## How It Works

1. **The Dummy Provider**: The `SandboxAgent` is configured to use a `ModelConfig` that acts like an OpenAI provider (e.g., `gateway-model-k8s`). 
2. **The Route**: Instead of going to OpenAI, this config's `baseUrl` forces the traffic to hit a specific path on your cluster's `Agentgateway` (e.g., `/v1/k8s`).
3. **The Policy Injection**: Once the request hits the matching `HTTPRoute`, the attached `AgentgatewayPolicy` intercepts the traffic. It dynamically injects the *real* model configuration (`default-model-config`).
4. **The Translation**: The Gateway processes the OpenAI-formatted request, identifies that `default-model-config` uses Gemini, translates the payload into Google's format, and sends it out to the external Gemini API.
5. **Tool Execution**: Tool execution remains natively bound to the `SandboxAgent` through its `spec.declarative.tools` array, allowing the Agent runtime to securely execute LLM tool calls against internal MCP servers.

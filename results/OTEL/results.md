# GenAI Observability Comparison

This document evaluates and compares three observability (o11y) solutions from the perspective of Generative AI (Agents, RAG, and LLM orchestration).

## Comparison Matrix

| Feature / Criteria | Standard OpenTelemetry (e.g., Jaeger) | MLflow | Arize Phoenix |
| :--- | :--- | :--- | :--- |
| **Primary Focus** | General microservices telemetry and distributed tracing. | MLOps, model lifecycle tracking, and experimentation. | Dedicated GenAI and LLM Observability built on OpenInference. |
| **Trace Visualization** | Generic spans and attributes. Hard to read long conversational chains or complex agent loops natively. | Linear trace views (MLflow Tracing) for Python frameworks (LangChain, etc.). | Purpose-built UI for LLMs. Distinct visual hierarchy for `AGENT`, `CHAIN`, `TOOL`, and `LLM` spans. |
| **Setup & Instrumentation** | Requires manually mapping GenAI concepts to standard spans/events. | Auto-instrumentation available for Python ML frameworks. | Standard OTLP ingest using OpenInference semantic conventions. Works out-of-the-box with Go/Python ADKs. |
| **Message/Payload Capture** | Must be explicitly configured. Long prompts often hit string length limits in standard backends. | Captured and versioned within MLflow tracking servers. | Captures full prompts, responses, and tool arguments (configurable via `SPAN_AND_EVENT`). |
| **Evaluations** | None natively. Just raw telemetry. | Offline batch evaluation (`mlflow.evaluate`). | Deeply integrated online/offline LLM-as-a-judge (Hallucinations, QA correctness). |
| **Prompt Engineering** | None. | Dedicated Prompt Engineering UI to compare models and templates. | "Prompt Playground" allows clicking a failed trace and re-running it instantly with a modified prompt. |
| **RAG & Vector Analysis** | No native support for vector mathematics. | Tracks RAG artifacts and retrieval metrics. | Advanced 3D UMAP visualizations to plot vector clusters and debug retrieval logic. |
| **Token & Cost Tracking** | Requires custom metrics/attributes. | Supported in trace views. | Native aggregation of token usage and inference costs across deep agentic loops. |

## Detailed Analysis

### Arize Phoenix

- **Pros:** Extremely fast to debug agent loops. The visual distinction between an agent's "thought process", its tool execution, and its LLM calls makes it uniquely suited for autonomous agents.
- **Cons:** Strictly focused on LLMs. Might require running alongside a traditional OTel backend if you also need deep infrastructure metrics (CPU/RAM/Disk).
- **Findings:** Successfully received OTLP traces from `kagent` (Go ADK). We learned that capturing the actual conversational content requires strictly adhering to the latest OpenTelemetry conventions by configuring `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=SPAN_AND_EVENT` in the agent framework.

### MLflow

- **Pros:** A mature ecosystem that unifies trace logging with model registry and prompt engineering. If using native Python frameworks (like LangChain) or formatting traces in MLflow's proprietary schema, the UI is excellent.
- **Cons:** Traces using the new bleeding-edge OpenTelemetry GenAI Semantic Conventions (like KAgent's Go ADK) are not currently rendered as a pretty "chat interface" natively. They appear as a raw span tree with complex attributes (`gen_ai.operation.name`, `gcp.vertex.agent.tool_call_args`).
- **Findings:** Successfully routed `kagent` telemetry to MLflow via an intermediate OpenTelemetry Collector. However, as a first-time user analyzing agent execution, **Phoenix looks much better**. MLflow buries critical information deep inside the right-hand attributes sidebar rather than presenting a native chat UI. For example, tool executions just appear as raw tags:
  ```json
  "gen_ai.operation.name": "execute_tool"
  "gen_ai.tool.name": "k8s_get_resources"
  "gcp.vertex.agent.tool_call_args": {"all_namespaces":"true","resource_type":"modelconfigs"}
  "gcp.vertex.agent.tool_response": {"output":"NAMESPACE NAME PROVIDER MODEL kagent default-model-config Gemini gemini-3.5-flash-lite"}
  ```

### Standard OpenTelemetry (Jaeger/Zipkin)

- **Pros:** Excellent for tracing requests across distributed architectures, tracking internal IPC/RPC calls between agent microservices, and debugging deep latency bottlenecks. Supported universally by every language and framework.
- **Cons:** Generic visualization. It treats GenAI components (like LLMs, tools, and vector DBs) identically to standard HTTP or database calls, lacking a conversational interface.
- **Findings:** Successfully deployed the OTel Demo stack and Jaeger backend to collect traces from `kagent`. The generic trace graph clearly demonstrated its strength in distributed microservice architectures—showing the flow from the `kagent-controller` API Gateway, across internal `a2a` endpoints, and into the `k8s-agent` worker.
However, for GenAI-specific debugging, it proved very cumbersome:
  - **Conversational Content is Buried:** Original prompts and final responses were extremely difficult to locate. We found the agent's internal clarifications buried inside a span called `execute_tool ask_user`, hidden in raw JSON text within the `gcp.vertex.agent.tool_call_args` attribute. 
  - **No LLM Abstractions:** Because Jaeger does not natively understand GenAI semantics, you must click into individual spans and manually sift through massive walls of JSON attributes to reconstruct a chat.
  - **Conclusion:** While Jaeger is incredibly powerful for tracking distributed agent-to-agent communication and system latency, it is not optimized for inspecting prompt quality or conversational flows, making purpose-built tools like Phoenix strictly superior for LLM observability.

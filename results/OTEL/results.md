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
*(To be completed)*

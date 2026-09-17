# ADR: Retrieval Quality and Embedding Models Comparison (Nomic vs MiniLM)

## Context
We are evaluating two different embedding architectures for our Agentic Retrieval pipeline. The goal is to compare the official Qdrant MCP server against our custom-built Qdrant MCP server to determine the best default stack for the AI harness.

Both pipelines use `gemini-2.5-flash` as the core reasoning engine, write graph relationships to a shared Neo4j database, but differ in how they embed and store semantic text:

1. **Official Stack (`retrieval-agent-official`)**:
   - **MCP Server**: `qdrant-mcp-official` (Astral `uvx mcp-server-qdrant`)
   - **Embedding Model**: `sentence-transformers/all-MiniLM-L6-v2` (Running in-process via `fastembed`)
   - **Collection**: `official-minilm`

2. **Custom Stack (`retrieval-agent-custom`)**:
   - **MCP Server**: `qdrant-mcp-custom` (Go-based stdio bridge)
   - **Embedding Model**: `nomic-embed-text-v1.5` (Running out-of-process via local `llm-d` / `llama.cpp`)
   - **Collection**: `abox-nomic`

---

## Testing Protocol

### Step 1: Identical Ingestion
To ensure a fair comparison, both agents will receive the exact same natural language instruction. The agents are equipped with the `k8s-agent` as a tool and must autonomously decide to invoke it to fetch the resources before chunking and writing to their respective stores.

**Ingestion Prompt (Send to both agents separately):**
> "Please ingest all yaml manifests from the kagent namespace into your stores."

### Step 2: Retrieval Queries
Once the data is ingested, we will assess the retrieval quality using queries that isolate different retrieval mechanisms (Vector, Graph, and Hybrid).

1. **Vector-Heavy Query (Content Search):**
   > "Find the manifest that configures the default model provider for the cluster and tell me exactly what API key secret it references."
   *Expectation:* The agent should prefer the vector store (`qdrant-find`) to locate the exact YAML content of the `ModelConfig`.

2. **Graph-Heavy Query (Topology & Relationships):**
   > "List all Agents in the cluster that have a dependency on or use the k8s-agent. Explain how they are related."
   *Expectation:* The agent should prefer the graph store (`read-cypher`) because vector search is poor at determining concrete directional references.

3. **Hybrid Query (Content + Topology):**
   > "Find the HTTPRoute that maps traffic to port 8083, and tell me which Gateway it attaches to and what namespace that Gateway lives in."
   *Expectation:* The agent should perform a vector search to find the HTTPRoute defining port 8083, then use Cypher to traverse the `ATTACHED_TO` relationship to identify the Gateway.

---

## Evaluation Methodology (How we rank them)

We will rank the performance of both stacks across four dimensions:

### 1. Semantic Relevance (Embedding Quality)
*Does the model retrieve the correct context?*
* **MiniLM** is smaller and highly optimized for semantic similarity, but may lack domain-specific k8s vocabulary comprehension.
* **Nomic-Embed (v1.5)** has a larger context window (up to 8192) and might capture longer, complex YAML files better than MiniLM.
* *Metric:* Does `qdrant-find` return the exact target manifest in the top results without hallucinating?

### 2. Agentic Routing (Tool Selection Accuracy)
*Does the underlying embedding quality affect how the LLM decides to use tools?*
* While the LLM (`gemini-2.5-flash`) is constant, poor vector retrieval results often trick an agent into falling back to incorrect Cypher queries, or vice-versa. 
* *Metric:* Did the agent pick the correct tool (Vector vs Graph) on the first try based on the system prompt's rules?

### 3. Architecture & Latency
*In-process vs Out-of-process embeddings.*
* **Official MCP**: Calculates embeddings inside the MCP server process (CPU).
* **Custom MCP**: Sends an HTTP request to `llama.cpp` / `llm-d`. 
* *Metric:* Time to complete the initial ingestion of the `kagent` namespace. Does the network hop of the custom MCP add unacceptable latency, or does the dedicated inference pool make it faster?

### 4. Hybrid Synthesis (Completeness)
*Can it put the pieces together?*
* *Metric:* For the Hybrid Query, did the agent successfully map the metadata returned from Qdrant (name/namespace/kind) into a Cypher query to retrieve the connected nodes?

---

## Results & Decision
*(To be populated after test execution)*

- **Ingestion Performance:** [Pending]
- **Retrieval Accuracy (MiniLM):** [Pending]
- **Retrieval Accuracy (Nomic):** [Pending]
- **Winner:** [Pending]

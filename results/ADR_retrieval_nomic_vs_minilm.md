# ADR: Retrieval Quality and Embedding Models Comparison (Nomic vs MiniLM)

## Context
We are evaluating two different embedding architectures for our Agentic Retrieval pipeline. The goal is to compare the official Qdrant MCP server against our custom-built Qdrant MCP server to determine the best default stack for the AI harness.

Both pipelines use `gemini-3.5-flash-lite` as the core reasoning engine, write graph relationships to a shared Neo4j database, but differ in how they embed and store semantic text:

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

## 4. Hybrid Synthesis (Completeness)
*Can it put the pieces together?*
* *Metric:* For the Hybrid Query, did the agent successfully map the metadata returned from Qdrant into a Cypher query?

---

## Results & Findings

### Test 1: Agentic Routing & "Cheating"
During the first query, both agents exhibited **"Tool Temptation"** (negative constraint failure). When asked complex retrieval questions, the LLM (`gemini-3.5-flash-lite`) completely ignored its system prompt instructions to strictly use Qdrant/Neo4j, and instead invoked the `k8s-agent` tool to "cheat" by checking the live cluster. This highlights that lightweight models prioritize certainty and ease of use over strict adherence to negative instructions. 

After explicitly forbidding the `k8s-agent` in the prompt, both models correctly deduced that the specific internal YAML field (API Key Secret Name) was not fully stored in the parsed vector/graph representations, and accurately reported missing data rather than hallucinating.

### Test 2: Graph Accuracy
**Query:** *"List all Agents in the cluster that have a dependency on or use the k8s-agent."*
* Both the **Official (`all-MiniLM-L6-v2`)** and **Custom (`nomic-embed-text-v1.5`)** pipelines successfully completed the task. They both used `get-schema` and `read-cypher` to identify that `retrieval-agent-official` and `retrieval-agent-custom` connect via `USES_TOOL`.

### Test 3: Missing Data Recognition
**Query:** *"Find the HTTPRoute that maps traffic to port 8083..."*
* Both agents correctly determined that `HTTPRoute` resources were never ingested (since the ingestion phase only targeted Deployments, Services, and Agents). All tasks across both architectures were completed successfully without hallucination.

### Iteration 2: The Raw YAML "Kill-Shot"
To validate the architectural limits of the embedding models, we ran a second iteration where both agents were forced to ingest the **raw, unsummarized YAML** of all 12 Deployments in the namespace, followed by complex vector and hybrid queries.

**1. The Context Dilution Trap (Custom Failure)**
The Custom Stack (`nomic-embed`) successfully ingested the massive payloads (storing 12 distinct points), but failed several exact-keyword lookups (e.g., finding the `dnsPolicy` field). Because `nomic` has an 8192-token window, it stored the entire 300-line YAML file as a single vector point. When searching for a specific keyword, the semantic similarity is mathematically diluted ("Needle in a Haystack"), causing the LLM to miss the result.

**2. The Chunking Advantage (Official Success)**
The Official Stack (`MiniLM`) succeeded in the exact-keyword lookups. The `fastembed` library automatically chunks text into small paragraphs before embedding. By chunking the YAML, exact keyword searches hit small chunks with extremely high similarity scores, proving that **chunking is mandatory** even for long-context models.

**3. Hallucination & Instability (Official Failure)**
Despite winning the vector searches, the Official Stack suffered two catastrophic failures:
* **Hallucination:** When asked about a `ModelConfig` secret (which was never ingested), the Official agent hallucinated the correct answer from its chat history. The Custom agent honestly reported the data was missing.
* **Server Crash:** On the final complex hybrid query, the Official MCP Server (`qdrant-mcp-official`) locked up and crashed (`context deadline exceeded`). The in-process Python server could not handle the memory footprint of heavy embedding searches under load.

## Final Decision
**Decision: We will use the Custom Stack (`abox-nomic`).**

Iteration 2 proved that in-process Python AI servers (like the Official FastMCP stack) are unstable in Kubernetes under load. Relying on a custom Go-based MCP bridge that delegates embedding to a dedicated, out-of-process inference pool (`llama.cpp` / `llm-d`) completely isolates our agent framework from memory-intensive AI crashes. 

While the Official stack proved that data chunking is mathematically superior for exact-keyword vector lookups, the Custom stack provides honesty (no hallucinations) and rock-solid stability. We will adopt the Custom Stack, with a future engineering mandate to implement a text-chunking strategy within the Go MCP server before embedding.

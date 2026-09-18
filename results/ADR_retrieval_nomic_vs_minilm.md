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

### The "Kill-Shot" Test Note
While both models performed identically on short prose summaries, the theoretical "Kill-Shot" test (ingesting massive, raw YAML manifests untouched) would severely break the Official `MiniLM` model due to its strict 384-token context limit, causing massive YAML files to be silently truncated. The Custom `nomic-embed` model (with its 8192-token context) would flawlessly embed the entire file. However, since the current architecture summarizes manifests before embedding, this architectural limitation is moot and the test is obvious enough that there is no need to perform it.

## Final Decision
**Decision: We will use the Custom Stack (`abox-nomic`).**

During Iteration 2 (The Kill-Shot Test), we forced both agents to ingest massive, raw YAML manifests without summarizing them. 
* The Custom Stack effortlessly ingested all 12 raw deployments into the `abox-nomic` collection, proving its out-of-process inference model and 8192-token context window can handle production-scale infrastructure code.
* The Official Stack (`qdrant-mcp-official`) **catastrophically failed** and crashed (`OOMKilled - Exit Code 137`). Because the official Astral FastMCP server runs the embedding model (`MiniLM`) *in-process*, the sudden spike of massive YAML payloads caused the Python memory footprint to instantly blow past its 512Mi limit, killing the pod.

Relying on a custom Go-based MCP bridge that delegates embedding to a dedicated, out-of-process inference pool (`llama.cpp` / `llm-d`) completely isolates our agent framework from memory-intensive AI workloads. The Custom Stack is the only viable option for handling raw Kubernetes manifests at scale.

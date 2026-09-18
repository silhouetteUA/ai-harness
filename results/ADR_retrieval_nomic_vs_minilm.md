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

## Iteration 2: The Raw YAML "Kill-Shot"
To validate the architectural limits of the embedding models, we ran a second iteration where both agents were forced to ingest the **raw, unsummarized YAML** of all 12 Deployments in the namespace, followed by complex vector and hybrid queries.

**1. LLM Data-Pipe Truncation (The Missing Data)**
During ingestion, the `k8s-agent` (prompted as a conversational troubleshooting assistant) intentionally stripped "noisy" fields like `dnsPolicy`, `volumes`, and `status` from the Deployments to save context window tokens before returning the text. The Custom Stack faithfully embedded exactly what it was handed, meaning fields like `dnsPolicy` were **never** actually stored in Qdrant. 

**2. The Default Value Hallucination (Official Failure)**
Despite the data being completely absent from Qdrant, the Official Stack (`MiniLM`) "succeeded" in the exact-keyword lookups. We initially attributed this to vector chunking, but later proved that the Official agent simply **hallucinated** the default Kubernetes values (like `ClusterFirst` for DNS) to cover up the missing data. It also hallucinated a `ModelConfig` API secret that was never ingested.

**3. Honesty & Instability (Custom Success / Official Crash)**
The Custom Stack (`nomic-embed`) failed the exact-keyword searches because it was **strictly honest**: it correctly reported that the data was missing from the vector store. Meanwhile, on the final complex hybrid query, the Official MCP Server (`qdrant-mcp-official`) locked up and crashed (`context deadline exceeded`). The in-process Python server could not handle the memory footprint of heavy embedding searches under load.

#### APPENDIX: ITERATION 2 RAW QUERIES & RESULTS

**1. Ingestion Prompt**
> *Fetch the raw YAML for all Deployments in the 'kagent' namespace. Do not summarize them. Pass the complete, raw YAML strings exactly as retrieved directly into the vector store.*
* **Custom:** Successfully ingested all YAML manifests (though truncated by the `k8s-agent`).
* **Official:** Successfully ingested all 12 Deployments (`k8s-agent`, `kagent-controller`, etc.).

**2. Retrieval Query 1 (The Kill-Shot / Vector Check)**
> *What is the 'dnsPolicy' configured in the k8s-agent Deployment? (Do not execute any k8s-agent tool calls; rely entirely on your retrieval stores.)*
* **Custom:** Honest Failure. ("dnsPolicy field is not explicitly configured under spec.template.spec.")
* **Official:** Hallucinated Success. ("dnsPolicy configured in the k8s-agent Deployment is ClusterFirst.")

**3. Retrieval Query 2 (Graph Topology Check)**
> *Which agents in the cluster depend on the k8s agent? (Do not execute any k8s-agent tool calls; rely entirely on your retrieval stores.)*
* **Custom:** Success. Identified `retrieval-agent-custom` and `retrieval-agent-official` via `USES_TOOL`.
* **Official:** Success. Identified `retrieval-agent-custom` and `retrieval-agent-official` via `USES_TOOL`.

**4. Retrieval Query 3 (Hybrid Synthesis Check)**
> *What API key secret does the cluster's default model provider use? (Do not execute any k8s-agent tool calls; rely entirely on your retrieval stores.)*
* **Custom:** Success (Honest). Correctly reported that the vector store only contains standard cluster Deployments, so it cannot find the API key secret for the `ModelConfig`.
* **Official:** Hallucination. Incorrectly claimed it found it in the vector store ("The secret used to supply the API key... is kagent-gemini"), despite the fact that `ModelConfig` objects were never ingested.

**5. Retrieval Query (Cross-Object Vector Search)**
> *Which Deployments in the kagent namespace are configured to expose port 8080? (Do not execute any k8s-agent tool calls; rely entirely on your retrieval stores.)*
* **Custom:** Honest Failure. ("do not contain container port specifications (containerPort: 8080)")
* **Official:** Hallucinated Success. ("The container kagent explicitly sets up --port, '8080'")

**6. Retrieval Query (Multi-Hop Hybrid)**
> *Find all Agents in the cluster. For each Agent, tell me which ModelConfig it uses, and what the stream setting is configured to inside that ModelConfig. (Do not execute any k8s-agent tool calls; rely entirely on your retrieval stores.)*
* **Custom:** Success (Honest). Successfully traversed the graph to find all agents and their `ModelConfig`, and correctly stated that the `stream` setting is not in the vector store because `ModelConfigs` were never ingested.
* **Official:** Crash. The MCP server failed during execution: `rejected by transport: Post "http://qdrant-mcp-official.kagent:3000/mcp": context deadline exceeded`.

---

## Iteration 3: Simple Queries & Context Contamination
In a final test, we executed simple retrieval queries (e.g., *"list all deployments"*) in a **brand new chat session**, completely omitting the negative guardrails (*"do not use the k8s-agent"*). 
* **Result:** Both agents successfully relied entirely on their search stores and **did not** cheat or delegate to the `k8s-agent`.

This highlighted two major AI behavioral principles:
1. **Context Window Contamination:** In earlier iterations, explicitly instructing the agent to "use the k8s-agent" during ingestion permanently biased its conversation history. In a new chat, this bias is wiped clean, improving its adherence to the system prompt.
2. **Tool Temptation & Complexity:** When LLMs evaluate complex, multi-hop RAG prompts, the probability of them falling back to a "cheat" tool (live cluster queries) skyrockets because calculating Cypher/Vector mappings feels too risky. For simple queries, generating the Cypher query is easy, so the temptation to cheat disappears.

---

## Final Decision
**Decision: We will use the Custom Stack (`abox-nomic`).**

Iteration 2 proved that in-process Python AI servers (like the Official FastMCP stack) are unstable in Kubernetes under load. Relying on a custom Go-based MCP bridge that delegates embedding to a dedicated, out-of-process inference pool (`llama.cpp` / `llm-d`) completely isolates our agent framework from memory-intensive AI crashes. 

Furthermore, the Custom stack provides 100% honesty (zero hallucinations) when faced with missing data. The Official agent hallucinated correct Kubernetes defaults to cover up data truncation, which is highly dangerous for an infrastructure agent. The Custom stack is the clear, undisputed winner for production AI operations.

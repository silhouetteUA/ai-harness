# Changelog

## [Unreleased]

### Added
- **Task 2: Local Embedding Model Selection (ADR & ToDo)**
  - **ADR**: Selected `nomic-embed-text-v1.5` as the local text embedding model. Given the strict limited RAM constraints, `nomic-embed-text-v1.5` (quantized to GGUF format such as Q4_K_M) is the optimal choice. It provides a large context window (8192) and strong performance while requiring minimal memory (often under 200MB of RAM) when run with `llama.cpp` or Ollama.
  - **ToDo (Instructions for Agent)**:
    1. Download the `nomic-embed-text-v1.5.Q4_K_M.gguf` model from HuggingFace (or pull via `ollama run nomic-embed-text`).
    2. If using `llama.cpp`, ensure `llama-server` is compiled and available.
    3. Run the model locally with embedding support enabled: 
       ```bash
       ./llama-server -m nomic-embed-text-v1.5.Q4_K_M.gguf --embedding --port 8080
       ```
    4. Test the model using the `/v1/embeddings` endpoint.

- **Task 3: Cluster Deployment with llmd Sidecar (ADR & ToDo)**
  - **ADR**: For deploying the embedding model in a Kubernetes cluster, we will adopt a sidecar architecture using `llm-d` (a framework for distributed LLM inference). By deploying an `llm-d` routing sidecar alongside our inference pods, we decouple endpoint routing, KV cache management, and stage coordination from the core computation engine. This ensures AI-aware load balancing and efficient resource scaling in a constrained cluster environment.
  - **ToDo (Instructions for Agent)**:
    1. Package the chosen embedding model and the `llama.cpp` server into a container image.
    2. Create a Kubernetes Deployment spec that includes the primary inference container.
    3. Add the `llm-d` sidecar container to the pod specification, sharing the network namespace (`localhost`).
    4. Expose the `llm-d` sidecar port as the primary entrypoint for inference requests.
    5. Follow Argo CD rules: Group custom resources in a separate directory and ensure any CRD installations use `ServerSideApply=true`.

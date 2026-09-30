# Router Agent Evaluations (Evals)

This guide explains how to evaluate your `router-agent`. Because the router's job is purely to classify a prompt and invoke a specific tool (`easy-coder` or `complex-coder`), this is a **Classification Evaluation**. 

Unlike evaluating creative writing (which is subjective), a routing eval is perfectly objective. There is only one correct answer per prompt.

---

## 1. The Eval Dataset

To run an eval, you need a "Golden Dataset"—a list of sample inputs paired with their expected outputs. Below are 40 sample prompts (20 easy, 20 complex) formatted as a CSV.

### `router_eval_dataset.csv`

```csv
prompt,expected_tool
"Fix the missing colon syntax error on line 42 of main.py",easy-coder
"How do I print 'hello world' in Python?",easy-coder
"Rename the variable `x` to `user_id` in this script.",easy-coder
"Add a docstring to the `calculate_total` function.",easy-coder
"Convert this list of strings to lowercase in JavaScript.",easy-coder
"Center this div using CSS flexbox.",easy-coder
"Write a regex to match a standard email address.",easy-coder
"Why is my Python script throwing an IndentationError?",easy-coder
"Format this JSON string to be pretty-printed.",easy-coder
"Sort this array of numbers in descending order.",easy-coder
"Change the background color of the header to blue.",easy-coder
"How do I read a text file line by line in bash?",easy-coder
"Write a SQL query to select all users where age > 18.",easy-coder
"Update the package.json to bump the react version.",easy-coder
"Fix the typo in the console.log statement.",easy-coder
"Add a comment explaining what the loop does.",easy-coder
"How do I get the length of a dictionary in Python?",easy-coder
"Convert this string from snake_case to camelCase.",easy-coder
"Remove the last element from this array.",easy-coder
"Write a basic HTML skeleton with a title.",easy-coder
"Design a highly available microservices architecture for a distributed caching system using Redis and Kubernetes.",complex-coder
"Refactor the entire authentication flow to use OAuth2 and JWT across the React frontend and Go backend.",complex-coder
"Migrate this monolithic Node.js application into three separate Go microservices communicating via gRPC.",complex-coder
"Analyze the race condition in this multi-threaded C++ database engine and propose a lock-free solution.",complex-coder
"Implement a custom Kubernetes Operator in Kubebuilder to manage the lifecycle of a distributed Postgres cluster.",complex-coder
"Design a data pipeline that ingests 100k events per second from Kafka, processes them in Flink, and writes to ClickHouse.",complex-coder
"Refactor the deeply nested callback hell in this legacy application to use modern async/await and robust error handling.",complex-coder
"Architect a multi-tenant SaaS authorization system using OpenFGA with Role-Based and Relationship-Based Access Control.",complex-coder
"Optimize this heavy React application to reduce the First Contentful Paint (FCP) from 4 seconds to under 1 second.",complex-coder
"Write a zero-downtime database migration strategy for splitting the 'users' table into three shard tables across regions.",complex-coder
"Implement a custom load balancer in Rust that uses consistent hashing to route websocket connections.",complex-coder
"Trace and fix the memory leak in this high-throughput Java application that crashes with OutOfMemoryError after 4 hours.",complex-coder
"Design a real-time collaborative text editor backend using WebSockets and Operational Transformation (OT) algorithms.",complex-coder
"Migrate our entire AWS infrastructure deployment from ClickOps into modular, reusable Terraform modules.",complex-coder
"Implement a custom memory allocator in C for a real-time embedded system with strict latency requirements.",complex-coder
"Architect a disaster recovery solution that provides cross-region failover with RPO < 5 minutes and RTO < 15 minutes.",complex-coder
"Refactor this monolithic God-class into adhering to SOLID principles using the Strategy and Factory design patterns.",complex-coder
"Write a custom Webpack plugin that analyzes the AST of the codebase to strip out dead internationalization strings.",complex-coder
"Implement a distributed locking mechanism using Zookeeper to coordinate leader election among 50 worker nodes.",complex-coder
"Build an end-to-end encrypted chat protocol utilizing double-ratchet encryption algorithms.",complex-coder
```

---

## 2. Injecting it into an Eval Framework

To execute these tests against your `router-agent`, you can use an open-source framework like **Promptfoo**, **Ragas**, or a simple **Python script**. 

Because your `router-agent` is exposed through `Agentgateway` as a standard OpenAI endpoint, injecting the dataset is identical to talking to ChatGPT.

Here is an example Python script that loops through the dataset and queries your agent:

```python
import csv
import openai

# Point the client to your Agentgateway Kagent Route
client = openai.OpenAI(
    base_url="http://localhost:8081/v1/k8s", # Your port-forwarded gateway
    api_key="dummy-key" # Kagent doesn't require a real key locally
)

results = []

with open("router_eval_dataset.csv", mode="r") as file:
    reader = csv.DictReader(file)
    for row in reader:
        prompt = row["prompt"]
        expected_tool = row["expected_tool"]
        
        # 1. Send the prompt to the router agent
        response = client.chat.completions.create(
            model="router-agent", # The name of the SandboxAgent
            messages=[{"role": "user", "content": prompt}],
        )
        
        # 2. Extract the tool call the agent made
        actual_tool = None
        if response.choices[0].message.tool_calls:
            actual_tool = response.choices[0].message.tool_calls[0].function.name
            
        results.append({
            "prompt": prompt,
            "expected": expected_tool,
            "actual": actual_tool
        })
```

---

## 3. Scoring the Results

Because routing is a classification task, scoring is an **Exact Match (0 or 1)**. 
- If `actual_tool == expected_tool`, the score is `1`.
- If the router picked the wrong tool (or answered the prompt directly without calling a tool), the score is `0`.

```python
total_samples = len(results)
correct_predictions = 0

for res in results:
    if res["actual"] == res["expected"]:
        correct_predictions += 1
    else:
        print(f"FAILED: '{res['prompt']}' | Expected: {res['expected']}, Got: {res['actual']}")

# Calculate Raw Score
print(f"Raw Score: {correct_predictions} / {total_samples}")
```

---

## 4. Normalizing the Score

In AI Evaluation, scores are almost always normalized to a float between `0.0` and `1.0` (or a percentage from 0% to 100%). This allows you to compare the performance of your router across different datasets of varying sizes.

```python
# Normalization: (Correct Predictions / Total Samples)
normalized_score = correct_predictions / total_samples

print(f"Normalized Accuracy: {normalized_score:.2f}") # e.g., 0.95
print(f"Percentage Accuracy: {normalized_score * 100:.1f}%") # e.g., 95.0%
```

### What to do with the Score?
- **Baseline**: If your score is **95%**, you have a strong baseline.
- **Tweak**: You change the router's `systemPrompt` or upgrade it from `gemini-3.8-flash` to a newer model.
- **Compare**: You re-run the Eval script. If the new normalized score drops to **85%**, you immediately know the prompt change made the router *worse*, and you revert it. This prevents regressions in production!

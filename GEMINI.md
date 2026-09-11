# AI Harness Agent Rules

## 1. Argo CD App of Apps Sequencing
* **Rule:** Never place raw Custom Resources (like `Gateway`, `HTTPRoute`) in the same directory as Argo CD `Application` manifests that install their respective CRDs.
* **Rationale:** Argo CD's directory generator applies all files concurrently. The dry-run validation will fail if a Custom Resource is encountered before its CRD is actually created, halting the entire sync and creating a chicken-and-egg failure.
* **Solution:** Always group raw Custom Resources into a separate directory (e.g., `manifests/app-resources/`) and manage them via a completely separate root Application (e.g., `root-resources`), explicitly ordered via OpenTofu `depends_on`.

## 2. Argo CD Large CRD Limitations
* **Rule:** Always add `ServerSideApply=true` to the `syncOptions` of any Argo CD Application that deploys CRDs.
* **Rationale:** Many modern CRDs frequently exceed the 256KB size limit of the `kubectl.kubernetes.io/last-applied-configuration` annotation used by Argo CD's default client-side apply. Server-Side Apply natively bypasses this limit.
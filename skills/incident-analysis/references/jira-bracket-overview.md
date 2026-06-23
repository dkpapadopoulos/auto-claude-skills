# Jira Bracket Overview

Shared reference for Jira-stage framing and parallel query strategy used by the incident-analysis skill. Later tasks append stage-pointer metadata here.

## Parallel Execution Strategy — Batch Independent Queries (Constraint 13)

When multiple independent queries are needed at the same investigation step, dispatch them in parallel rather than sequentially. Independence means the queries do not depend on each other's results to formulate the filter.

**Mandatory parallel batches:**

| Phase | What to batch | Why |
|-------|---------------|-----|
| Step 1 + Step 2 | Preflight + timezone detection + scope queries | No dependencies between them |
| Step 2b + 2c | Inventory queries + impact quantification | Independent data sources |
| Step 2d | Incident count + baseline count (per error signal) | Same query, different time window |
| Step 3 (intermediary found) | All-container ERROR inventory + deployment history + auth layer errors + HTTP status distribution | Architecture discovery — each query is independent |
| Step 3c (2+ services) | Per-service ERROR log queries (all services in one batch) | Same query template, different service filter |
| Step 3c item 3+4 | Deployment history + runtime signal (per service, all in one batch) | Independent per-service queries |
| Step 5 | Disconfirming query + per-service attribution queries | Independent verification checks |

**Always pair incident + baseline:** Every count or rate query should have a parallel twin for the baseline period (same service, same error class, same time-of-day on a prior day). This adds zero wall-clock time (parallel) and prevents deep-diving into baseline signals (Step 2d gate).

**When NOT to parallelize:** Queries that depend on a prior result to formulate the filter. For example, Step 4 (trace correlation) requires a trace_id from Step 3 exemplars — these must be sequential.

**Anti-pattern:** Sequential single-service discovery through an intermediary (N round-trips) when all services could be discovered in one parallel batch.

# Multi-Service Error Sweep — Parallel Rounds and Inventory Fields

Read at INVESTIGATE Step 3c, before the sweep and before writing `service_error_inventory`; the gate, procedure and layer semantics stay in `SKILL.md`. Moved verbatim from `SKILL.md`.

## Parallel rounds

1. **Architecture discovery batch (one parallel round):** Query all containers in the namespace with ERROR logs grouped by container name + deployment history for the 72h window + auth/identity service errors. This reveals the full service landscape and recent changes in a single round-trip instead of discovering services one at a time.

2. **Per-service sweep batch (one parallel round):** For each service identified in the architecture discovery, dispatch items 1-3 of the procedure below (ERROR logs + error classification + deployment history) as parallel queries. Each query is independent — they target different services with the same query template.

3. **Baseline comparison batch (one parallel round):** For each service's error count from the sweep, query the baseline count from a prior day in parallel. Feed results into the Step 2d baseline-first gate to skip baseline signals before deep-diving.

This pattern collapses an N-service sequential sweep (N round-trips) into 3 parallel rounds regardless of N. The procedure below describes what to query per service; this pattern describes how to batch the execution.

## `service_error_inventory`

```yaml
service_error_inventory:
  - service: "<name>"
    error_class: "<dominant error>"
    tier: 1|2|3
    count_incident: <N>
    count_baseline: <N>
    deployment_in_72h: true|false
    deployment_timestamp: "<UTC or null>"
    investigated: true|false
    infra_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
    infra_evidence: "<what was checked>"
    infra_reason: "<why not assessed, if status != assessed>"
    app_status: "assessed" | "not_applicable" | "unavailable" | "not_captured"
    app_evidence: "<what was checked>"
    app_reason: "<why not assessed, if status != assessed>"
    mechanism_status: "known" | "not_yet_traced" | "not_applicable"
```

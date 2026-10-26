# Multi-Service Error Sweep — `service_error_inventory` Schema

Read at INVESTIGATE Step 3c when writing `service_error_inventory`; the gate, procedure, parallel rounds and layer semantics stay in `SKILL.md`, and the canonical schema is `references/investigation-schema.md`. Moved verbatim from `SKILL.md`.

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

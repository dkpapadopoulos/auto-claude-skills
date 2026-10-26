# Why Three Rules Exist

Read when weighing whether one of these rules applies; each rule stays in `SKILL.md`. Moved verbatim from `SKILL.md`.

## Constraint 10: Dual-Layer Investigation

**Anti-pattern this prevents:** Building a complete, internally-consistent infrastructure narrative (timeouts, resource pressure, GC pauses) while the actual root cause is an application-layer bug (stale cache, template error, retry storm) in a service whose ERROR logs were never queried.

## MITIGATE Step 1: offer the auth fix

**Why this matters:** Tier 2 (gcloud CLI) cannot do `list_time_series` (metrics), `get_trace` (trace correlation), or `list_group_stats` (error reporting). Silently falling back to Tier 2 creates investigation gaps that are expensive to discover later — especially for database metrics, which are often the missing piece in shared-resource incidents. The few seconds to re-authenticate are far cheaper than the gaps.

## MITIGATE Step 2d: Baseline-First Gate

**Why this matters:** Without this gate, the investigation will deep-dive into every error signal regardless of whether it's normal. In one investigation, ~4 query round-trips were spent investigating 403 errors that turned out to be at baseline rate (4,948 vs 5,000) — time wasted that could have been spent on the actual anomaly (JDBC errors: 500 vs 0 baseline).

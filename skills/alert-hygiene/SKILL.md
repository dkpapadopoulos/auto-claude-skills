---
name: alert-hygiene
description: Use when facing flapping alerts, alert fatigue, recurring noisy incidents, threshold audits, or SLO-alert redesign questions for a GCP monitoring project.
---

# Alert Hygiene Analysis

Use when facing alert noise, flapping alerts, alert fatigue, threshold audits, or SLO-alert redesign questions. Analyzes alert policies and incident history for a single GCP monitoring project. Produces an action-class prescriptive report: Do Now items (PR-ready config changes with strict gating), Investigate items (bounded discovery with two-stage DoD), and Needs Decision items (strategy/policy choices with named owners). Runs straight through from data pull to final report.

**When NOT to use:**
- Active incident investigation — use incident-analysis instead (tiered log investigation with mitigation playbooks)
- SLO design from scratch — this skill identifies SLO-redesign *candidates*, it does not design SLOs or generate burn-rate PromQL
- Multi-project analysis — v1 is scoped to one monitoring project per invocation

## Behavioral Constraints

### 1. Scope Restriction

All queries are scoped to one monitoring project per invocation. The user must provide the monitoring project ID before analysis begins. If not provided, ask once.

### 2. Temp-File Execution Pattern

All bulk data operations write to session-scoped temp files via `mktemp`. This keeps large JSON payloads out of conversation context and makes the shell path debuggable:

```bash
WORK_DIR=$(mktemp -d /tmp/ah-XXXXXX)
```

All scripts read from and write to `$WORK_DIR`. Clean up at end of session.

### 3. No Checkpoint Gates

The analysis runs straight through from data pull to final report. The frequency table appears in the report appendix, not as a separate pause point. Do not ask the user for input mid-analysis.

### 4. Confidence Inline Flags

When an inference has less than high confidence (e.g., inferring a nightly batch from time-of-day concentration), state the inference and flag it inline: *"Inferred nightly batch from 100% h02 concentration — verify before applying mute window."* Do not gate the report on user confirmation.

## Confidence Levels and Readiness

Confidence determines evidence quality. Readiness determines action class. An item can be high-confidence but not Do Now-ready if it fails a gate requirement.

| Confidence | Evidence Criteria | Readiness | Action Class |
|------------|------------------|-----------|--------------|
| High | Frequency + metric/structural evidence agree, or structural flaw unambiguous | PR-Ready (all gate requirements met) | Do Now |
| High | Structural/measured evidence strong, but missing gate requirement (IaC location, owner, etc.) | Stage 1 (gate requirement resolution) | Investigate |
| Medium | Frequency pattern only, no metric validation | Stage 1 (hypothesis validation) | Investigate |
| High | Skill cannot determine intent — SLO redesign, ambiguous ownership, policy strategy | Decision Pending | Needs Decision |
| Low | Data insufficient, inference from time-of-day alone, or evidence contradicts | Stage 1 | Investigate (with inline low-confidence flag) |

**Confidence / Readiness vocabulary for Decision Summary:**
- `High / PR-Ready` — Do Now items
- `High / Stage 1` — Investigate items that are structurally proven or measured but failed a Do Now gate requirement
- `Medium / Stage 1` — Investigate items based on heuristic evidence or requiring hypothesis validation
- `High / Decision Pending` — Needs Decision items

**Heuristic alone never qualifies for Do Now.** Evidence basis must be `measured` or `structural` to pass the Do Now gate.

## Report Structure

The report is grouped by action class (Do Now / Investigate / Needs Decision), not by confidence band. The Decision Summary appears early (BLUF) so an engineering lead can triage the top actions within 30 seconds. Detailed finding sections provide the execution-ready schemas below.

### Do Now Gate — All Required

An item qualifies for Do Now only if it has ALL of the following:

1. Exact current -> proposed config diff with derivation for every proposed value
2. Named target owner (not "unlabeled" or "service owner")
3. Numeric, time-bounded Outcome DoD with both primary and guardrail metrics
4. Pre-change evidence (measured or structural — **heuristic alone never qualifies for Do Now**)
5. Rollback signal with a derived threshold (not arbitrary)
6. IaC Location status of Confirmed, Likely, or Search Required

If any are missing, the item drops to Investigate regardless of confidence level.

### IaC Location Rules

| Status | Meaning | Do Now eligible? |
|--------|---------|-----------------|
| **Confirmed** | Exact file path verified via repo tree walk (display_name match) | Yes |
| **Likely** | Strong candidate path from metric/module name correlation, not exact display_name match | Yes |
| **Search Required** | No match in IaC discovery, but repo tree link provided for manual search. Must include: (1) link to `tf/` directory in repo, (2) policy display_name as search hint, (3) exact replacement guidance | Yes |
| **Unknown** | No IaC repos provided or discovery failed entirely | No — drops to Investigate |

### Metric Families by Finding Type

| Finding type | Primary metric | Guardrail metric |
|---|---|---|
| Noise tuning | Raw incidents or open-incident hours | Detection latency for real incidents |
| auto_close fixes | Median open duration | N/A when change cannot hide signal |
| Routing/ownership | Correct owner/channel coverage | No alert dropped during transition |
| Orphaned alerts | Explicit close/remove/route decision | N/A |
| Coverage gaps | Implementation milestone | N/A |

Guardrail thresholds must be derived from evidence, not arbitrary. Guardrail = N/A only when the change cannot plausibly hide a real signal.

PromQL Change Spec Rules and Contextual Action Links (`## Situational rules and steps`, after Key Terms): exact current and proposed fragment, never blind copy-paste; one `**Links:**` line after `**Notification Reach:**` on each Do Now and Investigate finding, max 3, no URLs in `Policy ID` or `IaC Location`.

### Two-Stage DoD Rules

- Stage 1 closes on hypothesis confirmed/refuted + explicit next action documented
- Stage 2 is a completely separate follow-up item with its own numeric, time-bounded outcome DoD
- This prevents mixing discovery work with delivery work in a single ticket

### Structurally Proven but Not-Yet-PR-Ready Items

Items with structural or measured evidence that fail the Do Now gate (e.g., missing IaC location, missing owner) land in Investigate with their full evidence preserved. The `To Upgrade` field states exactly which gate requirement is missing. Stage 1 for these items is not hypothesis validation — it is resolving the missing gate requirement (e.g., "locate IaC path," "assign owner"). Once resolved, the item can be promoted to Do Now in the next report cycle or follow-up.

### Needs Decision Rules

- Deadline is advisory — the report does not auto-execute changes
- Default Recommendation is guidance for the decision owner, not an ultimatum
- Every Needs Decision item must have a named owner, not a generic role

### Mandatory Needs Decision Triggers

The following Needs Decision items are mandatory when their trigger condition is met:

- **Silent Policy Cleanup:** If `silent_policy_total > 0` and `silent_policy_count / silent_policy_total > 0.5` (more than half of enabled policies had zero incidents in the analysis window), include a "Silent Policy Cleanup" Needs Decision item with exact counts from compute-clusters output.

### Report templates and skeleton

Before writing any finding, Read `references/report-templates.md` (per-item templates, link URL patterns) and fill every field; the Investigate template's Proposed Config Diff appears ONLY when evidence basis is `measured` or `structural` and a diff is derivable.

Before writing the report, Read `references/report-skeleton.md` and follow it section by section. Its rules: Decision Summary early, capped at 8-12 rows, every non-empty category at least one row, the rest by priority, a note when over 12; modeled impact never overrides measured baselines; one Systemic Issues section with Ownership/Routing Debt, Dead/Orphaned Config, Missing Coverage and Inventory Health, read from compute-clusters output, never computed ad-hoc; Do Now opens with the Global Implementation Standard (verify every mutated field in production); a Verification Scorecard row per Do Now item; "Not attempted" lists genuine blockers only.

## Tier Detection

Run the shared observability preflight before data access:

```bash
bash '<PLUGIN_ROOT>/scripts/obs-preflight.sh'
```

If `gcloud` is `unauthenticated`, run `gcloud auth login` before proceeding. If `gcloud` is `missing`, fall to Tier 3.

### Tier 1 — REST API via scripts (default for inventory and bulk)

Default path for all data pull. Uses `gcloud auth print-access-token` for auth, `curl` for requests, Python scripts for pagination and extraction. MCP truncates at ~100K characters and cannot handle monitoring projects with >50 policies — REST has no such limits.

The commands (`pull-policies.py`, `pull-incidents.py --days 14`, `compute-clusters.py`, each writing to `$WORK_DIR`) are under `### Tier 1 data-pull commands`, after Key Terms.

### Tier 2 — MCP (targeted enrichment only)

If `list_time_series` or `list_alert_policies` MCP tools are available, use them **only** for targeted enrichment after cluster stats are computed:
- Single policy detail lookups (reading full PromQL query text)
- Time-series queries for metric validation on nominated clusters (< 50 results expected)

Never use MCP for bulk inventory pulls or incident history.

### Tier 3 — Guidance only

If neither gcloud nor MCP tools are available, provide manual Cloud Console instructions.

## Analysis Flow

### Stage 0: Validate Data Access

Before any analysis, discover and validate the monitoring project:

1. If the user provides a project ID, verify it is a **monitoring project** (has alert policies), not just a resource project. Run: `python3 pull-policies.py --project PROJECT --output /tmp/ah-check.json`.
2. **If zero policies returned:** The project is likely a resource project scoped under a different monitoring project. Provide actionable guidance: *"Project {X} returned 0 alert policies. This is likely a resource project, not the monitoring project. Try: (a) project ending in `-monitoring` (e.g., `{org}-monitoring`), (b) check Cloud Console > Monitoring > Settings > Metrics Scope to find which project hosts the alert policies, (c) run `gcloud alpha monitoring policies list --project={candidate}` to test candidates."* Do not just ask the user — give them the diagnostic path.
3. If the user does not provide a project, check if recent incident context or prior conversation names it. If not, ask once with the guidance above.
4. Verify incidents return non-empty: run pull-incidents.py with `--days 1` as a quick check. If zero incidents but policies exist, the window may be too narrow or incidents are in a different project — warn with specifics.
5. If both return data: `"Monitoring project: {project}, {N} policies found, incidents available. Proceeding with {days}-day analysis."`
6. **GitHub org and IaC repos for links:** Check if recent conversation or CLAUDE.md names a GitHub org and IaC repos. If not, ask once: *"Which GitHub org hosts your monitoring IaC, and which repo(s)? (e.g., `example-org`, repos `monitoring` and `k8s`). Used for IaC links in the report — skip if not applicable."* Store as `{github_org}` and `{iac_repos}` (list). If the user skips, omit IaC links.

Fail early — do not proceed to Stage 1 with an empty or wrong project.

### Stage 1: Pull Data

Run pull-policies.py and pull-incidents.py with the validated project. Verify non-empty results. Report counts:
- Total policies (enabled/disabled)
- Total incidents in window
- Policies by squad label

**Optional enrichment** (SLO config, IaC discovery, CODEOWNERS; steps under `### Stage 1 optional enrichment`, after Key Terms) runs in that order, each only when its preconditions hold (`{github_org}` given, `{iac_repos}` too for IaC and CODEOWNERS, and `gh` authenticated); otherwise it writes its fallback artifacts and is skipped. Every run writes `slo-services.json` and `slo-source-status.json` (run the SLO block in `references/slo-enrichment.md`: it writes them on every branch) and `iac-discovery/iac-status.json`, and reports each step's Stage 1 line (`SLO config: {reason}`, `IaC discovery: {reason}` when skipped). A finding's Target Owner is its squad label, else its `tf/squads/{squad}/` directory, else CODEOWNERS (say which), else `⚠ assign`.

### Stage 2: Compute Cluster Stats

Run compute-clusters.py. This produces a structured output with three sections:

**Per-cluster fields (`clusters` array):**
- `total_open_hours` — sum of actual incident durations (openTime to closeTime) in hours. **MANDATORY source for all open-incident-hours figures in the report.** Do NOT compute open-hours ad-hoc from `raw * median_duration` — that formula is inaccurate in both directions (overstates retrigger clusters, understates chronic long-tail clusters). If this field is missing or 0 for a cluster, the installed script version may predate this feature — re-run with the local source script.

The other per-cluster fields and the inventory-level fields (`metric_types_in_inventory`, `unlabeled_ranking`) are listed under `### Stage 2 output fields`, after Key Terms.

**After a compaction, Read this SKILL.md before continuing past Stage 2.** The prescriptive templates Stage 3 applies, the rest of Stage 3b, and Stages 4-5 sit past the re-attach cut; this is their every-run index.

**Every run after Stage 2:** Stage 3 applies the prescriptive reasoning templates (by pattern and by alert type) to every cluster; Stage 3b queries all clusters, prioritizing by raw incident count on API errors or rate limits; Stage 4 checks the Coverage Gap Checklist, runs Routing Validation (zero-channel and unlabeled policies with `raw_incidents > 10`, and label-inconsistent clusters with `raw_incidents > 5`, are promoted to Investigate) and the SLO cross-reference only when `slo-source-status.json` is `ok`; Stage 5 applies the Do Now Gate (failures drop to Investigate) and resolves IaC Location from `iac-modules.json`, never with `gh search code`.

### Stage 3: Classify and Prescribe

Read the cluster stats JSON. For each cluster, apply the prescriptive reasoning templates below to assign a verdict and specific recommended action.

**Threshold-aware prescriptions:** When the cluster data includes `threshold_value` and `comparison`, state the current config explicitly in the per-item output: *"Current: {comparison} {threshold_value}, eval window {eval_window_sec}s, auto_close {auto_close_sec}s"*. Use the actual value in recommendations: *"Raise threshold from 0 to >1000"* not *"Raise threshold to >1000"*. When `condition_match` is `"ambiguous"`, note all threshold values and flag which one the recommendation applies to. When `condition_filter` or `condition_query` is available, include a truncated excerpt (≤60 chars) in the per-item output for reviewer auditability.

### Stage 3b: Targeted Metric Validation

For the **top 5 clusters by raw incidents** where the evidence basis would be "heuristic" (not "structural" — structural flaws like auto_close NOT SET don't need metric validation):

**Step 1 — Map PromQL metric names to Cloud Monitoring equivalents.**

Before the first metric query, Read `references/metric-queries.md`: PromQL to Cloud Monitoring mapping and suffix order (a histogram `_count` maps to the parent `/histogram` type, never a `_count` metric).

**Label discovery from PromQL:** Cloud Monitoring labels don't always match what you'd guess. Read the PromQL query from `policies.json` to find the actual label names used. For example, `http_server_requests_seconds_count{container="hcs-gb"}` tells you the Cloud Monitoring filter needs `metric.labels.container = "hcs-gb"` — not `metric.labels.application` or `metric.labels.service`. Always check the PromQL before constructing filters. PromQL labels on the metric selector map to `metric.labels.X` in Cloud Monitoring.

**Step 2 — Extract threshold from PromQL query text.**

When `threshold_value` is null (PromQL conditions), extract from the query string. PromQL thresholds appear as a comparison operator at the end or after a closing parenthesis: `... > 1000`, `... < 0.01`, `... == 0`. Match with: `[><=!]+\s*([\d.]+)\s*$` on the query text.

**Mandatory Query Parameters by Metric Class:**

Every metric validation query MUST specify ALL THREE aggregation parameters. Omitting `crossSeriesReducer` when multiple series exist produces sparse, unrepresentative samples.

| Metric class | perSeriesAligner | alignmentPeriod | crossSeriesReducer | Expected points (14d) |
|---|---|---|---|---|
| Gauge (JVM threads, memory util, disk util) | ALIGN_MAX | 3600s | REDUCE_MAX | ~336 |
| Counter/delta (request count, restart count) | ALIGN_DELTA | 3600s | REDUCE_SUM | ~336 |
| Distribution (DB Insights latency) | ALIGN_DELTA | 86400s | — (per-hash) | ~14 |
| Error rate (ratio of two counters) | ALIGN_DELTA + REDUCE_SUM | 3600s | REDUCE_SUM (per query) | ~336 each |

When in doubt, use REDUCE_MAX for gauges and REDUCE_SUM for counters. Never omit the reducer for metrics that may have multiple series (per-pod, per-container, per-node).

**Step 3 — Query the metric.**

Use MCP `list_time_series` (Tier 1) or REST API via temp-file pattern (Tier 2). Select aligner and reducer from the Mandatory Query Parameters table above based on the metric class.

The Tier 2 REST query template (all three aggregation parameters, `pageSize=100000`) is in `references/metric-queries.md`.

Write results to `$WORK_DIR`, not to conversation context. Parse with `python3` one-liner to extract p50/p95.

**Result Quality Gate — MANDATORY before using any metric result:**

After every query, validate the result before computing percentiles:

1. **Point count check:** For a 14-day window with 1h alignment, expect ~336 points per reduced series. If fewer than 50 points are returned, flag the result as `insufficient sample` and note the actual count. Do NOT use sparse results to derive threshold recommendations — they produce unreliable percentiles. For distribution metrics with daily alignment (~14 expected points), use a minimum threshold of 7 points instead of 50.
2. **Series count check:** After REDUCE_MAX/REDUCE_SUM, expect exactly 1 series. If >1 series is returned, the reducer was not applied — re-query with the correct reducer.
3. **Pagination check:** If the response contains `nextPageToken`, the result is truncated. Re-query with higher `pageSize` or paginate. Do NOT compute percentiles from truncated data.
4. **Evidence block logging:** Every metric validation result MUST log in the Evidence Ledger: metric type, filter, aligner, reducer, alignment period, series count, point count, and numeric results. This makes cross-report comparisons auditable.

If a query fails the quality gate, mark the evidence basis as `heuristic (insufficient sample: N points)` instead of `measured`. Do not promote to Do Now based on insufficient samples.

**Step 4 — Compare against threshold.**

- If p95 < threshold: the alert rarely fires legitimately. Recommend lowering threshold to p95 + 20% headroom. State: *"p95={X}, threshold={Y}, headroom={Z}%"*.
- If p50 > 0.8 × threshold: baseline crowding. State: *"p50={X} is {Y}% of threshold={Z} — baseline crowding"*.
- Record the query used and numeric result in the cluster's `Evidence basis` field. Mark as `measured`.

**Step 5 — Handle failures.**

If the metric type cannot be mapped, the query returns no data, the suffix is wrong, or the result fails the quality gate: note the reason and keep `heuristic` basis. A no-data result is itself a finding — the metric may be misconfigured or the resource labels may not match. An insufficient-sample result (< 50 points) means the query parameters need adjustment (missing reducer, low pageSize, or metric sparsity) — do not treat it as measured evidence.

**Scope:** Query all clusters, not just heuristic-basis. Structural items also benefit from measurement (e.g., confirming queue baselines are zero proves the `> 0` threshold fires on transients). If API errors or rate limits occur, prioritize by raw incident count.

**Multi-query patterns** — these are NOT limitations, they are standard approaches. Use them:

The patterns (cumulative distributions, error-rate ratios, high-cardinality counters, histogram-based error rates, custom PromQL) and the two-query ratio template are in `references/metric-queries.md`; check them before classifying any metric as "not attempted".

If a multi-query approach is available but not executed (e.g., auth expired), state the approach and mark as "not attempted — auth expired" rather than claiming an API limitation.

### Stage 4: Coverage Gap Check

Read `metric_types_in_inventory` from the compute-clusters output. Compare against the Coverage Gap Checklist below. For each gap:
- If the metric type exists in the inventory: check scope — is it applied to all relevant clusters/services, or only a subset? If partial, report "extend scope" with the specific uncovered projects.
- If the metric type does not exist: report "add new".
- Cross-reference each gap with existing noisy clusters that the gap metric would detect upstream (e.g., probe failure coverage → would provide early signal for pod restart clusters).

#### Routing Validation

Check for routing and ownership gaps using policy-level and cluster-level data from `$WORK_DIR`.

**Zero-channel policies (policy-level):**
Scan `policies.json` for entries where `notificationChannels` is empty AND `enabled` is true. These fire but notify nobody — invisible failures.
- Policies with `raw_incidents > 10` (cross-reference against `clusters.json`): promote to **Investigate** with action: *"Silent alert — fires but has no notification channels. Add a notification channel or disable."*
- Policies with low/zero incidents: surface in **Systemic Issues > Dead/Orphaned Config** — *"Zero-channel policy: {displayName} — enabled but no notification path."*

**Unlabeled high-noise policies (policy-level):**
The existing `unlabeled_ranking` table stays in Systemic Issues. Additionally, for top entries with `raw_incidents > 10`:
- Promote to **Investigate** with ownership language: *"No squad/team/owner label — ownership is implicit and unauditable. {N} incidents in {days}d have no traceable owner."*
- Do not reference org-specific routing fallback channels. The skill is generic.
- Leave suggested owner as "⚠ assign" — the skill does not infer squad ownership from service names.

**Label inconsistency promotion (cluster-level):**
For clusters where `label_inconsistency` is true AND `raw_incidents > 5`:
- Promote to **Investigate** as a cluster-level finding: *"Label mismatch — staging/test label on a production resource. {N} incidents may be misrouted or ignored."*
- Do NOT merge into the policy-level unlabeled table — entity types stay separate.

#### SLO Coverage Cross-Reference

Only run this section when `$WORK_DIR/slo-source-status.json` has `"status": "ok"`. Read `$WORK_DIR/slo-services.json` (normalized service names) and cross-reference against cluster data.

**Service grouping:** Group clusters by `service_key` from `clusters.json`. Skip clusters where `service_key` is `null`. Only consider clusters with `signal_family` in (`error_rate`, `latency`, `availability`) — exclude `other`.

**SLO migration candidates:**
For each service_key with `total_raw_incidents > 20` across user-facing clusters AND NOT in `slo-services.json`:
- Surface in **Coverage Gaps** table: *"SLO review candidate — {service_key} has {N} noisy user-facing threshold alerts ({families}), no SLO definition."*

**SLO review candidates (redundancy check):**
For each service_key that IS in `slo-services.json` AND has noisy user-facing threshold alerts:
- Surface as **Needs Decision** item: *"Service {service_key} has an SLO definition and also {N} noisy user-facing threshold alerts; review for redundancy or intentional overlap."*
- Do not claim same-signal overlap — `slo-services.json` carries service names only, not signal coverage metadata.

**Matching rules:** Both `service_key` and SLO service names are normalized (lowercase, env suffixes stripped, separators unified). Only exact-match after normalization. Unmatched service_keys are excluded, not fuzzy-guessed.

### Stage 5: Produce Report

Write the final report as markdown using the Report Skeleton template below. Group findings by action class (Do Now / Investigate / Needs Decision), not by confidence band. Apply the Do Now Gate to determine which items qualify for the Do Now section. Items that fail the gate drop to Investigate regardless of confidence level.

The Report Skeleton and the per-item templates are in `references/report-skeleton.md` and `references/report-templates.md`; Read both before writing (see Report Structure above).

#### IaC Location Resolution via Module Discovery

During Do Now gate evaluation, resolve IaC Location for each finding using the `iac-modules.json` mapping built in Stage 1.

**Resolution rules (in priority order):**

1. **Confirmed:** The policy's `display_name` matches a `display_name` extracted from a TF file in `iac-modules.json` (accounting for `${var.XXX}` interpolation). The file path is known and verified from the repo tree. Use direct link.
2. **Likely:** The policy's metric type, PromQL fragment, or resource type matches a known TF module name (e.g., policy using `artemis_consumer_count` → module `message_broker_alerts`), but `display_name` didn't match exactly (e.g., due to complex interpolation). Include the candidate file path.
3. **Search Required:** No match in `iac-modules.json`, but `{iac_repos}` were provided. Include a link to the repo tree (`https://github.com/{org}/{repo}/tree/main/tf`) for manual search, plus the policy display_name as a search hint.
4. **Unknown:** No `{iac_repos}` provided or IaC discovery failed entirely.

**Link construction:**
- **Confirmed/Likely:** Direct link to the file: `https://github.com/{org}/{repo}/blob/main/{file_path}`
- **Search Required:** Link to the TF directory: `https://github.com/{org}/{repo}/tree/main/tf`
- If an `invocation_file` exists (module is instantiated from a separate file with threshold/label variables), include it as a second link: the module definition for the PromQL template, and the invocation file for the configurable values (thresholds, labels, duration).

**Do not use `gh search code`** for IaC resolution. Policy IDs are GCP-generated at `terraform apply` time and never appear in `.tf` source. GitHub code search for policy IDs always returns zero results.

## Prescriptive Reasoning by Pattern

### Flapping (raw/episode > 3, raw > 10)

The alert fires and resolves repeatedly on the same resource. Root cause: threshold too close to baseline, or evaluation window too short.

Compare the configured threshold to the median retrigger interval and median duration:
- If median_duration < duration setting: raise duration to 2x median_duration
- If threshold is below observed baseline (from metric validation): raise threshold above p50 of the observed metric. State current vs recommended value.
- If auto_close is NOT SET and median_duration > 1h: set auto_close to 2x median_duration (capped at 86400s / 24h)
- If notification_channels > 0 and noise_score >= 5: recommend demoting to dashboard-only
- If raw/episode ratio > 10: the alert has a structural flap design — recommend auto_close or redesign

### Chronic (episodes >= 5, median_duration > 1h)

The alert fires and stays open for extended periods. The underlying issue is real and persistent.

This is "Fix the underlying issue". The alert is working correctly — the service has a problem:
- State specific investigation pointers based on metric_type and resource_type
- If auto_close is NOT SET: recommend setting it to match the evaluation window to prevent alert accumulation
- Do not recommend raising the threshold — the alert is detecting a real condition
- If distinct_resources is high (> 20): flag as systemic/cluster-wide, not single-service

### Recurring (episodes >= 5, median_duration < 1h)

The alert fires regularly but resolves within an hour. Could be deploy-time transients, batch jobs, or genuine intermittent issues.

- If tod_pattern shows > 50% concentration at a specific hour: infer scheduled job or deployment window. Recommend time-of-day mute for that window or extend duration to ride through the transient. Flag as low confidence if < 80% concentration.
- If noise_score >= 3: recommend raising threshold or adding a volume floor (e.g., minimum request count for error-rate alerts)
- If noise_score < 3 and episodes > 15: this is "Fix the underlying issue" — recurring real issue

### Burst (raw > 10, episodes <= 3)

Many raw incidents collapse to few episodes. Likely a single event with cascading re-fires.

- Recommend auto_close if NOT SET
- Check if the burst correlates with a deploy or scaling event
- Usually "Tune the alert" — the alert design amplifies a single event into many notifications

### Isolated (everything else)

Low-frequency, distinct, potentially well-calibrated.

- If raw <= 3: "No action" — keep as-is
- If raw >= 5 and noise_score >= 3: "Tune the alert" — review threshold
- Otherwise: "No action" — monitor

## Prescriptive Reasoning by Alert Type

### Error-rate alerts (error rate > X%)

- Check if the PromQL/MQL includes a minimum request volume clause. If not, recommend adding one (e.g., `AND total_requests > 200` in the 15m window).
- If the threshold is <= 1% and retrigger interval < 5m: the alert fires on single-request errors on low-traffic endpoints. Recommend raising to 3-5%.
- If concentrated at deploy hours: recommend extending duration from current to 900s.
- Check cluster selector: if it targets test clusters but routes to a prod squad, flag the mismatch.

### Latency alerts (P99/P95/P90 > Xms)

- If multiple percentile alerts exist for the same service (P90, P95, P99), the lower percentile dominates. Recommend consolidating to one.
- If the alert has high noise_score: route to **Needs Decision** as SLO-redesign candidate. The skill cannot determine whether the service is user-facing or what SLI/SLO targets are appropriate. Frame as: *"This latency alert is a candidate for SLO burn-rate redesign if the service is user-facing. Analyst must confirm SLI target and error budget."*

### Queue/message broker alerts

- "Queue without consumer": if auto_close is NOT SET and median_duration > 24h, the alert is in permanent-fire state. Set auto_close=86400s.
- "Queue never empty": if the lookback window exceeds 12h and threshold is 0, the design causes permanent firing. Raise threshold to >1000 and shorten lookback to 6h.
- "Expired messages": if threshold is 1 (single message), raise to >100 or convert to rate-based.

### Pod restart alerts

- The threshold (>N restarts in Xh) is usually reasonable. If distinct_resources > 100, the problem is systemic — don't tune the alert, investigate the cluster.
- If auto_close is NOT SET: set to match the evaluation window.

### WAF/blocked-request alerts

- If chronic: review WAF rules for false positives.
- If burst at specific hours: may correlate with bot traffic patterns.

## Coverage Gap Checklist

Check the policy inventory for coverage of these high-value signals. For each, first search existing policies for the metric type. If found: recommend "extend scope" or "retune". If not found: recommend "add new".

| Gap | Metric to check | Why |
|-----|-----------------|-----|
| SSL certificate expiry | `ssl.googleapis.com/certificate/expiry_time` or uptime check SSL | Silent cert expiration causes hard outages |
| Pod probe failures | `kubernetes.io/container/probe/failure_count` or PromQL equivalent | Early signal before pod restart storms |
| Node memory/disk pressure | `kubernetes.io/node/status/condition` or `node/memory/allocatable_utilization` | Cascading pod evictions from node pressure |
| Cloud SQL connection saturation | `cloudsql.googleapis.com/database/network/connections` | Connection exhaustion causes app-level errors |
| Service 5xx coverage (per service) | Per-service HTTP error rate | Blind spots for services without error monitoring |
| Persistent disk utilization | `compute.googleapis.com/instance/disk/utilization` | Silent disk-full failures |

## Key Terms

Include a Definitions section in every report (after Methodology, before Action Type Legend) with these terms:

| Term | Definition |
|------|-----------|
| **Raw incidents** | Total alert firings in the analysis window |
| **Episodes** | Deduplicated incidents (same policy + resource, merged if gap < dedupe window) |
| **Raw/episode ratio** | Flapping indicator. 1:1 = clean signal. >5:1 = noisy. >20:1 = structural flaw |
| **Noise score** | 0-10 composite of ratio, duration, retrigger interval, and time-of-day pattern |
| **Evidence basis** | Whether a numeric prescription is `measured` (from validated metric query with stated scope) or `heuristic` (rule of thumb — must be flagged for validation) |
| **Open-incident hours** | Sum of all incident durations in the analysis window, measured in hours. Captures both volume and persistence of alert noise. |

## Situational rules and steps

Kept after the core steps: everything up to Stage 3b's Result Quality Gate ends inside the post-compaction window, and the end of Stage 2 indexes the every-run gates that follow it. Each section below is named where it applies.

### PromQL Change Spec Rules

- **Simple edits** (scalar threshold, window, auto_close): show exact current and proposed fragment
- **Complex edits** (multi-clause PromQL, aggregation changes): show full affected clause or precise change spec
- Never rely on blind copy-paste as the standard; aim for exact replacement guidance

### Contextual Action Links

Every Do Now and Investigate finding gets one `**Links:**` line directly after `**Notification Reach:**`. No links in Decision Summary, Needs Decision, Verification Scorecard, or Evidence Ledger. Max 3 links per finding, separator ` · `.

The link URL patterns (Open policy, Open alert policies, View IaC, Browse IaC, Incident history, Validate metric) and when each applies are in `references/report-templates.md`.

**Do Now:** Open policy + View IaC (or Browse IaC) (2 links). When an invocation file exists (threshold/label config separate from module definition), include both: View IaC (module) + View IaC (invocation) + Open policy (3 links).
**Investigate:** Open policy + View/Browse IaC + optional contextual third link (max 3). Omit third link if it would require inventing missing query details.
**Do not** embed URLs in `Policy ID` or `IaC Location` fields — keep those plain text.

### Tier 1 data-pull commands

```bash
WORK_DIR=$(mktemp -d /tmp/ah-XXXXXX)
SCRIPTS_DIR='<PLUGIN_ROOT>/skills/alert-hygiene/scripts'

python3 "$SCRIPTS_DIR/pull-policies.py" \
    --project "$MONITORING_PROJECT" \
    --output "$WORK_DIR/policies.json"

python3 "$SCRIPTS_DIR/pull-incidents.py" \
    --project "$MONITORING_PROJECT" \
    --days 14 \
    --output "$WORK_DIR/alerts.json"

python3 "$SCRIPTS_DIR/compute-clusters.py" \
    --policies "$WORK_DIR/policies.json" \
    --alerts "$WORK_DIR/alerts.json" \
    --output "$WORK_DIR/clusters.json"
```

### Stage 2 output fields

Per-cluster fields (`clusters` array), besides `total_open_hours` (kept in Stage 2):
- `raw_incidents`, `deduped_episodes`, `dedupe_window_sec`
- `distinct_resources`, `median_duration_sec`, `median_retrigger_sec`
- `tod_pattern`, `pattern` (flapping/chronic/recurring/burst/isolated)
- `noise_score`, `noise_reasons`, `label_inconsistency`
- `threshold_value`, `comparison`, `condition_filter`, `condition_query`, `condition_type`, `condition_match`
- `service_key` (normalized service identity from condition labels, or null), `signal_family` (error_rate/latency/availability/other)

**Inventory-level fields:**
- `metric_types_in_inventory` — deduplicated set of all metric types across all policy conditions
- `unlabeled_ranking` — top 20 enabled policies without squad/team/owner label, ranked by total raw incidents

### Stage 1 optional enrichment

#### Optional: SLO Config Enrichment

After pulling policies and incidents, attempt to fetch SLO service definitions from GitHub. This is optional enrichment — the core analysis runs without it.

**Preconditions:** `{github_org}` was provided in Stage 0 AND `gh` CLI is available AND authenticated (`gh auth status` succeeds). If any precondition fails, write fallback artifacts and skip.

**Flow:** Read `references/slo-enrichment.md` and run its block as written: it short-circuits on each failed precondition and checks fetch, decode and parse in turn, writing the artifacts below on every branch.

**On-disk artifacts (always written, every branch):**
- `slo-services.json` — normalized service name list or `[]`
- `slo-source-status.json` — `{"status": "ok|empty|unavailable", "reason": "...", "count": N}`

Names in `slo-services.json` are normalized with the same rules as `service_key` in compute-clusters.py: lowercase, strip environment suffixes (`-prod`, `-staging`, `-pta`), replace separators (`_`, `.`) with `-`.

**Stage 1 report line addition:** `"{M} services with SLO definitions"` when status is `ok`, `"SLO config: {reason}"` otherwise.

#### Optional: IaC Module Discovery

After SLO enrichment, build a `display_name → file_path` mapping by walking the IaC repo tree via `gh api`. This replaces the previous `gh search code` approach, which returned zero results because GCP-generated policy IDs never appear in Terraform source.

**Preconditions:** `{github_org}` and `{iac_repos}` were provided in Stage 0 AND `gh` is available AND authenticated. If any fail, write fallback and skip.

**Flow:** Read `references/iac-discovery.md` and run it for each repo in `{iac_repos}` that contains a `tf/` directory. It walks the repo tree with `gh api`, never `gh search code` (policy IDs are assigned at `terraform apply` and never appear in `.tf` source), and extracts `display_name` values from module, squad and root `.tf` files.

**On-disk artifacts (always written):**
- `iac-discovery/iac-modules.json` — `{display_name: {repo, module, file, type, invocation_file?}}`
- `iac-discovery/iac-status.json` — `{"status": "ok|empty|unavailable", "count": N}`

**Display-name matching rules:**
- The PromQL `display_name` in TF often contains Terraform variable interpolations (e.g., `"[${var.cluster}] Mobile API HTTP 5xx Error Rate (critical)"`). Strip `${var.XXX}` to a regex-compatible `.*` and match against the policy's `display_name` from `policies.json`.
- If a policy `display_name` matches multiple TF display_names (e.g., parameterized modules instantiated per-cluster), prefer the module definition file over squad files.

**Fallback: repo-level search link.** When a policy `display_name` does not match any discovered TF file, generate a fallback link to the repo tree for manual search: `https://github.com/{org}/{repo}/tree/main/tf`. This is always more useful than a GitHub code search for a policy ID.

#### Optional: Ownership Resolution via CODEOWNERS

After IaC module discovery, resolve suggested owners for policies that lack a `squad` label by cross-referencing IaC file paths against CODEOWNERS.

**Two-layer resolution:**

1. **CODEOWNERS match (mechanical):** For each IaC file path in `iac-modules.json`, find the matching CODEOWNERS rule (last match wins, per git spec). This resolves policies whose module definition or invocation file has a specific CODEOWNERS entry. Typically resolves high-volume infrastructure alerts (pod restarts, message broker, MySQL, ingress, WAF).

2. **Squad-directory inference (structural):** For policies defined or invoked from `tf/squads/{squad}/*.tf`, the squad directory itself implies ownership — even if the CODEOWNERS rule for that path is generic. A module invocation in `tf/squads/cosmos/recommendation_alerts.tf` means cosmos owns that alert regardless of whether CODEOWNERS maps `tf/squads/cosmos/*` to `@org/cosmos` or a generic owner. The squad directory name is the authoritative signal.

**Flow:** Read `references/codeowners-resolution.md` for the CODEOWNERS fetch and parser: the last matching rule wins, and a `tf/squads/{squad}/` path resolves to that squad first.

**On-disk artifacts (appended to existing):**
- `iac-discovery/iac-modules.json` — each entry gains `suggested_owner` field (team handle or null)
- `iac-discovery/codeowners-status.json` — `{"status": "ok|unavailable", "rules": N}`

**Owner resolution priority for report "Target Owner" field:**
1. Policy's existing `squad` label (already set in TF via `user_labels`) — highest priority, use as-is
2. Squad-directory inference from IaC file path (e.g., `tf/squads/cosmos/` → `@org/cosmos`)
3. CODEOWNERS match on IaC file path (e.g., `tf/modules/message_broker_alerts/` → `@org/devops-codeowners`)
4. No match → `⚠ assign`

**Report integration:**
- When `suggested_owner` is available and the policy has no squad label, use `suggested_owner` in the "Target Owner" field with a note: `{suggested_owner} (from CODEOWNERS)` or `{squad_name} (from squad directory)`
- In the Systemic Issues > Ownership/Routing Debt section, report resolution coverage: `"{N}/{M} ownerless clusters resolved via CODEOWNERS/squad-directory inference"`

**Stage 1 report line additions:**
- `"{N} IaC module mappings discovered"` when status is `ok`, `"IaC discovery: {reason}"` otherwise
- `"{N} CODEOWNERS rules loaded, {M} ownerless clusters resolved"` when CODEOWNERS available

## Reference files

Read each when its condition holds; never write a report section, a query or an enrichment step from memory.

| File | Read it |
|---|---|
| `references/slo-enrichment.md` | Stage 1, before SLO config enrichment. |
| `references/iac-discovery.md` | Stage 1, before IaC module discovery. |
| `references/codeowners-resolution.md` | Stage 1, before ownership resolution via CODEOWNERS. |
| `references/metric-queries.md` | Stage 3b, before the first metric query. |
| `references/report-templates.md` | Stage 5, before writing any finding or its Links line. |
| `references/report-skeleton.md` | Stage 5, before writing the report. |

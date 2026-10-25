# alert-hygiene — Stage 5 report skeleton

Read at SKILL.md Stage 5 before writing the report, on every run. The report rules restated under SKILL.md `### Report templates and skeleton` stay there. Moved verbatim from SKILL.md.

### Report Skeleton

```markdown
# Alert Hygiene Analysis Report
**Monitoring project:** {project} | **Window:** {days} days ending {date}

## Executive Summary
- {total_policies} policies ({enabled} enabled, {disabled} disabled), {total_incidents} raw incidents -> {total_episodes} episodes across {cluster_count} clusters
- Baseline metrics: {open_incident_hours} open-incident hours, {routed_volume} routed incidents, {ownerless_count} ownerless alerts
- Top findings (3-5 bullets with incident counts)
- {do_now_count} Do Now actions, {investigate_count} investigations, {decision_count} needs decision
- Modeled impact (estimated, scope: Do Now items only): {X} incidents reduced ({Y}%), {Z} open-incident hours reclaimed
- Note: modeled impact must never override measured baseline metrics. Always label projections as estimated with scope and confidence.

## Decision Summary
Capped at 8-12 items. Each Finding is linked to detailed section via anchor. Every non-empty category gets at least 1 row. After minimum representation, remaining rows filled in global priority order: Do Now by impact, then Investigate by urgency, then Needs Decision by deadline.

| Category | Finding (linked to detailed section) | Target Owner | Confidence / Readiness | Effort | Risk | Primary Expected Outcome | Next Action |
|----------|---------|--------------|----------------------|--------|------|--------------------------|-------------|

Primary Expected Outcome rules:
- Do Now: primary success outcome aligned to finding type (incident reduction, median duration, owner coverage)
- Investigate: Stage 1 closure result
- Needs Decision: decision closure

If more than 12 items total: *"Showing top {N} of {total} findings. See detailed sections below for complete list."*

## Methodology
- **Data source:** GCP Monitoring API (REST, paginated)
- **Scripts:** pull-policies.py (inventory), pull-incidents.py (incidents), compute-clusters.py (clustering + enrichment)
- **Analysis window:** {days} days ending {date}
- **Dedupe window:** max(1800s, 2× evaluation interval) per cluster
- **Noise score formula:** 0-10 composite: raw/episode ratio >5 (+3) or >2 (+1), median duration <15m (+2), retrigger <1h (+2), deploy-hour concentration (+1)
- **Pattern classification:** flapping (ratio>3 AND raw>10), chronic (episodes≥5 AND duration>1h), recurring (episodes≥5 AND duration≤1h), burst (raw>10 AND episodes≤3), isolated (other)
- **Evidence basis levels:** `measured` = metric time-series query with stated scope and result; `structural` = config flaw unambiguous from policy definition alone; `heuristic` = pattern-only inference, flagged for validation
- **To reproduce:** Run the three scripts with same `--project` and `--days`, then apply Stage 3-5 reasoning from this skill

## Definitions
(Key Terms table from the skill — raw incidents, episodes, raw/episode ratio with severity bands, noise score, evidence basis, open-incident hours)

| Term | Definition |
|------|-----------|
| **Open-incident hours** | Sum of all incident durations in the analysis window, measured in hours. Captures both volume and persistence of alert noise. |

(Plus existing terms: raw incidents, episodes, raw/episode ratio, noise score, evidence basis)

## Action Type Legend
- **Tune the alert** — the alert is miscalibrated. Specific config changes listed.
- **Fix the underlying issue** — the alert is correct. The service has a real problem.
- **Redesign around SLO** — replace threshold alerting with burn-rate/error-budget alerting.
- **Add/extend coverage** — a high-value blind spot exists.
- **No action** — well-calibrated, low-frequency. Keep as-is.

## Systemic Issues
Thematic and non-exhaustive — surfaces structural debt patterns without duplicating detailed findings.

### Ownership/Routing Debt
- Unlabeled policies ranked by incident volume (source: `unlabeled_ranking` from compute-clusters output)
- Misrouted alerts (e.g., prod alerts labeled as staging)
- Resolution coverage from CODEOWNERS/squad-directory inference (source: `iac-discovery/iac-modules.json`)

Top 10 policies without squad/team/owner label, ranked by total raw incidents:

| # | Policy | Policy ID | Raw ({days}d) | Episodes | Channels | Suggested Owner |
|---|--------|-----------|--------------|----------|----------|----------------|

**Suggested Owner resolution:** Populate from the ownership resolution in Stage 1:
1. If the policy's IaC file is in `tf/squads/{squad}/` → use the squad team handle (e.g., `@org/cosmos`)
2. Else if CODEOWNERS matches the IaC file path → use the CODEOWNERS team (e.g., `@org/devops-codeowners`)
3. Else → `⚠ assign`

Include a coverage summary: *"{N}/{M} ownerless clusters ({X}% of ownerless raw incidents) resolved via CODEOWNERS/squad-directory inference."*

### Dead/Orphaned Config
Read from compute-clusters output — do not compute ad-hoc.

**Zero-channel policies:** Read `zero_channel_policies` array. If non-empty, render table:

| Policy | Policy ID | Raw ({days}d) | Squad |
|--------|-----------|---------------|-------|

If empty: *"No zero-channel policies found."*

**Disabled-but-still-noisy:** Read `disabled_but_noisy_policies` array. If non-empty, render table with same columns. If empty: *"No disabled-but-noisy policies."*

### Missing Coverage
Coverage gaps from comparison of `metric_types_in_inventory` against Coverage Gap Checklist:

| Gap | Action | Implementation | Rationale | Upstream Signal For |
(last column cross-references existing clusters this gap would detect earlier)

### Inventory Health
Read from compute-clusters output — do not compute ad-hoc.

- **Silent policy ratio:** `silent_policy_count` / `silent_policy_total` from compute-clusters output
- **Condition type breakdown:** render `condition_type_breakdown` dict from compute-clusters output
- **Enabled/disabled counts:** from Stage 1 policy pull (no change)

## Actionable Findings: Do Now
Items ordered by impact descending.

**Global Implementation Standard:**
For all Do Now items, the following standard applies:
1. IaC PR is approved and merged
2. Engineer confirms via GCP Monitoring Console that **every mutated field** matches the proposed config in production:
   - For threshold/query changes: verify PromQL condition, thresholds, eval window, auto_close
   - For routing/label changes: verify squad/team labels, notification channels
   - For scope changes: verify project/resource selectors
3. Confirm no accidental changes to fields outside the change spec (scope, channels, labels, conditions)
4. Record merge date for 14-day outcome review

Per-finding Immediate Verification is added only when the verification steps are non-obvious or high-risk (scope moves across projects, duplicate policy consolidation, multi-policy edits, channel rewiring).

### 1. {Action}: {policy_name} [High / PR-Ready]
(Do Now per-item template)

## Actionable Findings: Investigate
Items ordered by urgency.

### 1. {investigation_title} [{High|Medium} / Stage 1]
(Investigate per-item template with Two-Stage DoD)

## Needs Decision
Items ordered by deadline ascending.

### 1. {decision_title} [High / Decision Pending]
(Needs Decision per-item template)

## Keep — No Action Required
Brief section with 5-10 representative well-calibrated clusters and one-liner rationale for each (e.g., "fires <2x/14d, threshold well above baseline, correct routing"). Demonstrates the analysis evaluated the full inventory.

## Verification Scorecard
Rolled-up outcomes for all Do Now items. Re-run analysis in {days} days to verify.

| Finding | Baseline | Target | Owner | Merge Date | Review Date | Primary Success Criteria | Guardrail | Confidence |
|---------|----------|--------|-------|------------|-------------|--------------------------|-----------|------------|

## Evidence Ledger / Reproduction
Grouped by validation method. Reviewer action: `metric query` and `config inspection` items are audit-complete; `pattern analysis` items need reviewer judgment before applying.

### Config inspection — provable from policy definition
| Cluster | What was checked | Finding | Scope |

### Metric query — validated against Cloud Monitoring time-series
| Cluster | Query | Result | Finding |

### Pattern analysis — inferred from incident frequency/timing, needs validation before applying
| Cluster | Pattern observed | What would upgrade this | Scope |

### Not attempted — specific blocker (auth expired, quota exhausted, metric not emitted)
> This section is for genuine blockers only. Do NOT list metrics here when a multi-query approach exists
> (e.g., histogram _count via /histogram type, error-rate ratios via two-query pattern).
> Check the Multi-query patterns table in Stage 3b before classifying a metric as "not attempted".

| Cluster | Blocker | What was tried |

## Appendix: Frequency Table
Full cluster table sorted by raw incidents: cluster key, raw, episodes, distinct resources, median duration, median retrigger, noise score, pattern, verdict, confidence.

## Appendix: Evidence Coverage
| Cluster | Metric Validated? | Evidence Basis | Sample Scope | Dedupe Window | Confidence |
(lets reviewer see which recommendations rest on metric validation vs pattern-only inference)
```

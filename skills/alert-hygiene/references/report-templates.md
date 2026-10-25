# alert-hygiene — Stage 5 per-item templates and link patterns

Read at SKILL.md Stage 5 before writing any finding or its `**Links:**` line. The Do Now Gate, the IaC Location Rules, the Two-Stage DoD and Needs Decision rules stay in SKILL.md. Moved verbatim from SKILL.md.

**Link construction** (see templates below for placement):

| Label | URL pattern | When |
|-------|-------------|------|
| Open policy | `https://console.cloud.google.com/monitoring/alerting/policies/{id}?project={monitoring_project}` | Concrete policy ID available |
| Open alert policies | `https://console.cloud.google.com/monitoring/alerting?project={monitoring_project}` | No concrete policy ID (fallback) |
| View IaC | `https://github.com/{org}/{repo}/blob/main/{file_path}` | IaC Location is Confirmed or Likely (direct file link from Stage 1 module discovery) |
| Browse IaC | `https://github.com/{org}/{repo}/tree/main/tf` | IaC Location is Search Required (link to TF directory for manual search) |
| Incident history | `https://console.cloud.google.com/monitoring/alerting/incidents?project={monitoring_project}` | Investigate only: next step is reviewing firing/timing patterns |
| Validate metric | `https://console.cloud.google.com/monitoring/metrics-explorer?project={monitoring_project}` | Investigate only: next step is metric validation AND report has enough query detail |

### Do Now Per-Item Template

```
### {N}. {Action}: {policy_name} [High / PR-Ready]

**Policy ID:** projects/{project}/alertPolicies/{id} | **Condition:** {condition_name}
**Target Owner:** {current_label} -> {target_team}
**Scope:** {projects affected}
**Notification Reach:** {N} channels
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/{id}?project={project}) · [View IaC](https://github.com/{org}/{repo}/blob/main/{file_path})

#### Current Policy Snapshot
(Include fields relevant to the finding type. Not all fields apply to every finding.)

**For threshold/query changes:**
**Threshold:** {comparison} {threshold_value} | eval: {eval_window_sec}s | auto_close: {auto_close_sec}s
**Condition:** `{condition_filter_or_query_excerpt_60chars}`

**For routing/ownership changes:**
**Current Label:** squad={current} | **Current Channels:** {channel list or count}

**For all Do Now items:**
**IaC Location:** [{Confirmed|Likely|Search Required}] {path or search guidance}

**Situation:** {what is happening — 1-2 sentences}
**Impact:** {why it matters — incident counts, duration, team effect}

#### Configuration Diff & Derivation
| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| {param}   | {value} | {value}  | {why this value was chosen} |

**Pre-change Evidence:** {metric query result or structural proof with stated scope}
**Evidence Basis:** {measured|structural} — {query text or reasoning}

**Outcome DoD:**
- **Primary:** {numeric, time-bounded, aligned to finding type} (e.g., "raw incidents < 15 within 14d")
- **Guardrail:** {what must NOT degrade} (e.g., "no genuine backlog > 1000 goes undetected")

**Rollback Signal:** {derived threshold + timeframe for revert}
**Related:** {cross-references to other findings or systemic issues}
```

### Investigate Per-Item Template

```
### {N}. {investigation_title} [{High|Medium} / Stage 1]

**Policy ID:** projects/{project}/alertPolicies/{id}
**Target Owner:** {team}
**Scope:** {projects affected}
**Notification Reach:** {N} channels
**Links:** [Open policy](https://console.cloud.google.com/monitoring/alerting/policies/{id}?project={project}) · [View IaC](https://github.com/{org}/{repo}/blob/main/{file_path})

**Situation:** {what is happening — 1-2 sentences}
**Impact:** {why it matters — incident counts, team effect}

#### Proposed Config Diff (pending gate resolution)
> Include this section ONLY when evidence basis is `measured` or `structural` AND a specific
> config diff is derivable. Omit entirely for heuristic-only items.

| Parameter | Current | Proposed | Derivation |
|-----------|---------|----------|------------|
| {param}   | {value} | {value}  | {why this value was chosen} |

**Gate Blocker:** {which Do Now gate requirement is missing}
**To Upgrade:** {resolve blocker} → promotes to Do Now

**Evidence Basis:** {measured|structural|heuristic} — {current evidence}
**Hypothesis:** {explicit, testable hypothesis}

**Stage 1 DoD (Discovery — this ticket):**
- {specific diagnostic steps}
- **Closes when:** hypothesis confirmed/refuted AND follow-up action documented as a separate item
- **Timebox:** {N} days

**Stage 2 (Execution — spawned follow-up):**
- **If confirmed:** {specific action with its own numeric outcome DoD}
- **If refuted:** {alternative action or close with rationale}
```

### Needs Decision Per-Item Template

```
### {N}. {decision_title} [High / Decision Pending]

**Situation:** {what is happening — 1-2 sentences}
**Impact:** {why it matters — incident counts, redundancy, team effect}

**Decision Required:** {specific question that must be answered}
**Named Decision Owner:** {person or role — not generic "product owner"}
**Deadline:** {date — advisory, not auto-enforced}
**Default Recommendation:** {what the report recommends if no decision is made}

**Options:**
- **If A:** {action with expected outcome}
- **If B:** {action with expected outcome}
```

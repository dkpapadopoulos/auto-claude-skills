# Incident Analysis Evidence Links — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add investigator-facing evidence links (Logs Explorer, Metrics Explorer, Cloud Trace, deployment, GitHub) to the incident-analysis synthesis so claims are one-click verifiable.

**Architecture:** Constraint 12 in SKILL.md defines the behavioral contract (6 link types, 3 claim surfaces, priority/omission rules). A new reference file `references/evidence-links.md` holds URL templates and encoding rules. YAML schema extends `chosen_hypothesis`, `ruled_out`, and `service_error_inventory` with optional `evidence_links` arrays. Step 7 gains a prose `**Links:**` line placement rule.

**Tech Stack:** Markdown (SKILL.md, reference file), Bash (test assertions), JSON (eval fixture)

**Spec:** `docs/superpowers/specs/2026-04-09-incident-analysis-evidence-links-design.md`

---

### Task 1: Add Constraint 12 — Evidence Links

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` (insert after Constraint 11, before `## Investigation Modes`)
- Modify: `tests/test-incident-analysis-content.sh` (add assertions before `print_summary`)

- [ ] **Step 1: Write the test assertions**

Add to `tests/test-incident-analysis-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Evidence Links (Constraint 12)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has evidence links constraint" \
    "Evidence Links" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 12 defines allowed link types" \
    "logs.*baseline_logs.*metrics.*trace.*deployment.*source" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 12 has omission rule for empty arrays" \
    "Omit the.*evidence_links.*field entirely" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 12 enforces max links" \
    "max 3 links" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 12 excludes timeline and gate" \
    "timeline entries.*completeness gate" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 12 has deterministic priority rule" \
    "logs.*baseline_logs.*trace.*deployment.*metrics.*source" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 12 forbids placeholder URLs" \
    "Never emit placeholder.*reconstructed.*guessed" "${SKILL_FILE}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 7 FAIL for the new assertions

- [ ] **Step 3: Add Constraint 12 to SKILL.md**

Insert after line 183 (`**Self-check:** Do not build the next investigation step...stop and query.`) and before line 185 (`## Investigation Modes`):

```markdown

### 12. Evidence Links

For each of the three claim surfaces in the Step 7 synthesis — the chosen root-cause statement, each ruled-out hypothesis, and each `service_error_inventory` entry — include clickable verification links when the required URL parameters were captured at query time. This constraint is active across Steps 2-7.

**Allowed link types:**

| Type | Label pattern | When |
|------|--------------|------|
| `logs` | "{Service} incident logs" | LQL query during Steps 2, 3, 3c |
| `baseline_logs` | "{Service} baseline logs" | Baseline comparison supporting a claim (Step 3c tier classification, Step 5 recurring-workload check) |
| `metrics` | "{Service} {metric_name}" | `list_time_series` or Metrics Explorer data supporting a claim (Steps 2c, 3, 5) |
| `trace` | "Trace {first_8_chars}" | Step 4 trace correlation in the evidence chain |
| `deployment` | "{Service} deploy history" | Deployment correlation (Steps 3, 3c) |
| `source` | "Commit {first_7_chars}" or "{file_name}" | Step 4b source analysis candidate |

**Where links appear:**
- **Prose synthesis (Step 7):** One `**Links:** [label](url) · [label](url)` line after each root cause statement (max 3 links) and each ruled-out hypothesis (max 2 links). Separator ` · `.
- **YAML schema:** `evidence_links` arrays on `chosen_hypothesis` (max 3 links), each `ruled_out` entry (max 2 links), and each `service_error_inventory` entry (max 3 links).

**YAML item shape:**
```yaml
evidence_links:
  - type: "logs" | "baseline_logs" | "metrics" | "trace" | "deployment" | "source"
    label: "<display text>"
    url: "<https://...>"
```

**Priority rule (when valid candidates exceed the cap):** Select links in this order: `logs` > `baseline_logs` > `trace` > `deployment` > `metrics` > `source`. Within the same type, prefer the root-cause service. This order is deterministic.

**Omission rules:**
- If the required parameters to build a trustworthy URL are missing, omit the link and describe the evidence source in prose. Never emit placeholder, reconstructed, or guessed URLs.
- If a constructed URL would open a generic landing page (losing its filter or time range), omit it.
- Omit the `evidence_links` field entirely when no valid URL was captured for that block. Do not emit empty arrays.

**Where links do NOT appear:** timeline entries, completeness gate answers, `tested_intermediate_conclusions`, `root_cause_layer_coverage`, `service_attribution`.

**Capture rule:** Record link inputs (project_id, LQL filter, time window, trace_id, commit SHA, metric_type, metric filter) at query time. Do not reconstruct URLs retroactively from prose summaries — parameters may be lost.

**Exclusion:** kubectl commands and MCP tool invocations are not evidence links. Only clickable URLs that open a verification view in a browser.

**Label normalization:** Use stable, human-readable labels: `{Service} incident logs`, `{Service} baseline logs`, `{Service} {metric_name}`, `Trace {first_8_chars}`, `{Service} deploy history`, `Commit {first_7_chars}`. Labels must not contain raw LQL, full SHAs, or URL fragments.

URL construction templates and encoding rules: `references/evidence-links.md`.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add Constraint 12 — evidence links"
```

---

### Task 2: Create reference file `references/evidence-links.md`

**Files:**
- Create: `skills/incident-analysis/references/evidence-links.md`
- Modify: `tests/test-incident-analysis-content.sh` (add assertions before `print_summary`)

- [ ] **Step 1: Write the test assertions**

Add to `tests/test-incident-analysis-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# Reference file: evidence-links.md
# ---------------------------------------------------------------------------
EVIDENCE_LINKS_REF="${PROJECT_ROOT}/skills/incident-analysis/references/evidence-links.md"
assert_file_exists "references/evidence-links.md exists" "${EVIDENCE_LINKS_REF}"

EVIDENCE_LINKS_REF_CONTENT="$(cat "${EVIDENCE_LINKS_REF}")"
assert_contains "evidence-links ref: has Logs Explorer URL pattern" \
    "console.cloud.google.com/logs/query" "${EVIDENCE_LINKS_REF_CONTENT}"
assert_contains "evidence-links ref: reuses postmortem permalink rules" \
    "postmortem permalink" "${EVIDENCE_LINKS_REF_CONTENT}"
assert_contains "evidence-links ref: has label normalization rule" \
    "stable, human-readable" "${EVIDENCE_LINKS_REF_CONTENT}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 4 FAIL (file not found + 3 content checks)

- [ ] **Step 3: Create `references/evidence-links.md`**

Create file `skills/incident-analysis/references/evidence-links.md`:

```markdown
# Evidence Links — URL Construction Reference

URL templates, encoding rules, required parameters, and worked examples for the 6 evidence link types defined in Constraint 12.

## URL Templates

| Type | URL Pattern | Notes |
|------|-------------|-------|
| `logs` | `https://console.cloud.google.com/logs/query;query={ENCODED_LQL};timeRange={START}%2F{END}?project={PROJECT}` | Canonical base URL only — no UI extras like `summaryFields` |
| `baseline_logs` | Same as `logs` with the baseline time window | Same construction, different timestamps |
| `metrics` | `https://console.cloud.google.com/monitoring/metrics-explorer?project={PROJECT}&pageState=...` | `pageState` is a best-effort deeplink; exact JSON structure in examples below, not normative |
| `trace` | Reuses the existing postmortem permalink formatting rule (SKILL.md § POSTMORTEM Step 3): `https://console.cloud.google.com/traces/list?project={PROJECT}&tid={TRACE_ID}` | No new construction rule needed |
| `deployment` | Cloud Run: `https://console.cloud.google.com/run/detail/{REGION}/{SERVICE}/revisions?project={PROJECT}` / GKE: `https://console.cloud.google.com/kubernetes/deployment/{ZONE}/{CLUSTER}/{NAMESPACE}/{DEPLOYMENT}/overview?project={PROJECT}` / Other platforms: omit link | Platform-specific construction under one link type |
| `source` | Reuses the existing postmortem permalink formatting rule (SKILL.md § POSTMORTEM Step 3): `https://github.com/{ORG}/{REPO}/commit/{FULL_SHA}` or `https://github.com/{ORG}/{REPO}/blob/{REF}/{FILE_PATH}` | Derive org/repo from `git remote get-url origin`. If not GitHub-hosted, omit link |

## Encoding Rules

- **LQL filters:** URL-encode spaces (`%20`), quotes (`%22`), `>=` (`%3E%3D`), newlines (`%0A`). Timestamps in ISO 8601 UTC.
- **Metrics Explorer `pageState`:** JSON object URL-encoded as a query parameter value. Structure varies by metric type — use examples as guidance, not as a byte-for-byte contract.
- **Tier independence:** Tier 1 (MCP) and Tier 2 (gcloud CLI) produce the same URL output — the link always points to the Cloud Console view, regardless of which tool executed the query.

## Required Parameters and Fallback

| Type | Required Parameters | When Missing |
|------|-------------------|-------------|
| `logs` | project_id, LQL filter, start timestamp, end timestamp | Omit link, describe query in prose |
| `baseline_logs` | project_id, LQL filter, baseline start, baseline end | Omit link |
| `metrics` | project_id, metric_type, metric filter, start, end | Omit link |
| `trace` | project_id, trace_id | Omit link |
| `deployment` | project_id, service/deployment name, region or zone+cluster+namespace | Omit link, state deployment checked in prose |
| `source` | org, repo (from git remote), commit SHA or file path + ref | If not GitHub-hosted or remote unavailable, omit link |

## Validation Rule

Before emitting a link, verify the URL retains its filter and time range. If the constructed URL would open a generic landing page (Logs Explorer with no query, Metrics Explorer with no filter, Cloud Run with only the project), omit it and describe the evidence in prose. A bad link is worse than no link.

## Label Normalization

Use stable, human-readable labels. Labels must not contain raw LQL, full SHAs, or URL fragments.

| Type | Label Pattern | Example |
|------|--------------|---------|
| `logs` | "{Service} incident logs" | "checkout-service incident logs" |
| `baseline_logs` | "{Service} baseline logs" | "checkout-service baseline logs" |
| `metrics` | "{Service} {metric_name}" | "checkout-service error_count" |
| `trace` | "Trace {first_8_chars}" | "Trace a1b2c3d4" |
| `deployment` | "{Service} deploy history" | "checkout-service deploy history" |
| `source` | "Commit {first_7_chars}" or "{file_name}" | "Commit f4e8a12" or "CheckoutHandler.java" |

## Worked Examples

### logs

**Input:** project_id=`my-project`, LQL=`resource.type="k8s_container" AND resource.labels.container_name="checkout-service" AND severity>=ERROR`, start=`2026-03-09T14:00:00Z`, end=`2026-03-09T15:00:00Z`

**URL:** `https://console.cloud.google.com/logs/query;query=resource.type%3D%22k8s_container%22%20AND%20resource.labels.container_name%3D%22checkout-service%22%20AND%20severity%3E%3DERROR;timeRange=2026-03-09T14:00:00Z%2F2026-03-09T15:00:00Z?project=my-project`

**Formatted:** `[checkout-service incident logs](https://console.cloud.google.com/logs/query;query=...?project=my-project)`

### baseline_logs

**Input:** Same LQL as above, baseline window: start=`2026-03-08T14:00:00Z`, end=`2026-03-08T15:00:00Z`

**URL:** Same pattern as `logs`, with baseline timestamps substituted.

**Formatted:** `[checkout-service baseline logs](https://console.cloud.google.com/logs/query;query=...?project=my-project)`

### metrics

**Input:** project_id=`my-project`, metric_type=`logging.googleapis.com/log_entry_count`, filter=`resource.type="k8s_container" AND resource.labels.container_name="checkout-service"`, start/end as above

**URL:** `https://console.cloud.google.com/monitoring/metrics-explorer?project=my-project&pageState=%7B%22timeSeriesFilter%22%3A%7B%22filter%22%3A%22metric.type%3D%5C%22logging.googleapis.com%2Flog_entry_count%5C%22%20AND%20resource.labels.container_name%3D%5C%22checkout-service%5C%22%22%7D%7D`

**Formatted:** `[checkout-service error_count](https://console.cloud.google.com/monitoring/metrics-explorer?project=my-project&pageState=...)`

**Note:** `pageState` JSON structure is best-effort. The exact encoding may vary by browser and Console version. If the URL does not resolve to the intended metric view, omit it.

### trace

**Input:** project_id=`my-project`, trace_id=`a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6`

**URL:** `https://console.cloud.google.com/traces/list?project=my-project&tid=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6`

**Formatted:** `[Trace a1b2c3d4](https://console.cloud.google.com/traces/list?project=my-project&tid=a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6)`

### deployment (Cloud Run)

**Input:** project_id=`my-project`, region=`europe-west6`, service=`checkout-service`

**URL:** `https://console.cloud.google.com/run/detail/europe-west6/checkout-service/revisions?project=my-project`

**Formatted:** `[checkout-service deploy history](https://console.cloud.google.com/run/detail/europe-west6/checkout-service/revisions?project=my-project)`

### deployment (GKE)

**Input:** project_id=`my-project`, zone=`europe-west6-a`, cluster=`prod-cluster`, namespace=`default`, deployment=`checkout-service`

**URL:** `https://console.cloud.google.com/kubernetes/deployment/europe-west6-a/prod-cluster/default/checkout-service/overview?project=my-project`

**Formatted:** `[checkout-service deploy history](https://console.cloud.google.com/kubernetes/deployment/europe-west6-a/prod-cluster/default/checkout-service/overview?project=my-project)`

### source

**Input:** org=`my-org`, repo=`checkout-service`, commit=`f4e8a12b9c3d5e6f7a8b9c0d1e2f3a4b5c6d7e8f`

**URL:** `https://github.com/my-org/checkout-service/commit/f4e8a12b9c3d5e6f7a8b9c0d1e2f3a4b5c6d7e8f`

**Formatted:** `[Commit f4e8a12](https://github.com/my-org/checkout-service/commit/f4e8a12b9c3d5e6f7a8b9c0d1e2f3a4b5c6d7e8f)`
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/references/evidence-links.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add references/evidence-links.md with URL templates and encoding rules"
```

---

### Task 3: Extend YAML schema with `evidence_links`

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` (3 YAML blocks in Step 7 investigation_summary)
- Modify: `tests/test-incident-analysis-content.sh` (add assertions before `print_summary`)

- [ ] **Step 1: Write the test assertions**

Add to `tests/test-incident-analysis-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — evidence_links YAML schema in investigation_summary
# ---------------------------------------------------------------------------
HYPOTHESIS_BLOCK=$(sed -n '/^  chosen_hypothesis:/,/^  ruled_out:/p' "${SKILL_FILE}")
assert_contains "SKILL.md: evidence_links in chosen_hypothesis block" \
    "evidence_links:" "${HYPOTHESIS_BLOCK}"

INVESTIGATION_YAML=$(sed -n '/^investigation_summary:/,/^```$/p' "${SKILL_FILE}")
assert_contains "SKILL.md: evidence_links item shape has type field" \
    'type: "logs" | "baseline_logs" | "metrics" | "trace" | "deployment" | "source"' "${INVESTIGATION_YAML}"
assert_contains "SKILL.md: evidence_links item shape has label field" \
    'label: "<display text>"' "${INVESTIGATION_YAML}"
assert_contains "SKILL.md: evidence_links item shape has url field" \
    'url: "<https://...">' "${INVESTIGATION_YAML}"

RULED_OUT_BLOCK=$(sed -n '/^  ruled_out:/,/^  evidence_coverage:/p' "${SKILL_FILE}")
assert_contains "SKILL.md: evidence_links in ruled_out block" \
    "evidence_links:" "${RULED_OUT_BLOCK}"

SEI_BLOCK=$(sed -n '/^  service_error_inventory:/,/^  root_cause_layer_coverage:/p' "${SKILL_FILE}")
assert_contains "SKILL.md: evidence_links in service_error_inventory block" \
    "evidence_links:" "${SEI_BLOCK}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 6 FAIL for the new assertions

- [ ] **Step 3: Add `evidence_links` to `chosen_hypothesis` in SKILL.md**

In `skills/incident-analysis/SKILL.md`, find:

```yaml
    contradicting_evidence_found: "<what was found, or 'none'>"
  ruled_out:
```

Replace with:

```yaml
    contradicting_evidence_found: "<what was found, or 'none'>"
    evidence_links:  # optional — present only when valid URLs were captured
      - type: "logs" | "baseline_logs" | "metrics" | "trace" | "deployment" | "source"
        label: "<display text>"
        url: "<https://...>"
  ruled_out:
```

- [ ] **Step 4: Add `evidence_links` to `ruled_out` in SKILL.md**

Find:

```yaml
  ruled_out:
    - hypothesis: "<alternative>"
      reason: "<disconfirming evidence>"
  evidence_coverage:
```

Replace with:

```yaml
  ruled_out:
    - hypothesis: "<alternative>"
      reason: "<disconfirming evidence>"
      evidence_links:  # optional — present only when valid URLs were captured
        - type: "..."
          label: "..."
          url: "..."
  evidence_coverage:
```

- [ ] **Step 5: Add `evidence_links` to `service_error_inventory` in SKILL.md**

Find:

```yaml
      mechanism_status: "known" | "not_yet_traced" | "not_applicable"
  root_cause_layer_coverage:
```

Replace with:

```yaml
      mechanism_status: "known" | "not_yet_traced" | "not_applicable"
      evidence_links:  # optional — present only when valid URLs were captured
        - type: "..."
          label: "..."
          url: "..."
  root_cause_layer_coverage:
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All PASS

- [ ] **Step 7: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add evidence_links to chosen_hypothesis, ruled_out, and service_error_inventory"
```

---

### Task 4: Add Step 7 prose placement rule

**Files:**
- Modify: `skills/incident-analysis/SKILL.md` (Step 7 synthesis content list)
- Modify: `tests/test-incident-analysis-content.sh` (add assertions before `print_summary`)

- [ ] **Step 1: Write the test assertions**

Add to `tests/test-incident-analysis-content.sh` before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# SKILL.md — Step 7 evidence links prose placement
# ---------------------------------------------------------------------------
STEP7_BLOCK=$(sed -n '/### Step 7: Context Discipline/,/### Step 8/p' "${SKILL_FILE}")
assert_contains "SKILL.md: step 7 has evidence links item" \
    "Evidence links (Constraint 12)" "${STEP7_BLOCK}"
assert_contains "SKILL.md: step 7 evidence links mentions Links line" \
    "Links:" "${STEP7_BLOCK}"
assert_contains "SKILL.md: step 7 evidence links has omission behavior" \
    "Omit the" "${STEP7_BLOCK}"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: 3 FAIL for the new assertions

- [ ] **Step 3: Add item 8 to Step 7 synthesis content list**

In `skills/incident-analysis/SKILL.md`, find Step 7 item 7 (line 722):

```
7. **Evidence coverage and gaps:** Per-domain coverage assessment and explicit gap list (included in the structured block below)
```

Insert after it:

```markdown

8. **Evidence links (Constraint 12):** After the root cause statement in the prose synthesis, include a `**Links:**` line with up to 3 verification links. After each ruled-out hypothesis, include a `**Links:**` line with up to 2 verification links. Use markdown link syntax with ` · ` separator. Omit the `**Links:**` line entirely when no valid URLs are available for that block.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-incident-analysis-content.sh`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add skills/incident-analysis/SKILL.md tests/test-incident-analysis-content.sh
git commit -m "feat(incident-analysis): add Step 7 evidence links prose placement rule"
```

---

### Task 5: Add behavioral eval fixture and coverage pattern

**Files:**
- Modify: `tests/fixtures/incident-analysis/evals/behavioral.json` (append 1 new entry)
- Modify: `tests/test-incident-analysis-evals.sh` (add 1 coverage pattern)

- [ ] **Step 1: Update the eval coverage loop**

In `tests/test-incident-analysis-evals.sh`, find the `for behavior in` line (line 113):

```bash
for behavior in "exit.code.*triage\|crashloop.*exit" "evidence_coverage\|gaps" "rollback\|bad.release" "live.triage\|triage.*mode" "independent.*root.*cause\|attribution\|confirmed.dependent" "inconclusive\|not.investigated" "dual.layer\|app.*layer\|infra.*layer" "anchoring\|rank\|diagnostic.value" "baseline.*verif\|intermediate.*conclusion\|tier.*reclassif"; do
```

Replace with:

```bash
for behavior in "exit.code.*triage\|crashloop.*exit" "evidence_coverage\|gaps" "rollback\|bad.release" "live.triage\|triage.*mode" "independent.*root.*cause\|attribution\|confirmed.dependent" "inconclusive\|not.investigated" "dual.layer\|app.*layer\|infra.*layer" "anchoring\|rank\|diagnostic.value" "baseline.*verif\|intermediate.*conclusion\|tier.*reclassif" "evidence.link\|Links:.*\\·\|verification.*link"; do
```

- [ ] **Step 2: Run eval tests to verify new coverage check fails**

Run: `bash tests/test-incident-analysis-evals.sh`
Expected: 1 FAIL for the new behavior coverage pattern

- [ ] **Step 3: Add the new fixture to behavioral.json**

Read the current `tests/fixtures/incident-analysis/evals/behavioral.json`, then replace the closing `]` at the end of the file. Find:

```json
      {"text": "not.*dismiss|cannot.*assume|verify.*before", "description": "Does not accept baseline classification without evidence"}
    ]
  }
]
```

Replace with:

```json
      {"text": "not.*dismiss|cannot.*assume|verify.*before", "description": "Does not accept baseline classification without evidence"}
    ]
  },
  {
    "id": "evidence-links-in-synthesis",
    "prompt": "Two services behind a reverse proxy. checkout-service has Tier 1 NullPointerException errors at 20x baseline. payment-service has Tier 2 timeout errors at 3x baseline. checkout-service was deployed 2 hours before incident. Investigation uses Tier 1 MCP tools with project_id example-k8s-prod. Trace correlation links checkout-service failures to payment-service timeouts.",
    "expected_behavior": "The Step 7 synthesis must include a **Links:** line after the root cause statement with clickable Logs Explorer URLs for the incident-window query. The evidence_links YAML must include entries for at least the root-cause service's logs. service_error_inventory entries should have evidence_links when URL parameters were captured. Links must use stable labels like '{Service} incident logs', not raw LQL.",
    "assertions": [
      {"text": "Links:.*\\·|evidence_links|verification.*link", "description": "Includes evidence links in synthesis output with proper formatting"},
      {"text": "console\\.cloud\\.google\\.com/logs|Logs Explorer|logs/query", "description": "Generates Logs Explorer URLs for incident-window queries"},
      {"text": "incident logs|baseline logs|deploy history", "description": "Uses stable human-readable labels, not raw LQL or full URLs"},
      {"text": "evidence_links.*type.*logs|type.*logs.*label.*url", "description": "YAML evidence_links entries have the required type/label/url shape"}
    ]
  }
]
```

- [ ] **Step 4: Run eval tests to verify they pass**

Run: `bash tests/test-incident-analysis-evals.sh`
Expected: All PASS

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/incident-analysis/evals/behavioral.json tests/test-incident-analysis-evals.sh
git commit -m "feat(incident-analysis): add evidence-links-in-synthesis behavioral eval fixture"
```

---

### Task 6: Run full test suite and verify

**Files:**
- None (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All test files pass, 0 failures

- [ ] **Step 2: Verify SKILL.md structure**

Run: `bash tests/test-skill-content.sh`
Expected: All PASS (this file was not modified but validates overall SKILL.md structure)

- [ ] **Step 3: Verify reference file is discoverable**

Run: `ls skills/incident-analysis/references/evidence-links.md`
Expected: File exists

- [ ] **Step 4: Verify constraint numbering**

Run: `grep -n '### [0-9]' skills/incident-analysis/SKILL.md`
Expected: Constraints 1-12 with no gaps or duplicates

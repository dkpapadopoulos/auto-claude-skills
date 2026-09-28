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

## Tier Detection

Run the shared observability preflight before data access:

```bash
bash '<PLUGIN_ROOT>/scripts/obs-preflight.sh'
```

If `gcloud` is `unauthenticated`, run `gcloud auth login` before proceeding. If `gcloud` is `missing`, fall to Tier 3.

### Tier 1 — REST API via scripts (default for inventory and bulk)

Default path for all data pull. Uses `gcloud auth print-access-token` for auth, `curl` for requests, Python scripts for pagination and extraction. MCP truncates at ~100K characters and cannot handle monitoring projects with >50 policies — REST has no such limits.

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

#### Optional: SLO Config Enrichment

After pulling policies and incidents, attempt to fetch SLO service definitions from GitHub. This is optional enrichment — the core analysis runs without it.

**Preconditions:** `{github_org}` was provided in Stage 0 AND `gh` CLI is available AND authenticated (`gh auth status` succeeds). If any precondition fails, write fallback artifacts and skip.

**Flow:**

```bash
REPO="${github_org}/monitoring"

# Short-circuit if preconditions not met
if [ -z "${github_org:-}" ]; then
  echo '{"status":"unavailable","reason":"github_org_not_provided","count":0}' \
    > "$WORK_DIR/slo-source-status.json"
  echo '[]' > "$WORK_DIR/slo-services.json"
elif ! command -v gh &>/dev/null || ! gh auth status &>/dev/null 2>&1; then
  echo '{"status":"unavailable","reason":"gh_not_available","count":0}' \
    > "$WORK_DIR/slo-source-status.json"
  echo '[]' > "$WORK_DIR/slo-services.json"
else
  # Step 1: fetch (checked)
  if ! gh api "repos/$REPO/contents/tf/slo-config.yaml" \
       --jq '.content' > "$WORK_DIR/slo-raw-b64.txt" 2>"$WORK_DIR/slo-fetch-err.txt"; then
    echo '{"status":"unavailable","reason":"fetch_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  # Step 2: decode (checked)
  elif ! base64 -d < "$WORK_DIR/slo-raw-b64.txt" > "$WORK_DIR/slo-config.yaml" 2>/dev/null; then
    echo '{"status":"unavailable","reason":"decode_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  # Step 3: extract service names (checked — Ruby stdlib YAML, no PyYAML)
  elif ! ruby -ryaml -rjson -e '
    cfg = YAML.safe_load(File.read(ARGV[0])) || {}
    services = (cfg["services"] || []).map { |s| s["name"] }.compact
      .map { |n| n.downcase.gsub(/[_.]/, "-").gsub(/-(prod|staging|pta)$/, "") }
    File.write(ARGV[1], JSON.generate(services))
    File.write(ARGV[2], JSON.generate({
      status: services.empty? ? "empty" : "ok",
      count: services.length
    }))
  ' "$WORK_DIR/slo-config.yaml" "$WORK_DIR/slo-services.json" \
    "$WORK_DIR/slo-source-status.json" 2>"$WORK_DIR/slo-parse-err.txt"; then
    echo '{"status":"unavailable","reason":"parse_failed","count":0}' \
      > "$WORK_DIR/slo-source-status.json"
    echo '[]' > "$WORK_DIR/slo-services.json"
  fi
  rm -f "$WORK_DIR/slo-raw-b64.txt"
fi
```

**On-disk artifacts (always written, every branch):**
- `slo-services.json` — normalized service name list or `[]`
- `slo-source-status.json` — `{"status": "ok|empty|unavailable", "reason": "...", "count": N}`

Names in `slo-services.json` are normalized with the same rules as `service_key` in compute-clusters.py: lowercase, strip environment suffixes (`-prod`, `-staging`, `-pta`), replace separators (`_`, `.`) with `-`.

**Stage 1 report line addition:** `"{M} services with SLO definitions"` when status is `ok`, `"SLO config: {reason}"` otherwise.

#### Optional: IaC Module Discovery

After SLO enrichment, build a `display_name → file_path` mapping by walking the IaC repo tree via `gh api`. This replaces the previous `gh search code` approach, which returned zero results because GCP-generated policy IDs never appear in Terraform source.

**Preconditions:** `{github_org}` and `{iac_repos}` were provided in Stage 0 AND `gh` is available AND authenticated. If any fail, write fallback and skip.

**Why repo tree walk instead of `gh search code`:**
- Policy IDs are assigned at `terraform apply` time — they do not exist in `.tf` files, so searching for them always returns 0 results
- `gh search code` has a 10 req/min rate limit and frequently hits 403 on private orgs
- `gh api` (used here) has a 5,000 req/hour limit and works reliably on private repos
- The results are deterministic: if a `display_name` matches, the file path is confirmed

**Flow:**

For each repo in `{iac_repos}` that contains a `tf/` directory:

```bash
REPO="${github_org}/${iac_repo}"
IAC_DIR="$WORK_DIR/iac-discovery"
mkdir -p "$IAC_DIR"

# Step 1: List module directories
gh api "repos/$REPO/contents/tf/modules" --jq '.[].name' \
  > "$IAC_DIR/module-names.txt" 2>/dev/null

# Step 2: For each module, fetch the main TF file and extract display_name values
python3 -c "
import subprocess, json, re, os
repo = '$REPO'
iac_dir = '$IAC_DIR'
modules = open(f'{iac_dir}/module-names.txt').read().strip().split('\n')
mapping = {}
for mod in modules:
    # Try common TF file names in the module
    for fname in ['main.tf', 'google_monitoring_alert_policy.tf', f'{mod}.tf']:
        try:
            result = subprocess.run(
                ['gh', 'api', f'repos/{repo}/contents/tf/modules/{mod}/{fname}',
                 '--jq', '.content'],
                capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                continue
            import base64
            content = base64.b64decode(result.stdout.strip()).decode('utf-8')
            # Extract display_name values from TF
            for m in re.finditer(r'display_name\s*=\s*\"([^\"]+)\"', content):
                dn = m.group(1)
                # Skip condition display names (inside conditions {} blocks)
                # Only keep top-level policy display_name
                mapping[dn] = {
                    'repo': repo,
                    'module': mod,
                    'file': f'tf/modules/{mod}/{fname}',
                    'type': 'module_definition'
                }
            break  # Found file, stop trying alternatives
        except Exception:
            continue

# Step 3: Also scan squad directories for module invocations
try:
    result = subprocess.run(
        ['gh', 'api', f'repos/{repo}/contents/tf/squads', '--jq', '.[].name'],
        capture_output=True, text=True, timeout=10)
    squads = result.stdout.strip().split('\n') if result.returncode == 0 else []
except Exception:
    squads = []

for squad in squads:
    try:
        result = subprocess.run(
            ['gh', 'api', f'repos/{repo}/contents/tf/squads/{squad}',
             '--jq', '.[].name'],
            capture_output=True, text=True, timeout=10)
        files = [f for f in result.stdout.strip().split('\n')
                 if f.endswith('.tf')]
    except Exception:
        continue
    for fname in files:
        try:
            result = subprocess.run(
                ['gh', 'api',
                 f'repos/{repo}/contents/tf/squads/{squad}/{fname}',
                 '--jq', '.content'],
                capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                continue
            content = base64.b64decode(result.stdout.strip()).decode('utf-8')
            for m in re.finditer(r'display_name\s*=\s*\"([^\"]+)\"', content):
                dn = m.group(1)
                mapping[dn] = {
                    'repo': repo,
                    'module': squad,
                    'file': f'tf/squads/{squad}/{fname}',
                    'type': 'squad_definition'
                }
        except Exception:
            continue

# Step 4: Scan root-level .tf files for module invocations
try:
    result = subprocess.run(
        ['gh', 'api', f'repos/{repo}/contents/tf', '--jq', '.[].name'],
        capture_output=True, text=True, timeout=10)
    root_files = [f for f in result.stdout.strip().split('\n')
                  if f.endswith('.tf')]
except Exception:
    root_files = []

for fname in root_files:
    try:
        result = subprocess.run(
            ['gh', 'api', f'repos/{repo}/contents/tf/{fname}',
             '--jq', '.content'],
            capture_output=True, text=True, timeout=10)
        if result.returncode != 0:
            continue
        content = base64.b64decode(result.stdout.strip()).decode('utf-8')
        # Extract module invocations: module \"name\" { source = \"./modules/X\"
        for m in re.finditer(
            r'module\s+\"([^\"]+)\"\s*\{[^}]*source\s*=\s*\"([^\"]+)\"',
            content, re.DOTALL):
            mod_name = m.group(1)
            mod_source = m.group(2)
            # Store invocation location for modules we already know about
            mod_key = mod_source.split('/')[-1] if '/' in mod_source else mod_source
            for dn, info in mapping.items():
                if info['module'] == mod_key:
                    info['invocation_file'] = f'tf/{fname}'
    except Exception:
        continue

with open(f'{iac_dir}/iac-modules.json', 'w') as f:
    json.dump(mapping, f, indent=2)
with open(f'{iac_dir}/iac-status.json', 'w') as f:
    json.dump({'status': 'ok' if mapping else 'empty',
               'count': len(mapping)}, f)
print(f'Discovered {len(mapping)} display_name → file_path mappings')
"
```

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

**Flow:**

```bash
# Fetch CODEOWNERS (single gh api call)
gh api "repos/$REPO/contents/CODEOWNERS" --jq '.content' 2>/dev/null \
  | base64 -d > "$IAC_DIR/CODEOWNERS" 2>/dev/null
```

Then in Python:

```python
# Parse CODEOWNERS rules
codeowner_rules = []  # [(glob_pattern, [owners])]
for line in open(f'{iac_dir}/CODEOWNERS'):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    parts = line.split()
    codeowner_rules.append((parts[0], [p for p in parts[1:] if p.startswith('@')]))

def resolve_owner(filepath):
    """Last matching CODEOWNERS rule wins (git spec)."""
    matched = None
    for pattern, owners in codeowner_rules:
        # Convert CODEOWNERS glob to simple match
        if fnmatch.fnmatch(filepath, pattern) or filepath.startswith(pattern.rstrip('*')):
            matched = owners
    return matched

# For each entry in iac-modules.json:
# 1. Check if file is in tf/squads/{squad}/ → squad name is the owner
# 2. Else resolve via CODEOWNERS match on the file path
# 3. Store as 'suggested_owner' in the mapping
```

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

### Stage 2: Compute Cluster Stats

Run compute-clusters.py. This produces a structured output with three sections:

**Per-cluster fields (`clusters` array):**
- `raw_incidents`, `deduped_episodes`, `dedupe_window_sec`
- `distinct_resources`, `median_duration_sec`, `median_retrigger_sec`
- `total_open_hours` — sum of actual incident durations (openTime to closeTime) in hours. **MANDATORY source for all open-incident-hours figures in the report.** Do NOT compute open-hours ad-hoc from `raw * median_duration` — that formula is inaccurate in both directions (overstates retrigger clusters, understates chronic long-tail clusters). If this field is missing or 0 for a cluster, the installed script version may predate this feature — re-run with the local source script.
- `tod_pattern`, `pattern` (flapping/chronic/recurring/burst/isolated)
- `noise_score`, `noise_reasons`, `label_inconsistency`
- `threshold_value`, `comparison`, `condition_filter`, `condition_query`, `condition_type`, `condition_match`
- `service_key` (normalized service identity from condition labels, or null), `signal_family` (error_rate/latency/availability/other)

**Inventory-level fields:**
- `metric_types_in_inventory` — deduplicated set of all metric types across all policy conditions
- `unlabeled_ranking` — top 20 enabled policies without squad/team/owner label, ranked by total raw incidents

### Stage 3: Classify and Prescribe

Read the cluster stats JSON. For each cluster, apply the prescriptive reasoning templates below to assign a verdict and specific recommended action.

**Threshold-aware prescriptions:** When the cluster data includes `threshold_value` and `comparison`, state the current config explicitly in the per-item output: *"Current: {comparison} {threshold_value}, eval window {eval_window_sec}s, auto_close {auto_close_sec}s"*. Use the actual value in recommendations: *"Raise threshold from 0 to >1000"* not *"Raise threshold to >1000"*. When `condition_match` is `"ambiguous"`, note all threshold values and flag which one the recommendation applies to. When `condition_filter` or `condition_query` is available, include a truncated excerpt (≤60 chars) in the per-item output for reviewer auditability.

### Stage 3b: Targeted Metric Validation

For the **top 5 clusters by raw incidents** where the evidence basis would be "heuristic" (not "structural" — structural flaws like auto_close NOT SET don't need metric validation):

**Step 1 — Map PromQL metric names to Cloud Monitoring equivalents.**

Most PromQL conditions use metrics that ARE queryable via Cloud Monitoring under a mapped name:

| PromQL pattern | Cloud Monitoring equivalent | Example |
|---|---|---|
| `kubernetes_io:METRIC_PATH` | `kubernetes.io/METRIC_PATH` | `kubernetes_io:container_restart_count` → `kubernetes.io/container/restart_count` |
| `SERVICE_COM:METRIC` | `SERVICE.com/METRIC` | `dbinsights_googleapis_com:perquery_latencies` → `dbinsights.googleapis.com/perquery/latencies` |
| `METRIC_NAME` (custom) | `prometheus.googleapis.com/METRIC_NAME/SUFFIX` | `jvm_threads_live_threads` → `prometheus.googleapis.com/jvm_threads_live_threads/gauge` |
| `METRIC_NAME_count` (histogram _count) | `prometheus.googleapis.com/METRIC_NAME/histogram` | `http_server_duration_milliseconds_count` → `prometheus.googleapis.com/http_server_duration_milliseconds/histogram` (use `distributionValue.count` for request counts) |

For custom Prometheus metrics, the suffix depends on the metric type: try `/gauge` first, then `/counter`, `/summary`, `/histogram` if no data returns. **Important:** When PromQL references `METRIC_count` (the `_count` component of a histogram), the Cloud Monitoring equivalent is the parent histogram type (`/histogram`), NOT a separate `_count` metric. The request count is in the `distributionValue.count` field of the distribution result. If none return data, list metric descriptors with `filter=metric.type = starts_with("prometheus.googleapis.com/METRIC_PREFIX")` to find the actual suffix.

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

**Tier 2 query pattern** (uses session temp file per Behavioral Constraint 2):

```bash
WORK_DIR="${WORK_DIR:-$(mktemp -d /tmp/ah-XXXXXX)}"
FILTER_FILE=$(mktemp "$WORK_DIR/ts-filter-XXXXXX.txt")
cat > "$FILTER_FILE" << 'FILTER'
metric.type = "prometheus.googleapis.com/jvm_threads_live_threads/gauge"
AND metric.labels.container = "recommendation-service"
AND resource.labels.cluster = "example-cluster-prod"
FILTER

TOKEN=$(gcloud auth print-access-token)
FILTER_ENC=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(open(sys.argv[1]).read().strip().replace('\n', ' ')))" "$FILTER_FILE")

# Note: REDUCE_MAX for gauges; use REDUCE_SUM for counters per the table above
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/$PROJECT/timeSeries?filter=$FILTER_ENC&interval.startTime=${START_TIME}&interval.endTime=${END_TIME}&aggregation.alignmentPeriod=3600s&aggregation.perSeriesAligner=ALIGN_MAX&aggregation.crossSeriesReducer=REDUCE_MAX&pageSize=100000" \
  -o "$WORK_DIR/ts-result.json" ; rm -f "$FILTER_FILE"
```

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

| Metric kind | Approach | Example |
|---|---|---|
| **CUMULATIVE DISTRIBUTION** (e.g., perquery latencies) | `ALIGN_DELTA` extracts the delta distribution per period. Read `distributionValue.mean` for average latency and `distributionValue.count` for query volume. | `dbinsights.googleapis.com/perquery/latencies` + ALIGN_DELTA daily → mean latency per day |
| **Error rate ratios** (5xx / total) | Two queries: (1) filter by status label for errors, (2) unfiltered for total. Divide in Python. Write both results to `$WORK_DIR`. | Query with `metric.labels.status=starts_with("5")` for errors, without for total. Compute `error_count / total_count`. |
| **High-cardinality counters** (e.g., 1,000+ containers) | Use `aggregation.crossSeriesReducer=REDUCE_SUM` to aggregate across all series. Gives total restart rate without enumerating each container. | `kubernetes.io/container/restart_count` + ALIGN_DELTA 1h + REDUCE_SUM → total restarts/hour across all containers |
| **Histogram-based error rates** (e.g., `rate(metric_count{status=~"5.."}[5m])`) | When PromQL uses `_count` from a histogram metric (e.g., `http_server_duration_milliseconds_count`), the Cloud Monitoring equivalent is the `/histogram` type — NOT a separate `_count` metric. Query `prometheus.googleapis.com/METRIC_NAME/histogram` with `ALIGN_DELTA`. The `distributionValue.count` field gives the request count per period. For error-rate ratios: query with status label filter for 5xx (count = error volume), then without filter (count = total volume). Compute ratio from the two `count` sums. | `prometheus.googleapis.com/http_server_duration_milliseconds/histogram` + ALIGN_DELTA 1h → `distributionValue.count` per period. Two queries: with `http_status_code=~"5.."` for errors, without for total. |
| **Custom PromQL with no Cloud Monitoring equivalent** | Rare — most Prometheus metrics map via `prometheus.googleapis.com/METRIC/SUFFIX`. Try `/gauge`, `/counter`, `/summary`, `/histogram` suffixes. If none return data, list metric descriptors with `starts_with` filter. | `metricDescriptors?filter=metric.type = starts_with("prometheus.googleapis.com/METRIC_PREFIX")` |

**Tier 2 two-query ratio pattern** (error rate example):

```bash
WORK_DIR="${WORK_DIR:-$(mktemp -d /tmp/ah-XXXXXX)}"

# Query 1: error count (5xx)
FILTER_ERR=$(mktemp "$WORK_DIR/ts-err-XXXXXX.txt")
cat > "$FILTER_ERR" << 'FILTER'
metric.type = "prometheus.googleapis.com/http_server_requests_seconds_count/summary"
AND metric.labels.status = starts_with("5")
AND metric.labels.application = "SERVICE_NAME"
FILTER
# ... curl with crossSeriesReducer=REDUCE_SUM&pageSize=100000 to $WORK_DIR/ts-err-result.json

# Query 2: total count
FILTER_TOTAL=$(mktemp "$WORK_DIR/ts-total-XXXXXX.txt")
cat > "$FILTER_TOTAL" << 'FILTER'
metric.type = "prometheus.googleapis.com/http_server_requests_seconds_count/summary"
AND metric.labels.application = "SERVICE_NAME"
FILTER
# ... curl with crossSeriesReducer=REDUCE_SUM&pageSize=100000 to $WORK_DIR/ts-total-result.json

# Compute ratio
python3 -c "
import json
err = sum(float(pt['value']['doubleValue']) for s in json.load(open('$WORK_DIR/ts-err-result.json')).get('timeSeries',[]) for pt in s['points'] if 'doubleValue' in pt.get('value',{}))
total = sum(float(pt['value']['doubleValue']) for s in json.load(open('$WORK_DIR/ts-total-result.json')).get('timeSeries',[]) for pt in s['points'] if 'doubleValue' in pt.get('value',{}))
print(f'error_rate={err/total*100:.2f}% ({err:.0f}/{total:.0f})') if total > 0 else print('no data')
"
rm -f "$FILTER_ERR" "$FILTER_TOTAL"
```

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

### PromQL Change Spec Rules

- **Simple edits** (scalar threshold, window, auto_close): show exact current and proposed fragment
- **Complex edits** (multi-clause PromQL, aggregation changes): show full affected clause or precise change spec
- Never rely on blind copy-paste as the standard; aim for exact replacement guidance

### Metric Families by Finding Type

| Finding type | Primary metric | Guardrail metric |
|---|---|---|
| Noise tuning | Raw incidents or open-incident hours | Detection latency for real incidents |
| auto_close fixes | Median open duration | N/A when change cannot hide signal |
| Routing/ownership | Correct owner/channel coverage | No alert dropped during transition |
| Orphaned alerts | Explicit close/remove/route decision | N/A |
| Coverage gaps | Implementation milestone | N/A |

Guardrail thresholds must be derived from evidence, not arbitrary. Guardrail = N/A only when the change cannot plausibly hide a real signal.

### Contextual Action Links

Every Do Now and Investigate finding gets one `**Links:**` line directly after `**Notification Reach:**`. No links in Decision Summary, Needs Decision, Verification Scorecard, or Evidence Ledger. Max 3 links per finding, separator ` · `.

**Link construction** (see templates below for placement):

| Label | URL pattern | When |
|-------|-------------|------|
| Open policy | `https://console.cloud.google.com/monitoring/alerting/policies/{id}?project={monitoring_project}` | Concrete policy ID available |
| Open alert policies | `https://console.cloud.google.com/monitoring/alerting?project={monitoring_project}` | No concrete policy ID (fallback) |
| View IaC | `https://github.com/{org}/{repo}/blob/main/{file_path}` | IaC Location is Confirmed or Likely (direct file link from Stage 1 module discovery) |
| Browse IaC | `https://github.com/{org}/{repo}/tree/main/tf` | IaC Location is Search Required (link to TF directory for manual search) |
| Incident history | `https://console.cloud.google.com/monitoring/alerting/incidents?project={monitoring_project}` | Investigate only: next step is reviewing firing/timing patterns |
| Validate metric | `https://console.cloud.google.com/monitoring/metrics-explorer?project={monitoring_project}` | Investigate only: next step is metric validation AND report has enough query detail |

**Do Now:** Open policy + View IaC (or Browse IaC) (2 links). When an invocation file exists (threshold/label config separate from module definition), include both: View IaC (module) + View IaC (invocation) + Open policy (3 links).
**Investigate:** Open policy + View/Browse IaC + optional contextual third link (max 3). Omit third link if it would require inventing missing query details.
**Do not** embed URLs in `Policy ID` or `IaC Location` fields — keep those plain text.

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

### Two-Stage DoD Rules

- Stage 1 closes on hypothesis confirmed/refuted + explicit next action documented
- Stage 2 is a completely separate follow-up item with its own numeric, time-bounded outcome DoD
- This prevents mixing discovery work with delivery work in a single ticket

### Structurally Proven but Not-Yet-PR-Ready Items

Items with structural or measured evidence that fail the Do Now gate (e.g., missing IaC location, missing owner) land in Investigate with their full evidence preserved. The `To Upgrade` field states exactly which gate requirement is missing. Stage 1 for these items is not hypothesis validation — it is resolving the missing gate requirement (e.g., "locate IaC path," "assign owner"). Once resolved, the item can be promoted to Do Now in the next report cycle or follow-up.

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

### Needs Decision Rules

- Deadline is advisory — the report does not auto-execute changes
- Default Recommendation is guidance for the decision owner, not an ultimatum
- Every Needs Decision item must have a named owner, not a generic role

### Mandatory Needs Decision Triggers

The following Needs Decision items are mandatory when their trigger condition is met:

- **Silent Policy Cleanup:** If `silent_policy_total > 0` and `silent_policy_count / silent_policy_total > 0.5` (more than half of enabled policies had zero incidents in the analysis window), include a "Silent Policy Cleanup" Needs Decision item with exact counts from compute-clusters output.

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

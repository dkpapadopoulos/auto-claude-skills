#!/usr/bin/env bash
# test-alert-hygiene-skill-content.sh — SKILL.md behavioral contract assertions
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-alert-hygiene-skill-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/alert-hygiene/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# Situational detail lives in references/ (openspec/changes/skill-reattach-budget):
# each cell reads the file its passage now lives in, so a passage moved again, or
# dropped from the file the core points at, still fails.
REF_DIR="${PROJECT_ROOT}/skills/alert-hygiene/references"
_ref() { cat "${REF_DIR}/$1" 2>/dev/null; }
TEMPLATES_CONTENT="$(_ref report-templates.md)"
SKELETON_CONTENT="$(_ref report-skeleton.md)"
METRIC_REF_CONTENT="$(_ref metric-queries.md)"
SLO_REF_CONTENT="$(_ref slo-enrichment.md)"
IAC_REF_CONTENT="$(_ref iac-discovery.md)"
CODEOWNERS_REF_CONTENT="$(_ref codeowners-resolution.md)"

# --- Frontmatter ---
assert_contains "has name frontmatter" "name: alert-hygiene" "${SKILL_CONTENT}"
assert_contains "has description frontmatter" "description: Use when" "${SKILL_CONTENT}"

# --- Tier detection documented (REST first, MCP second) ---
assert_contains "tier 1 REST documented" "Tier 1" "${SKILL_CONTENT}"
assert_contains "REST is default" "REST API" "${SKILL_CONTENT}"
assert_contains "tier 2 MCP documented" "Tier 2" "${SKILL_CONTENT}"
assert_contains "MCP enrichment only" "enrichment" "${SKILL_CONTENT}"
assert_contains "temp file pattern" "mktemp" "${SKILL_CONTENT}"

# --- Analysis stages ---
assert_contains "pull policies stage" "pull-policies" "${SKILL_CONTENT}"
assert_contains "pull incidents stage" "pull-incidents" "${SKILL_CONTENT}"
assert_contains "compute clusters stage" "compute-clusters" "${SKILL_CONTENT}"

# --- Prescriptive reasoning ---
assert_contains "threshold recommendation" "threshold" "${SKILL_CONTENT}"
assert_contains "duration recommendation" "duration" "${SKILL_CONTENT}"
assert_contains "auto_close recommendation" "auto_close" "${SKILL_CONTENT}"

# --- Action-class grouped output (v3) ---
assert_contains "do now section" "Actionable Findings: Do Now" "${SKELETON_CONTENT}"
assert_contains "investigate section" "Actionable Findings: Investigate" "${SKELETON_CONTENT}"
assert_contains "needs decision section" "Needs Decision" "${SKILL_CONTENT}"
assert_contains "decision summary section" "Decision Summary" "${SKILL_CONTENT}"
assert_contains "systemic issues section" "Systemic Issues" "${SKILL_CONTENT}"

# --- Action types ---
assert_contains "tune action" "Tune the alert" "${SKILL_CONTENT}"
assert_contains "fix action" "Fix the underlying issue" "${SKILL_CONTENT}"
assert_contains "SLO redesign action" "Redesign around SLO" "${SKELETON_CONTENT}"
assert_contains "coverage action" "Add/extend coverage" "${SKELETON_CONTENT}"
assert_contains "no action" "No action" "${SKILL_CONTENT}"

# --- Label inconsistency check ---
assert_contains "label inconsistency" "label_inconsistency" "${SKILL_CONTENT}"

# --- Noise scoring ---
assert_contains "noise scoring" "noise_score" "${SKILL_CONTENT}"
assert_contains "pattern classification" "flapping" "${SKILL_CONTENT}"
assert_contains "pattern classification" "chronic" "${SKILL_CONTENT}"
assert_contains "pattern classification" "recurring" "${SKILL_CONTENT}"

# --- Coverage gap analysis ---
assert_contains "SSL cert coverage" "SSL" "${SKILL_CONTENT}"
assert_contains "probe failure coverage" "probe" "${SKILL_CONTENT}"
assert_contains "node pressure coverage" "node" "${SKILL_CONTENT}"

# --- Confidence levels ---
assert_contains "high confidence" "High" "${SKILL_CONTENT}"
assert_contains "low confidence inline flag" "Low" "${SKILL_CONTENT}"

# --- Report structure ---
assert_contains "frequency table" "frequency table" "${SKILL_CONTENT}"
assert_contains "prescriptive" "prescriptive" "${SKILL_CONTENT}"

# --- Do Now per-item template fields (v3) ---
assert_contains "policy ID field" "Policy ID:" "${TEMPLATES_CONTENT}"
assert_contains "target owner field" "Target Owner:" "${TEMPLATES_CONTENT}"
assert_contains "scope field" "Scope:" "${TEMPLATES_CONTENT}"
assert_contains "notification reach field" "Notification Reach:" "${TEMPLATES_CONTENT}"
assert_contains "current policy snapshot" "Current Policy Snapshot" "${TEMPLATES_CONTENT}"
assert_contains "iac location field" "IaC Location:" "${TEMPLATES_CONTENT}"
assert_contains "config diff table" "Configuration Diff" "${TEMPLATES_CONTENT}"
assert_contains "derivation column" "Derivation" "${TEMPLATES_CONTENT}"
assert_contains "pre-change evidence field" "Pre-change Evidence:" "${TEMPLATES_CONTENT}"
assert_contains "evidence basis field" "Evidence Basis:" "${TEMPLATES_CONTENT}"
assert_contains "outcome dod field" "Outcome DoD:" "${TEMPLATES_CONTENT}"
assert_contains "primary metric" "Primary:" "${TEMPLATES_CONTENT}"
assert_contains "guardrail metric" "Guardrail:" "${TEMPLATES_CONTENT}"
assert_contains "rollback signal field" "Rollback Signal:" "${TEMPLATES_CONTENT}"

# --- Investigate per-item template fields (v3) ---
assert_contains "hypothesis field" "Hypothesis:" "${TEMPLATES_CONTENT}"
assert_contains "stage 1 dod" "Stage 1 DoD" "${TEMPLATES_CONTENT}"
assert_contains "stage 2 follow-up" "Stage 2" "${TEMPLATES_CONTENT}"
assert_contains "to upgrade field" "To Upgrade:" "${TEMPLATES_CONTENT}"

# --- Needs Decision per-item template fields (v3) ---
assert_contains "decision required field" "Decision Required:" "${TEMPLATES_CONTENT}"
assert_contains "named decision owner" "Named Decision Owner:" "${TEMPLATES_CONTENT}"
assert_contains "deadline field" "Deadline:" "${TEMPLATES_CONTENT}"
assert_contains "default recommendation" "Default Recommendation:" "${TEMPLATES_CONTENT}"

# --- Do Now gate behavioral contract ---
assert_contains "do now gate" "Do Now Gate" "${SKILL_CONTENT}"
assert_contains "heuristic exclusion" "heuristic alone never qualifies for Do Now" "${SKILL_CONTENT}"
assert_contains "iac confirmed status" "Confirmed" "${SKILL_CONTENT}"
assert_contains "iac likely status" "Likely" "${SKILL_CONTENT}"
assert_contains "iac search required status" "Search Required" "${SKILL_CONTENT}"
assert_contains "iac unknown drops" "Unknown" "${SKILL_CONTENT}"
assert_contains "search req repo hint" "repo" "${SKILL_CONTENT}"
assert_contains "search req policy id" "policy ID" "${SKILL_CONTENT}"
assert_contains "search req display name hint" "display_name" "${SKILL_CONTENT}"
assert_contains "search req replacement guidance" "replacement guidance" "${SKILL_CONTENT}"

# --- Investigate behavioral contract ---
assert_contains "investigate structural evidence" "measured|structural|heuristic" "${TEMPLATES_CONTENT}"
assert_contains "two-stage dod rule" "Two-Stage DoD" "${SKILL_CONTENT}"
assert_contains "structurally proven gate-blocked" "Structurally Proven" "${SKILL_CONTENT}"

# --- Confidence/Readiness vocabulary ---
assert_contains "pr-ready readiness" "PR-Ready" "${SKILL_CONTENT}"
assert_contains "high stage 1 readiness" "High / Stage 1" "${SKILL_CONTENT}"
assert_contains "medium stage 1 readiness" "Medium / Stage 1" "${SKILL_CONTENT}"
assert_contains "decision pending readiness" "Decision Pending" "${SKILL_CONTENT}"

# --- Systemic Issues subsections ---
assert_contains "ownership routing debt" "Ownership/Routing Debt" "${SKILL_CONTENT}"
assert_contains "dead orphaned config" "Dead/Orphaned Config" "${SKILL_CONTENT}"
assert_contains "missing coverage" "Missing Coverage" "${SKILL_CONTENT}"
assert_contains "inventory health" "Inventory Health" "${SKILL_CONTENT}"

# --- Verification metric families ---
assert_contains "metric family noise" "Noise tuning" "${SKILL_CONTENT}"
assert_contains "metric family auto_close" "auto_close fixes" "${SKILL_CONTENT}"
assert_contains "metric family routing" "Routing/ownership" "${SKILL_CONTENT}"
assert_contains "finding-type-aligned outcome" "aligned to finding type" "${TEMPLATES_CONTENT}"

# --- Definitions additions ---
assert_contains "open-incident hours defined" "open-incident hours" "${SKILL_CONTENT}"

# --- Skill intro describes v3 action-class model ---
assert_contains "intro do now" "Do Now" "${SKILL_CONTENT}"
assert_contains "intro investigate" "Investigate" "${SKILL_CONTENT}"
assert_contains "intro needs decision" "Needs Decision" "${SKILL_CONTENT}"

# --- Report sections ---
assert_contains "definitions section" "Definitions" "${SKILL_CONTENT}"
assert_contains "action type legend" "Action Type Legend" "${SKILL_CONTENT}"
# --- Decision Summary table columns ---
assert_contains "summary category column" "Category" "${SKELETON_CONTENT}"
assert_contains "summary target owner column" "Target Owner" "${SKELETON_CONTENT}"
assert_contains "summary readiness column" "Confidence / Readiness" "${SKELETON_CONTENT}"
assert_contains "summary expected outcome column" "Primary Expected Outcome" "${SKELETON_CONTENT}"
assert_contains "summary next action column" "Next Action" "${SKELETON_CONTENT}"
assert_contains "summary cap rule" "8-12" "${SKELETON_CONTENT}"
assert_contains "summary selection rule" "non-empty category" "${SKELETON_CONTENT}"
assert_contains "summary anchor links" "linked to detailed section" "${SKELETON_CONTENT}"
assert_contains "keep section" "No Action Required" "${SKELETON_CONTENT}"
assert_contains "verification scorecard" "Verification Scorecard" "${SKELETON_CONTENT}"
assert_contains "global implementation standard" "Global Implementation Standard" "${SKELETON_CONTENT}"
assert_contains "every mutated field" "every mutated field" "${SKELETON_CONTENT}"
assert_contains "evidence coverage appendix" "Evidence Coverage" "${SKELETON_CONTENT}"
# The core restates the skeleton's rules, so they hold when the skeleton is not
# open (after a re-attach cut); see the Report Structure cells below.
assert_contains "core restates the summary cap" "capped at 8-12 rows" "${SKILL_CONTENT}"
assert_contains "core restates every-mutated-field verification" "verify every mutated field" "${SKILL_CONTENT}"

# --- Evidence basis methodology ---
assert_contains "measured evidence type" "measured" "${SKILL_CONTENT}"
assert_contains "heuristic evidence type" "heuristic" "${SKILL_CONTENT}"
assert_contains "key terms section" "Key Terms" "${SKILL_CONTENT}"

# --- Behavioral constraints ---
assert_contains "no checkpoint gate" "straight through" "${SKILL_CONTENT}"
assert_contains "scope restriction" "monitoring project" "${SKILL_CONTENT}"

# --- Step 0 validation guard ---
assert_contains "step 0 validation" "Stage 0" "${SKILL_CONTENT}"
assert_contains "fail early" "Fail early" "${SKILL_CONTENT}"

# --- New sections from terraform/routing/SLO refinements ---

# SLO enrichment in Stage 1
assert_contains "SKILL.md has SLO enrichment section" \
    "SLO Config Enrichment" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions slo-services.json artifact" \
    "slo-services.json" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions slo-source-status.json artifact" \
    "slo-source-status.json" "${SKILL_CONTENT}"
assert_contains "SLO enrichment script uses Ruby not PyYAML" \
    "ruby -ryaml -rjson" "${SLO_REF_CONTENT}"

# Routing validation in Stage 4
assert_contains "SKILL.md has routing validation section" \
    "Routing Validation" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions zero-channel policies" \
    "Zero-channel policies" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions unlabeled high-noise" \
    "ownership is implicit and unauditable" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions label inconsistency promotion" \
    "Label inconsistency promotion" "${SKILL_CONTENT}"

# SLO cross-reference in Stage 4
assert_contains "SKILL.md has SLO cross-reference section" \
    "SLO Coverage Cross-Reference" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions SLO migration candidates" \
    "SLO migration candidate" "${SKILL_CONTENT}"
assert_contains "SKILL.md gates SLO xref on signal_family" \
    "signal_family" "${SKILL_CONTENT}"
assert_contains "SKILL.md excludes other from SLO xref" \
    "exclude" "${SKILL_CONTENT}"

# IaC location resolution in Stage 5
assert_contains "SKILL.md has IaC search section" \
    "IaC Location Resolution" "${SKILL_CONTENT}"
assert_contains "SKILL.md warns against gh search code" \
    "Do not use" "${SKILL_CONTENT}"
assert_contains "SKILL.md explains policy IDs not in TF source" \
    "Policy IDs are GCP-generated" "${SKILL_CONTENT}"
assert_contains "SKILL.md mentions gh auth status precondition" \
    "gh auth status" "${SKILL_CONTENT}"

# --- Report quality improvements (v4) ---

# Investigate template: Proposed Config Diff
assert_contains "investigate proposed config diff" "Proposed Config Diff" "${SKILL_CONTENT}"
assert_contains "investigate proposed config diff (template)" "Proposed Config Diff" "${TEMPLATES_CONTENT}"
assert_contains "investigate gate blocker field" "Gate Blocker:" "${TEMPLATES_CONTENT}"

# Dead/Orphaned Config reads from script output
assert_contains "dead orphaned reads zero_channel_policies" "zero_channel_policies" "${SKELETON_CONTENT}"
assert_contains "dead orphaned reads disabled_but_noisy" "disabled_but_noisy_policies" "${SKELETON_CONTENT}"

# Inventory Health reads from script output
assert_contains "inventory health reads silent_policy_count" "silent_policy_count" "${SKELETON_CONTENT}"
assert_contains "inventory health reads silent_policy_total" "silent_policy_total" "${SKELETON_CONTENT}"
assert_contains "inventory health reads condition_type_breakdown" "condition_type_breakdown" "${SKELETON_CONTENT}"

# Mandatory Needs Decision trigger
assert_contains "mandatory needs decision triggers section" "Mandatory Needs Decision Triggers" "${SKILL_CONTENT}"
assert_contains "silent policy cleanup trigger" "Silent Policy Cleanup" "${SKILL_CONTENT}"

# --- Open-incident hours sourcing (v5) ---
assert_contains "total_open_hours field documented" "total_open_hours" "${SKILL_CONTENT}"
assert_contains "ad-hoc formula forbidden" "Do NOT compute open-hours ad-hoc" "${SKILL_CONTENT}"

# --- Metric validation query standardization (v5) ---
assert_contains "mandatory query params table" "Mandatory Query Parameters" "${SKILL_CONTENT}"
assert_contains "crossSeriesReducer in template" "crossSeriesReducer=REDUCE_MAX" "${METRIC_REF_CONTENT}"
assert_contains "pageSize 100000 in template" "pageSize=100000" "${METRIC_REF_CONTENT}"
assert_contains "REDUCE_MAX for gauges" "REDUCE_MAX" "${SKILL_CONTENT}"
assert_contains "REDUCE_SUM for counters" "REDUCE_SUM" "${SKILL_CONTENT}"
assert_contains "result quality gate" "Result Quality Gate" "${SKILL_CONTENT}"
assert_contains "point count check" "fewer than 50 points" "${SKILL_CONTENT}"
assert_contains "series count check" "exactly 1 series" "${SKILL_CONTENT}"
assert_contains "pagination check" "nextPageToken" "${SKILL_CONTENT}"
assert_contains "evidence block logging" "series count, point count" "${SKILL_CONTENT}"
assert_contains "insufficient sample basis" "insufficient sample" "${SKILL_CONTENT}"

# --- Moved situational detail: each reference carries its block -----------
assert_contains "metric reference maps histogram _count to /histogram" \
    "prometheus.googleapis.com/METRIC_NAME/histogram" "${METRIC_REF_CONTENT}"
assert_contains "metric reference has the two-query ratio template" \
    "Tier 2 two-query ratio pattern" "${METRIC_REF_CONTENT}"
assert_contains "IaC reference walks the repo tree with gh api" \
    "repos/{repo}/contents/tf/squads" "${IAC_REF_CONTENT}"
assert_contains "CODEOWNERS reference keeps last-match-wins" \
    "Last matching CODEOWNERS rule wins" "${CODEOWNERS_REF_CONTENT}"
assert_contains "templates reference has the link URL patterns" \
    "monitoring/alerting/policies/{id}?project={monitoring_project}" "${TEMPLATES_CONTENT}"

# --- The core sends the model to each file at the step that needs it --------
# _FENCE_AWK — awk rule tracking fenced code, shared by _section and
# _section_end: a fence opens with 3+ backticks or 3+ tildes and closes only on
# a line of the SAME character, at least as long, with nothing after it — so a
# ``` inside a ```` fence, or a ~~~ fence, does not end it. `fl` is the open
# fence's length (0 = outside a fence).
_FENCE_AWK='
        match($0, /^[[:space:]]*(```+|~~~+)/) {
            _m = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", _m)
            if (!fl) { fc = substr(_m, 1, 1); fl = length(_m) }
            else if (substr(_m, 1, 1) == fc && length(_m) >= fl && substr($0, RSTART + RLENGTH) ~ /^[[:space:]]*$/) fl = 0
        }'
# _section <heading-prefix> <level> — the section's text, up to the next
# heading of the same or a higher level, skipping fenced code.
_section() {
    LC_ALL=C awk -v h="$1" -v lv="$2" "${_FENCE_AWK}"'
        f && !fl && match($0, /^#+ /) && RLENGTH - 1 <= lv { exit }
        !f && index($0, h) == 1 { f = 1 }
        f { print }
    ' "${SKILL_FILE}"
}
STAGE1_TEXT="$(_section '### Stage 1: Pull Data' 3)"
STAGE3B_TEXT="$(_section '### Stage 3b: Targeted Metric Validation' 3)"
STAGE5_TEXT="$(_section '### Stage 5: Produce Report' 3)"
REPORT_TEXT="$(_section '## Report Structure' 2)"
ENRICH_TEXT="$(_section '### Stage 1 optional enrichment' 3)"
assert_contains "Stage 1 names where the optional enrichment steps are" \
    "### Stage 1 optional enrichment" "${STAGE1_TEXT}"
assert_contains "Stage 1 keeps the precondition-or-fallback rule" \
    "otherwise it writes its fallback artifacts and is skipped" "${STAGE1_TEXT}"
# What applies on every run, fallback included, is restated inside the window
# (the enrichment steps themselves sit past it).
assert_contains "Stage 1 names the SLO artifacts every run writes" \
    "Every run writes \`slo-services.json\` and \`slo-source-status.json\`" "${STAGE1_TEXT}"
assert_contains "Stage 1 says to run the SLO block, which writes them on every branch" \
    "run the SLO block in \`references/slo-enrichment.md\`" "${STAGE1_TEXT}"
assert_contains "Stage 1 names the IaC status artifact" "\`iac-discovery/iac-status.json\`" "${STAGE1_TEXT}"
assert_contains "Stage 1 keeps the report lines" \
    "(\`SLO config: {reason}\`, \`IaC discovery: {reason}\` when skipped)" "${STAGE1_TEXT}"
assert_contains "Stage 1 keeps the Target Owner priority" \
    "Target Owner is its squad label, else its \`tf/squads/{squad}/\` directory, else CODEOWNERS (say which), else \`⚠ assign\`" "${STAGE1_TEXT}"
for _f in slo-enrichment.md iac-discovery.md codeowners-resolution.md; do
    assert_contains "Stage 1 enrichment points at references/${_f}" "references/${_f}" "${ENRICH_TEXT}"
done
assert_contains "Stage 3b points at references/metric-queries.md" \
    "Read \`references/metric-queries.md\`" "${STAGE3B_TEXT}"
assert_contains "Stage 5 points at the report skeleton" "references/report-skeleton.md" "${STAGE5_TEXT}"
assert_contains "Stage 5 points at the report templates" "references/report-templates.md" "${STAGE5_TEXT}"
assert_contains "Report Structure: Read the templates before writing any finding" \
    "Before writing any finding, Read \`references/report-templates.md\`" "${REPORT_TEXT}"
assert_contains "Report Structure: Read the skeleton before writing the report" \
    "Before writing the report, Read \`references/report-skeleton.md\`" "${REPORT_TEXT}"
assert_contains "Report Structure restates the Investigate diff condition" \
    "Proposed Config Diff appears ONLY when evidence basis is" "${REPORT_TEXT}"
assert_contains "Report Structure restates the summary cap" "capped at 8-12 rows" "${REPORT_TEXT}"
assert_contains "Report Structure restates read-not-computed systemic data" \
    "never computed ad-hoc" "${REPORT_TEXT}"
assert_contains "Report Structure restates the Global Implementation Standard" \
    "Do Now opens with the Global Implementation Standard" "${REPORT_TEXT}"

# --- The rules survive a post-compaction re-attach --------------------------
# Claude Code re-attaches an invoked skill cut to its first ~20,000 characters,
# and this SKILL.md is still larger than that, so its gates and stop conditions
# lead the core and must end inside the first 19,500 bytes (the re-attach
# budget). A section ends where the next heading of the same or a higher level
# begins, or at its stop line; a `# comment` inside a fenced code block is not a
# heading.
REATTACH_BYTES=19500
# _section_end <start-prefix> <level> [stop-prefix] [file] — byte offset where
# the span ends.
_section_end() {
    LC_ALL=C awk -v h="$1" -v lv="$2" -v s="${3:-}" "${_FENCE_AWK}"'
        f && !fl && match($0, /^#+ /) && RLENGTH - 1 <= lv { print n; done = 1; exit }
        f && !fl && s != "" && index($0, s) == 1 { print n; done = 1; exit }
        !f && index($0, h) == 1 { f = 1 }
        { n += length($0) + 1 }
        END { if (f && !done) print n }
    ' "${4:-${SKILL_FILE}}"
}
# Controls: a fenced `# comment` inside a section does not end it, for each
# fence shape. The expected end is the next real heading's byte offset, read
# independently with grep -b.
_fence_doc="$(mktemp)"
while IFS='|' read -r _shape _open _inner _close; do
    [ -n "${_shape}" ] || continue
    if [ -n "${_inner}" ]; then
        printf '%s\n' '# T' '' '### Stage 2: X' 'text' "${_open}" "${_inner}" '# a comment' 'echo hi' '```' "${_close}" 'more' '### Stage 3: Y' 'tail' > "${_fence_doc}"
    else
        printf '%s\n' '# T' '' '### Stage 2: X' 'text' "${_open}" '# a comment' 'echo hi' "${_close}" 'more' '### Stage 3: Y' 'tail' > "${_fence_doc}"
    fi
    _fence_want="$(grep -b -m1 '^### Stage 3: Y' "${_fence_doc}" | cut -d: -f1)"
    assert_equals "control: a # comment in a ${_shape} fence does not end a section early" \
        "${_fence_want}" "$(_section_end '### Stage 2: ' 3 '' "${_fence_doc}")"
done <<'FENCES'
backtick|```bash||```
tilde|~~~bash||~~~
four-backtick holding a ``` block|````markdown|```bash|````
FENCES
rm -f "${_fence_doc}"
while IFS='|' read -r _h _lv _stop _label; do
    [ -n "${_h}" ] || continue
    _end="$(_section_end "${_h}" "${_lv}" "${_stop}")"
    case "${_end}" in
        ''|*[!0-9]*)
            _record_fail "${_label} ends within the first ${REATTACH_BYTES} bytes" "'${_h}' not found" ;;
        *)
            if [ "${_end}" -le "${REATTACH_BYTES}" ]; then
                _record_pass "${_label} ends within the first ${REATTACH_BYTES} bytes (byte ${_end})"
            else
                _record_fail "${_label} ends within the first ${REATTACH_BYTES} bytes" \
                    "it ends at byte ${_end}, past the re-attach cut — move situational detail below it"
            fi ;;
    esac
done <<'SECTIONS'
## Behavioral Constraints|2||Behavioral Constraints
## Confidence Levels and Readiness|2||Confidence Levels and Readiness
## Report Structure|2||Report Structure (Do Now Gate through the report rules)
## Tier Detection|2||Tier Detection (obs-preflight first)
### Stage 0: Validate Data Access|3||Stage 0 (fail early)
### Stage 1: Pull Data|3||Stage 1 (counts; enrichment precondition-or-fallback, artifacts, report lines, owner priority)
### Stage 2: Compute Cluster Stats|3||Stage 2 (total_open_hours is mandatory)
### Stage 3: Classify and Prescribe|3||Stage 3 (threshold-aware prescriptions)
**Mandatory Query Parameters|3|**Step 3 |Stage 3b Mandatory Query Parameters
**Result Quality Gate|3|**Step 4 |Stage 3b Result Quality Gate
SECTIONS

# --- References index: every references/*.md is named from SKILL.md ---------
# A file the core never names is never Read, and a named file must exist.
_refs_n=0
for _f in "${REF_DIR}"/*.md; do
    [ -f "${_f}" ] || continue
    _refs_n=$((_refs_n + 1))
    assert_contains "SKILL.md names references/$(basename "${_f}")" \
        "references/$(basename "${_f}")" "${SKILL_CONTENT}"
done
assert_equals "references/ holds the six moved files" "6" "${_refs_n}"
for _named in $(grep -oE 'references/[A-Za-z0-9_-]+\.md' "${SKILL_FILE}" | sort -u); do
    assert_file_exists "named ${_named} exists" "$(dirname "${SKILL_FILE}")/${_named}"
done

print_summary

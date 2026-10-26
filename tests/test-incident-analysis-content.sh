#!/usr/bin/env bash
# test-incident-analysis-content.sh — Validates incident-analysis skill content
# contains expected diagnostic patterns (Scoutflo adoption).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-incident-analysis-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md"
SCHEMA_FILE="${PROJECT_ROOT}/skills/incident-analysis/references/investigation-schema.md"
EVIDENCE_LINKS_REF="${PROJECT_ROOT}/skills/incident-analysis/references/evidence-links.md"
SIGNALS_FILE="${PROJECT_ROOT}/skills/incident-analysis/signals.yaml"
PLAYBOOK_DIR="${PROJECT_ROOT}/skills/incident-analysis/playbooks"
# Situational detail moved out of SKILL.md so its rules fit the post-compaction
# re-attach window (openspec/changes/skill-reattach-budget). A cell whose needle
# lived in a moved block reads the file the block now lives in.
REF_DIR="${PROJECT_ROOT}/skills/incident-analysis/references"
STAGE_FLOW_REF="${REF_DIR}/stage-flow.md"
TEMPFILE_REF="${REF_DIR}/temp-file-pattern.md"
ACCESS_GATE_REF="${REF_DIR}/access-gate.md"
DB_METRICS_REF="${REF_DIR}/db-metrics-gate.md"
SWEEP_REF="${REF_DIR}/multi-service-sweep.md"
PM_FIELDS_REF="${REF_DIR}/postmortem-fields.md"
RATIONALE_REF="${REF_DIR}/rationale.md"
# The files this split created; the negative checks below scan them too.
MOVED_REFS="${STAGE_FLOW_REF} ${TEMPFILE_REF} ${ACCESS_GATE_REF} ${DB_METRICS_REF} ${SWEEP_REF} ${PM_FIELDS_REF} ${RATIONALE_REF}"

# ---------------------------------------------------------------------------
# Helper: assert file contains pattern (grep -q wrapper)
# ---------------------------------------------------------------------------
assert_file_contains() {
    local description="$1"
    local pattern="$2"
    local file="$3"

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "pattern '${pattern}' not found in $(basename "${file}")"
    fi
}

# ---------------------------------------------------------------------------
# SKILL.md — Exit code taxonomy
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has exit code taxonomy" "exit code" "${SKILL_FILE}"
assert_file_contains "SKILL.md: exit code 137 OOMKilled" "137" "${SKILL_FILE}"
assert_file_contains "SKILL.md: exit code 139 SIGSEGV" "139" "${SKILL_FILE}"
assert_file_contains "SKILL.md: exit code 143 SIGTERM" "143" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# references/error-taxonomy.md — Extracted taxonomy and exit codes
# ---------------------------------------------------------------------------
ERROR_TAXONOMY_REF="${PROJECT_ROOT}/skills/incident-analysis/references/error-taxonomy.md"
assert_file_exists "references/error-taxonomy.md exists" "${ERROR_TAXONOMY_REF}"
assert_file_contains "error-taxonomy ref: has tier table" "Tier.*Type.*Diagnostic value" "${ERROR_TAXONOMY_REF}"
assert_file_contains "error-taxonomy ref: has exit code table" "Exit Code.*Signal.*Meaning" "${ERROR_TAXONOMY_REF}"
assert_file_contains "error-taxonomy ref: mentions poison-pill" "poison.pill" "${ERROR_TAXONOMY_REF}"
assert_file_contains "error-taxonomy ref: baseline verification rule" "not evidence.*query the baseline" "${ERROR_TAXONOMY_REF}"

DEEP_DIVE_REF="${PROJECT_ROOT}/skills/incident-analysis/references/deep-dive-branches.md"

# ---------------------------------------------------------------------------
# SKILL.md — CrashLoopBackOff triage branch (pointer in SKILL.md, detail in ref)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has crashloop triage branch" "CrashLoopBackOff triage" "${SKILL_FILE}"
assert_file_contains "SKILL.md: crashloop checks previous container logs" "previous" "${SKILL_FILE}"
assert_file_contains "SKILL.md: crashloop checks termination reason" "[Tt]ermination reason" "${SKILL_FILE}"
assert_file_contains "SKILL.md: crashloop checks rollout history" "rollout history" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Probe/startup-envelope checks (pointer in SKILL.md, detail in ref)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has probe checks branch" "startup-envelope" "${SKILL_FILE}"
assert_file_contains "deep-dive ref: probe checks initialDelaySeconds" "initialDelaySeconds" "${DEEP_DIVE_REF}"
assert_file_contains "deep-dive ref: probe checks timeoutSeconds" "timeoutSeconds" "${DEEP_DIVE_REF}"
assert_file_contains "deep-dive ref: probe checks dependency reachability" "[Dd]ependency reachability" "${DEEP_DIVE_REF}"

# ---------------------------------------------------------------------------
# SKILL.md — Pod-start failure branch (pointer in SKILL.md, detail in ref)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has pod-start failure branch" "Pod-start failure" "${SKILL_FILE}"
assert_file_contains "SKILL.md: pod-start mentions ImagePullBackOff" "ImagePullBackOff" "${SKILL_FILE}"
assert_file_contains "SKILL.md: pod-start mentions CreateContainerConfigError" "CreateContainerConfigError" "${SKILL_FILE}"
assert_file_contains "deep-dive ref: pod-start mentions imagePullSecrets" "imagePullSecrets" "${DEEP_DIVE_REF}"

# ---------------------------------------------------------------------------
# references/deep-dive-branches.md — Extracted conditional branches
# ---------------------------------------------------------------------------
assert_file_exists "references/deep-dive-branches.md exists" "${DEEP_DIVE_REF}"
assert_file_contains "deep-dive ref: has crashloop triage" "CrashLoopBackOff" "${DEEP_DIVE_REF}"
assert_file_contains "deep-dive ref: has probe checks" "initialDelaySeconds" "${DEEP_DIVE_REF}"
assert_file_contains "deep-dive ref: has pod-start failure" "ImagePullBackOff" "${DEEP_DIVE_REF}"
assert_file_contains "deep-dive ref: has imagePullSecrets check" "imagePullSecrets" "${DEEP_DIVE_REF}"

# ---------------------------------------------------------------------------
# SKILL.md — Capacity/baseline overlay
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has capacity headroom check" "[Cc]apacity headroom" "${SKILL_FILE}"
assert_file_contains "SKILL.md: capacity mentions HPA" "HPA" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Restart gating: triage must precede restart candidacy
# ---------------------------------------------------------------------------
# The CrashLoopBackOff triage branch must appear in INVESTIGATE Step 3
# AND must state that workload-restart is only a candidate after triage.
investigate_section="$(sed -n '/^## Stage 2 — INVESTIGATE/,/^## Stage 3/p' "${SKILL_FILE}")"

# 1. Triage branch exists in INVESTIGATE
crashloop_line="$(echo "${investigate_section}" | grep -n "CrashLoopBackOff triage" | head -1 | cut -d: -f1)"
if [ -n "${crashloop_line}" ] && [ "${crashloop_line}" -gt 0 ] 2>/dev/null; then
    _record_pass "SKILL.md: CrashLoopBackOff triage is in INVESTIGATE stage"
else
    _record_fail "SKILL.md: CrashLoopBackOff triage is in INVESTIGATE stage" "not found in INVESTIGATE section"
fi

# 2. Triage branch references the workload-restart investigation_steps gate
assert_file_contains "SKILL.md: triage references workload-restart investigation_steps" \
    "workload-restart.*investigation_steps" "${SKILL_FILE}"

# 3. workload-restart.yaml has a Restart Decision Gate section
assert_file_contains "workload-restart.yaml: has restart decision gate" \
    "Restart Decision Gate" "${PLAYBOOK_DIR}/workload-restart.yaml"

# 4. The gate explicitly blocks restart for OOMKilled (exit 137)
assert_file_contains "workload-restart.yaml: gate blocks restart for OOMKilled" \
    "137.*OOMKilled" "${PLAYBOOK_DIR}/workload-restart.yaml"

# ---------------------------------------------------------------------------
# Routing — pod-start symptoms reach incident-analysis
# ---------------------------------------------------------------------------
TRIGGERS_FILE="${PROJECT_ROOT}/config/default-triggers.json"
if [ -f "${TRIGGERS_FILE}" ]; then
    assert_file_contains "triggers: ImagePullBackOff routes to incident-analysis" \
        "image.pull" "${TRIGGERS_FILE}"
    assert_file_contains "triggers: CreateContainerConfigError routes to incident-analysis" \
        "create.?container.?config" "${TRIGGERS_FILE}"
fi

# ---------------------------------------------------------------------------
# signals.yaml — New signals present
# ---------------------------------------------------------------------------
assert_file_contains "signals.yaml: has image_pull_failure" "image_pull_failure" "${SIGNALS_FILE}"
assert_file_contains "signals.yaml: has config_error_detected" "config_error_detected" "${SIGNALS_FILE}"
assert_file_contains "signals.yaml: has kubelet_not_running" "kubelet_not_running" "${SIGNALS_FILE}"

# ---------------------------------------------------------------------------
# workload-restart.yaml — Has investigation_steps with crashloop triage
# ---------------------------------------------------------------------------
WR_FILE="${PLAYBOOK_DIR}/workload-restart.yaml"
assert_file_contains "workload-restart.yaml: has investigation_steps" "investigation_steps" "${WR_FILE}"
assert_file_contains "workload-restart.yaml: investigation mentions termination reason" "[Tt]ermination" "${WR_FILE}"
assert_file_contains "workload-restart.yaml: investigation mentions previous logs" "previous" "${WR_FILE}"
assert_file_contains "workload-restart.yaml: investigation mentions exit code" "exit code" "${WR_FILE}"
assert_file_contains "workload-restart.yaml: investigation mentions rollout history" "rollout" "${WR_FILE}"

# ---------------------------------------------------------------------------
# infra-failure.yaml — Node discrimination checks
# ---------------------------------------------------------------------------
IF_FILE="${PLAYBOOK_DIR}/infra-failure.yaml"
assert_file_contains "infra-failure.yaml: mentions node conditions" "[Cc]ondition" "${IF_FILE}"
assert_file_contains "infra-failure.yaml: mentions kubelet logs" "kubelet" "${IF_FILE}"
assert_file_contains "infra-failure.yaml: mentions runtime health" "[Rr]untime" "${IF_FILE}"
assert_file_contains "infra-failure.yaml: mentions connectivity" "[Cc]onnectivity" "${IF_FILE}"
assert_file_contains "infra-failure.yaml: mentions certificate" "[Cc]ertificate" "${IF_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Access Gate (Step 1b)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has access gate step" "Access Gate" "${SKILL_FILE}"
assert_file_contains "access-gate ref: access summary checks gcloud auth" "gcloud auth:" "${ACCESS_GATE_REF}"
assert_file_contains "access-gate ref: access summary checks kubectl context" "kubectl context:" "${ACCESS_GATE_REF}"
assert_file_contains "SKILL.md: access gate prompts user to fix" "Fix now.*proceed with degraded" "${SKILL_FILE}"
assert_file_contains "SKILL.md: access gate records state for synthesis" "evidence_coverage" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Evidence coverage and gaps (Step 7)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: synthesis includes evidence coverage" "Evidence coverage and gaps" "${SKILL_FILE}"
assert_file_contains "SKILL.md: has evidence_coverage block" "evidence_coverage:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: has gaps block" "gaps:" "${SKILL_FILE}"
# This needle only ever matched the access summary's domain lines, now in the
# reference; the Step 7 table that defines the levels is asserted row by row.
assert_file_contains "access-gate ref: domains carry the coverage levels" "complete.*partial.*unavailable" "${ACCESS_GATE_REF}"
for _lvl in complete partial skipped unavailable; do
    assert_file_contains "SKILL.md: Step 7 defines coverage level ${_lvl}" "^| \`${_lvl}\` |" "${SKILL_FILE}"
done
assert_file_contains "SKILL.md: gap recording rules" "Record a gap for" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Completeness gate references evidence coverage
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: access gate does not block on unfixable gaps" \
    "Do not block.*unfixable" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate references evidence coverage" "evidence_coverage.*block" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate requires gap-aware answers" "what could change the answer" "${SKILL_FILE}"
assert_file_contains "SKILL.md: confident yes impossible with missing domain" \
    "confident.*yes.*not possible.*relevant domain" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Aggregate-first error fingerprinting (Step 3b)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has aggregate fingerprint step" "Aggregate.*[Ff]ingerprint" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions error distribution" "error distribution" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions dominant bucket" "dominant.*bucket" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions sample-biased warning" "sample.biased" "${SKILL_FILE}"
assert_file_contains "SKILL.md: aggregate mentions exemplar reads" "exemplar" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Evidence ledger (Constraint 6)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has evidence ledger constraint" "[Ee]vidence [Ll]edger" "${SKILL_FILE}"
assert_file_contains "SKILL.md: ledger has freshness semantics" "freshness" "${SKILL_FILE}"
assert_file_contains "SKILL.md: ledger excludes EXECUTE recheck" "always re-query" "${SKILL_FILE}"
assert_file_contains "SKILL.md: ledger labels reused evidence" "reused" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Live-triage mode
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has live-triage mode" "[Ll]ive.triage" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage is opt-in" "opt.in\|explicit" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage has non-blocking access" "non.blocking\|[Nn]on-blocking" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage has light inventory" "[Ll]ight inventory" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage defers deep inventory" "[Dd]efer.*deep\|[Dd]eep.*defer" "${SKILL_FILE}"
assert_file_contains "SKILL.md: live-triage preserves safety" "fingerprint recheck\|completeness gate\|safety" "${SKILL_FILE}"
assert_file_contains "SKILL.md: full investigation is default" "[Dd]efault.*[Ff]ull\|[Ff]ull.*[Dd]efault" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Canonical summary schema (Step 7)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: summary has structured block" "investigation_summary:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: summary schema has scope" "scope:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: summary schema has dominant_errors" "dominant_errors:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: summary schema has chosen_hypothesis" "chosen_hypothesis:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: summary schema has ruled_out" "ruled_out:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: summary schema has recovery_status" "recovery_status:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: summary schema has open_questions" "open_questions:" "${SCHEMA_FILE}"

# ---------------------------------------------------------------------------
# bad-release-rollback.yaml — Disambiguation probe
# ---------------------------------------------------------------------------
assert_file_contains "bad-release-rollback.yaml: has disambiguation probe" \
    "disambiguation_probe" "${PLAYBOOK_DIR}/bad-release-rollback.yaml"
assert_file_contains "bad-release-rollback.yaml: probe resolves error_pattern_predates_deploy" \
    "error_pattern_predates_deploy" "${PLAYBOOK_DIR}/bad-release-rollback.yaml"

# ---------------------------------------------------------------------------
# node-resource-exhaustion.yaml — Enhanced checks
# ---------------------------------------------------------------------------
NRE_FILE="${PLAYBOOK_DIR}/node-resource-exhaustion.yaml"
assert_file_contains "node-resource-exhaustion.yaml: mentions kubelet cert" "[Cc]ertificate" "${NRE_FILE}"
assert_file_contains "node-resource-exhaustion.yaml: mentions runtime health" "[Rr]untime" "${NRE_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Completeness gate Q10 (multi-service attribution)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: completeness gate has Q10" \
    "| 10 |" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Q10 mentions attribution verification" \
    "attribution\|independently\|error.*match" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — service_attribution in investigation_summary YAML
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: summary schema has service_attribution" \
    "service_attribution:" "${SCHEMA_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Per-Service Attribution Proof in Step 5
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has per-service attribution proof" \
    "Per-Service Attribution Proof\|Per-service attribution" "${SKILL_FILE}"
assert_file_contains "SKILL.md: attribution has four-state model" \
    "confirmed-dependent.*independent.*inconclusive.*not-investigated" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Application-logic analysis in Step 3
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: Step 3 has call pattern analysis" \
    "[Cc]all pattern" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Step 3 mentions N+1 or sequential fan-out" \
    "N+1\|sequential fan.out\|sequential.*permission" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Step 3 mentions gRPC connection analysis" \
    "peer.address\|connection pinning\|gRPC.*caller.*skew" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — No speculative language in routing heuristics
# ---------------------------------------------------------------------------
# The infrastructure escalation paragraph must not use "likely" as a conclusion
investigate_section="$(sed -n '/^## Stage 2 — INVESTIGATE/,/^## EXECUTE/p' "${SKILL_FILE}")"
# The INVESTIGATE detail moved to references/ is held to the same rule.
investigate_section="${investigate_section}
$(cat "${DB_METRICS_REF}" "${SWEEP_REF}" 2>/dev/null)"
if echo "${investigate_section}" | grep -q "root cause is likely"; then
    _record_fail "SKILL.md: no speculative 'likely' in infrastructure escalation" \
        "found 'root cause is likely' in INVESTIGATE section"
else
    _record_pass "SKILL.md: no speculative 'likely' in infrastructure escalation"
fi

# ---------------------------------------------------------------------------
# SKILL.md — Evidence-Only Attribution constraint (Constraint 7)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has evidence-only attribution constraint" \
    "Evidence-Only Attribution" "${SKILL_FILE}"
assert_file_contains "SKILL.md: forbids speculative language in synthesis" \
    "likely.*prohibited\|prohibited.*likely\|forbidden.*likely\|likely.*forbidden" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — MCP Result Processing constraint (Constraint 8)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has MCP result processing constraint" \
    "MCP Result Processing" "${SKILL_FILE}"
assert_file_contains "SKILL.md: forbids reading tool-results files" \
    "Never read.*tool-results" "${SKILL_FILE}"
assert_file_contains "SKILL.md: disambiguates from Evidence Ledger" \
    "Evidence Ledger.*Constraint 6" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Completeness gate Q11 (multi-service sweep)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: completeness gate has Q11" \
    "| 11 |" "${SKILL_FILE}"
assert_file_contains "SKILL.md: Q11 references service_error_inventory" \
    "service_error_inventory.*Step 3c" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Recurring-workload correlation trap (Step 5)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has recurring-workload correlation trap" \
    "Recurring-workload correlation trap" "${SKILL_FILE}"
assert_file_contains "SKILL.md: recurring trap requires previous-cycle check" \
    "previous cycle" "${SKILL_FILE}"
assert_file_contains "SKILL.md: recurring trap is a hard gate" \
    "hard gate.*MUST NOT.*root cause trigger" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Multi-Service Error Sweep (Step 3c)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has multi-service error sweep step" \
    "Multi-Service Error Sweep" "${SKILL_FILE}"
assert_file_contains "multi-service-sweep ref: step 3c has service_error_inventory output" \
    "service_error_inventory:" "${SWEEP_REF}"
assert_file_contains "SKILL.md: step 3c requires 72-hour deployment history" \
    "72-hour deployment history" "${SKILL_FILE}"
assert_file_contains "SKILL.md: step 3c warns against anchoring bias" \
    "Do not anchor" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Message broker signals and baseline verification
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: message broker signals are Tier 1" \
    "Message broker signals.*always Tier 1" "${SKILL_FILE}"
assert_file_contains "error-taxonomy ref: message broker mentions poison-pill" \
    "poison.pill" "${ERROR_TAXONOMY_REF}"
assert_file_contains "SKILL.md: Tier 3 requires verified baseline" \
    "verified baseline" "${SKILL_FILE}"
assert_file_contains "error-taxonomy ref: Tier 3 forbids unverified dismissal" \
    "not evidence.*query the baseline" "${ERROR_TAXONOMY_REF}"

# ---------------------------------------------------------------------------
# SKILL.md — Intermediary-Layer Investigation Discipline (Constraint 9)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has intermediary-layer constraint" \
    "Intermediary-Layer Investigation" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 9 requires downstream sweep" \
    "query every distinct downstream service" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 9 has scope boundary" \
    "bounded to services explicitly named" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Dual-Layer Investigation (Constraint 10)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has dual-layer investigation constraint" \
    "Dual-Layer Investigation" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 10 requires both layers" \
    "infrastructure layer.*application layer\|application layer.*infrastructure layer" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 10 defines mechanism_status" \
    "mechanism.status.*known.*not_yet_traced" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 10 requires mechanism for root cause" \
    "chosen root-cause service.*must trace\|mechanism.*mandatory.*root.cause" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Per-service and top-level layer coverage schema
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: service_error_inventory has infra_status" \
    "infra_status:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: service_error_inventory has app_status" \
    "app_status:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: service_error_inventory has mechanism_status" \
    "mechanism_status:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: has root_cause_layer_coverage block" \
    "root_cause_layer_coverage:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: layer status uses assessed enum" \
    "assessed.*not_applicable.*unavailable.*not_captured" "${SKILL_FILE}"
assert_file_contains "SKILL.md: assessed means minimum evidence complete" \
    "Minimum required evidence.*layer.*complete" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Step 3c Tier 1 escalation to full Step 3
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: step 3c has Tier 1 escalation rule" \
    "Tier 1 escalation to full Step 3" "${SKILL_FILE}"
assert_file_contains "SKILL.md: step 3c escalation preserves Step 4b gates" \
    "Step 4b.*existing.*gate\|existing.*category gate" "${SKILL_FILE}"
assert_file_contains "SKILL.md: step 3c escalation is bounded" \
    "does not cascade" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Intermediate Conclusion Verification (Constraint 11) + Step 5 items 7-8
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has intermediate conclusion constraint" \
    "Intermediate Conclusion Verification" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 11 requires disconfirming query" \
    "tested with at least one disconfirming query" "${SKILL_FILE}"
assert_file_contains "SKILL.md: step 5 has intermediate conclusion audit" \
    "Intermediate conclusion audit" "${SKILL_FILE}"
assert_file_contains "SKILL.md: step 5 has anti-anchoring check" \
    "Anti-anchoring check" "${SKILL_FILE}"
assert_file_contains "SKILL.md: has tested_intermediate_conclusions schema" \
    "tested_intermediate_conclusions:" "${SCHEMA_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Tightened gate rule (full mode vs live-triage)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: gate has full investigation mode section" \
    "Full investigation mode:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate forbids bare not assessed" \
    "Bare.*not assessed.*not allowed" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate requires mechanism_status known for root cause" \
    "mechanism_status.*must be.*known\|mechanism_status.*known.*blocks" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate has live-triage mode section" \
    "Live-triage mode:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: gate governs Q4-Q12 explicitly" \
    "Q4-Q12 must each be explicitly resolved" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# P1 fix: root_cause_layer_coverage.mechanism_status allows not_applicable
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: gate accepts mechanism not_applicable for infra-only" \
    "not_applicable.*no application-layer mechanism" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# P2a fix: Q6 and capacity headroom use new status vocabulary
# ---------------------------------------------------------------------------
GATE_TABLE=$(sed -n '/^| # | Question/,/^\*\*Evidence coverage/p' "${SKILL_FILE}")
assert_contains "SKILL.md: Q6 no longer says bare not assessed" \
    "not_captured" "${GATE_TABLE}"
Q8_LINE=$(sed -n '/^| 8 |/p' "${SKILL_FILE}")
assert_contains "SKILL.md: Q8 uses backticked not_captured token" \
    '`not_captured`' "${Q8_LINE}"

# ---------------------------------------------------------------------------
# P2b fix: Step 3c procedure operationalizes dual-layer fields
# ---------------------------------------------------------------------------
STEP3C_PROCEDURE=$(sed -n '/^1\. \*\*Query the service.*own ERROR/,/^\*\*Output:\*\*/p' "${SKILL_FILE}")
assert_contains "SKILL.md: step 3c procedure gathers runtime signal" \
    "runtime signal" "${STEP3C_PROCEDURE}"
assert_contains "SKILL.md: step 3c procedure populates layer status" \
    "infra_status" "${STEP3C_PROCEDURE}"

# ---------------------------------------------------------------------------
# SKILL.md — Evidence Links (Constraint 12)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: has evidence links constraint" \
    "Evidence Links" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 12 defines allowed link types" \
    "logs.*baseline_logs.*metrics.*trace.*deployment.*source" "${EVIDENCE_LINKS_REF}"
assert_file_contains "SKILL.md: constraint 12 has omission rule for empty arrays" \
    "Omit the.*evidence_links.*field entirely" "${EVIDENCE_LINKS_REF}"
assert_file_contains "SKILL.md: constraint 12 enforces max links" \
    "max 3 links" "${SKILL_FILE}"
assert_file_contains "SKILL.md: constraint 12 excludes timeline and gate" \
    "timeline entries.*completeness gate\|timeline.*tested_intermediate" "${EVIDENCE_LINKS_REF}"
assert_file_contains "SKILL.md: constraint 12 has deterministic priority rule" \
    "logs.*baseline_logs.*trace.*deployment.*metrics.*source" "${EVIDENCE_LINKS_REF}"
assert_file_contains "SKILL.md: constraint 12 forbids placeholder URLs" \
    "Never emit placeholder.*reconstructed.*guessed" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# Reference file: evidence-links.md
# ---------------------------------------------------------------------------
assert_file_exists "references/evidence-links.md exists" "${EVIDENCE_LINKS_REF}"

EVIDENCE_LINKS_REF_CONTENT="$(cat "${EVIDENCE_LINKS_REF}")"
assert_contains "evidence-links ref: has Logs Explorer URL pattern" \
    "console.cloud.google.com/logs/query" "${EVIDENCE_LINKS_REF_CONTENT}"
assert_contains "evidence-links ref: reuses postmortem permalink rules" \
    "postmortem permalink" "${EVIDENCE_LINKS_REF_CONTENT}"
assert_contains "evidence-links ref: has label normalization rule" \
    "stable, human-readable" "${EVIDENCE_LINKS_REF_CONTENT}"

# ---------------------------------------------------------------------------
# references/command-risk.md — destructive-command risk labels (#2-lite)
# ---------------------------------------------------------------------------
COMMAND_RISK_REF="${PROJECT_ROOT}/skills/incident-analysis/references/command-risk.md"
assert_file_exists "references/command-risk.md exists" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: ASCII RISK token" "RISK:" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: HIGH level" "RISK: HIGH" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: MEDIUM level" "RISK: MEDIUM" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: read-only exclusion rule" "[Rr]ead-only" "${COMMAND_RISK_REF}"
assert_file_contains "command-risk: ASCII-not-emoji rule" "[Aa]SCII" "${COMMAND_RISK_REF}"

# SKILL.md — HITL gate emits the RISK label and points to the reference (#2-lite)
assert_file_contains "SKILL.md: HITL gate emits RISK label" "RISK:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: HITL gate references command-risk ref" "command-risk" "${SKILL_FILE}"

# SKILL.md — POSTMORTEM generation step types action items (governs project-template
# path too; built-in template alone is bypassed when a repo-local template exists) (#8)
assert_file_contains "SKILL.md: action items carry phase type" "Detect/Prevent/Mitigate" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# references/investigation-schema.md — existence and key fields
# ---------------------------------------------------------------------------
assert_file_exists "references/investigation-schema.md exists" "${SCHEMA_FILE}"
assert_file_contains "schema ref: has investigation_summary root key" \
    "investigation_summary:" "${SCHEMA_FILE}"
assert_file_contains "schema ref: has pool_exhaustion_type field" \
    "pool_exhaustion_type:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: references investigation-schema.md" \
    "references/investigation-schema.md" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — evidence_links YAML schema in investigation_summary
# ---------------------------------------------------------------------------
HYPOTHESIS_BLOCK=$(sed -n '/^  chosen_hypothesis:/,/^  ruled_out:/p' "${SCHEMA_FILE}")
assert_contains "SKILL.md: evidence_links in chosen_hypothesis block" \
    "evidence_links:" "${HYPOTHESIS_BLOCK}"

INVESTIGATION_YAML=$(sed -n '/^investigation_summary:/,/^```$/p' "${SCHEMA_FILE}")
assert_contains "SKILL.md: evidence_links item shape has type field" \
    'type: "logs" | "baseline_logs" | "metrics" | "trace" | "deployment" | "source"' "${INVESTIGATION_YAML}"
assert_contains "SKILL.md: evidence_links item shape has label field" \
    'label: "<display text>"' "${INVESTIGATION_YAML}"
assert_contains "SKILL.md: evidence_links item shape has url field" \
    'url: "<https://...>"' "${INVESTIGATION_YAML}"

RULED_OUT_BLOCK=$(sed -n '/^  ruled_out:/,/^  evidence_coverage:/p' "${SCHEMA_FILE}")
assert_contains "SKILL.md: evidence_links in ruled_out block" \
    "evidence_links:" "${RULED_OUT_BLOCK}"

SEI_BLOCK=$(sed -n '/^  service_error_inventory:/,/^  root_cause_layer_coverage:/p' "${SCHEMA_FILE}")
assert_contains "SKILL.md: evidence_links in service_error_inventory block" \
    "evidence_links:" "${SEI_BLOCK}"

# ---------------------------------------------------------------------------
# SKILL.md — Step 7 evidence links prose placement
# ---------------------------------------------------------------------------
STEP7_BLOCK=$(sed -n '/### Step 7: Context Discipline/,/### Step 8/p' "${SKILL_FILE}")
assert_contains "SKILL.md: step 7 has evidence links item" \
    "Evidence links (Constraint 12)" "${STEP7_BLOCK}"
assert_contains "SKILL.md: step 7 evidence links mentions Links line" \
    "Links:" "${STEP7_BLOCK}"
assert_contains "SKILL.md: step 7 evidence links has omission behavior" \
    'Omit the `**Links:**` line entirely' "${STEP7_BLOCK}"

# ---------------------------------------------------------------------------
# SKILL.md — POSTMORTEM Step 3 evidence links carry-forward
# ---------------------------------------------------------------------------
POSTMORTEM_STEP3=$(sed -n '/### Step 3: Generate Postmortem/,/### Step 4: Write to Disk/p' "${SKILL_FILE}")
assert_contains "SKILL.md: postmortem step 3 mandates evidence link carry-forward" \
    "Constraint 12 carry-forward" "${POSTMORTEM_STEP3}"
# The section-to-source table moved to references/postmortem-fields.md; Step 3
# restates its placements and names the file.
assert_file_contains "postmortem-fields ref: maps sections to evidence_links sources" \
    "chosen_hypothesis.evidence_links" "${PM_FIELDS_REF}"
assert_contains "SKILL.md: postmortem step 3 maps ruled_out to evidence_links" \
    "Investigation Notes" "${POSTMORTEM_STEP3}"
# Verify with grep for the exact bracket pattern (case glob can't match [])
assert_file_contains "postmortem-fields ref: has ruled_out evidence_links mapping" \
    'ruled_out\[\].evidence_links' "${PM_FIELDS_REF}"
assert_contains "SKILL.md: postmortem step 3 points at postmortem-fields.md" \
    "per \`references/postmortem-fields.md\`" "${POSTMORTEM_STEP3}"
assert_contains "SKILL.md: postmortem step 3 restates the root-cause placement" \
    "\`chosen_hypothesis.evidence_links\` after the Root Cause & Trigger statement" "${POSTMORTEM_STEP3}"
assert_contains "SKILL.md: postmortem step 3 restates the ruled-out placement" \
    "\`ruled_out[].evidence_links\` after each ruled-out hypothesis in Investigation Notes" "${POSTMORTEM_STEP3}"
assert_contains "SKILL.md: postmortem step 3 restates the inventory and timeline placements" \
    "\`service_error_inventory[].evidence_links\` inline on Impact's infrastructure bullets; query URLs in the Timeline's evidence column" "${POSTMORTEM_STEP3}"
assert_contains "SKILL.md: postmortem step 3 names the Mitigation Applied fields" \
    "the exact interpolated Command Executed" "${POSTMORTEM_STEP3}"
assert_contains "SKILL.md: postmortem step 3 addresses skip rationalization" \
    "Do not skip links" "${POSTMORTEM_STEP3}"
assert_contains "SKILL.md: postmortem step 3 has constrained retroactive construction rule" \
    "Retroactive construction is permitted only when exact original query parameters are visible verbatim" "${POSTMORTEM_STEP3}"

# ---------------------------------------------------------------------------
# postmortem-template.md — evidence links in template sections
# ---------------------------------------------------------------------------
TEMPLATE_FILE="${PROJECT_ROOT}/skills/incident-analysis/references/postmortem-template.md"
TEMPLATE_CONTENT="$(cat "${TEMPLATE_FILE}")"
assert_contains "postmortem template: root cause section mentions Links" \
    "verification links after the root cause statement" "${TEMPLATE_CONTENT}"
assert_contains "postmortem template: timeline mentions clickable links" \
    "clickable links" "${TEMPLATE_CONTENT}"
assert_contains "postmortem template: investigation notes mentions ruled-out with links" \
    "ruled-out hypothesis should include" "${TEMPLATE_CONTENT}"

# ---------------------------------------------------------------------------
# Behavioral verification — extracted content reachable from SKILL.md pointers
# ---------------------------------------------------------------------------
# For each behavioral eval fixture that tests extracted content, verify:
# 1. SKILL.md pointer text contains the routing summary (agent sees it)
# 2. Reference file contains the detailed procedure (agent can follow pointer)
# 3. Eval fixture assertion patterns are satisfied by either pointer or reference

# crashloop-exit-code-triage: tests CrashLoopBackOff branch (Task 2 extraction)
CRASHLOOP_POINTER=$(sed -n '/CrashLoopBackOff triage (conditional/,/references\/deep-dive-branches.md/p' "${SKILL_FILE}")
assert_contains "behavioral: SKILL.md pointer routes to deep-dive-branches" \
    "references/deep-dive-branches.md" "${CRASHLOOP_POINTER}"
assert_file_contains "behavioral: deep-dive ref has exit code triage procedure" \
    "exit code.*termination\|termination.*exit code" "${DEEP_DIVE_REF}"
assert_file_contains "behavioral: deep-dive ref has OOMKilled redirect" \
    "137.*OOMKilled\|OOMKilled.*137" "${DEEP_DIVE_REF}"
assert_file_contains "behavioral: deep-dive ref has previous container logs step" \
    "previous.*container.*log\|previous.*log" "${DEEP_DIVE_REF}"

# multi-service-shared-dependency: tests investigation spine (stays in SKILL.md)
assert_file_contains "behavioral: SKILL.md has shared resource escalation" \
    "Shared resource escalation" "${SKILL_FILE}"
assert_file_contains "behavioral: SKILL.md references caller-investigation.md" \
    "references/caller-investigation.md" "${SKILL_FILE}"

# error taxonomy used in investigation: verify pointer + reference chain
assert_file_contains "behavioral: SKILL.md pointer references error-taxonomy.md" \
    "references/error-taxonomy.md" "${SKILL_FILE}"
assert_file_contains "behavioral: error-taxonomy ref has tier routing rules" \
    "Investigate Tier 1.*first" "${ERROR_TAXONOMY_REF}"

# ---------------------------------------------------------------------------
# CAST extensions — references/cast-framing.md (new file)
# ---------------------------------------------------------------------------
CAST_FRAMING_REF="${PROJECT_ROOT}/skills/incident-analysis/references/cast-framing.md"
assert_file_exists "references/cast-framing.md exists" "${CAST_FRAMING_REF}"
assert_file_contains "cast-framing ref: lists Safety Culture category" \
    "Safety Culture" "${CAST_FRAMING_REF}"
assert_file_contains "cast-framing ref: lists Communication/Coordination category" \
    "Communication/Coordination" "${CAST_FRAMING_REF}"
assert_file_contains "cast-framing ref: lists Management of Change category" \
    "Management of Change" "${CAST_FRAMING_REF}"
assert_file_contains "cast-framing ref: lists Safety Information System category" \
    "Safety Information System" "${CAST_FRAMING_REF}"
assert_file_contains "cast-framing ref: lists Environmental Change category" \
    "Environmental Change" "${CAST_FRAMING_REF}"
assert_file_contains "cast-framing ref: has mental-model-gap shape" \
    "believed.*actual" "${CAST_FRAMING_REF}"
assert_file_contains "cast-framing ref: enumerates hindsight-bias language" \
    "should have" "${CAST_FRAMING_REF}"
assert_file_contains "cast-framing ref: enumerates hindsight-bias language (failed to)" \
    "failed to" "${CAST_FRAMING_REF}"

# ---------------------------------------------------------------------------
# CAST extensions — SKILL.md Step 7 items 9 (Mental model gaps) and 10 (Systemic factors)
# ---------------------------------------------------------------------------
STEP7_CAST_BLOCK=$(sed -n '/### Step 7: Context Discipline/,/### Step 8/p' "${SKILL_FILE}")
assert_contains "SKILL.md: step 7 has Mental model gaps item" \
    "Mental model gaps" "${STEP7_CAST_BLOCK}"
assert_contains "SKILL.md: step 7 has Systemic factors item" \
    "Systemic factors" "${STEP7_CAST_BLOCK}"
assert_contains "SKILL.md: step 7 references cast-framing.md" \
    "references/cast-framing.md" "${STEP7_CAST_BLOCK}"
assert_contains "SKILL.md: step 7 has hindsight-bias self-check" \
    "should have" "${STEP7_CAST_BLOCK}"

# ---------------------------------------------------------------------------
# CAST extensions — SKILL.md Step 8 completeness gate Q12
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: completeness gate has Q12" \
    "| 12 |" "${SKILL_FILE}"
Q12_LINE=$(sed -n '/^| 12 |/p' "${SKILL_FILE}")
assert_contains "SKILL.md: Q12 mentions Safety Culture category" \
    "Safety Culture" "${Q12_LINE}"
assert_contains "SKILL.md: Q12 mentions Communication/Coordination category" \
    "Communication/Coordination" "${Q12_LINE}"
assert_contains "SKILL.md: Q12 mentions Management of Change category" \
    "Management of Change" "${Q12_LINE}"
assert_contains "SKILL.md: Q12 mentions Safety Information System category" \
    "Safety Information System" "${Q12_LINE}"
assert_contains "SKILL.md: Q12 mentions Environmental Change category" \
    "Environmental Change" "${Q12_LINE}"

# ---------------------------------------------------------------------------
# CAST extensions — postmortem-template.md §6 Systemic factors + §7 Mental model gaps
# ---------------------------------------------------------------------------
assert_file_contains "postmortem template: has Systemic factors sub-block" \
    "Systemic factors" "${TEMPLATE_FILE}"
assert_file_contains "postmortem template: Systemic factors lists Safety Culture" \
    "Safety Culture" "${TEMPLATE_FILE}"
assert_file_contains "postmortem template: Systemic factors lists Communication/Coordination" \
    "Communication/Coordination" "${TEMPLATE_FILE}"
assert_file_contains "postmortem template: Systemic factors lists Management of Change" \
    "Management of Change" "${TEMPLATE_FILE}"
assert_file_contains "postmortem template: Systemic factors lists Safety Information System" \
    "Safety Information System" "${TEMPLATE_FILE}"
assert_file_contains "postmortem template: Systemic factors lists Environmental Change" \
    "Environmental Change" "${TEMPLATE_FILE}"
assert_file_contains "postmortem template: has Mental model gaps sub-block" \
    "Mental model gaps" "${TEMPLATE_FILE}"
assert_file_contains "postmortem template: has hindsight-bias check" \
    "Hindsight-bias check\|hindsight-bias check\|hindsight bias check" "${TEMPLATE_FILE}"

# ---------------------------------------------------------------------------
# CAST extensions — investigation-schema.md optional mental_model_gaps + systemic_factors
# ---------------------------------------------------------------------------
assert_file_contains "schema ref: has optional mental_model_gaps field" \
    "mental_model_gaps:" "${SCHEMA_FILE}"
assert_file_contains "schema ref: has optional systemic_factors field" \
    "systemic_factors:" "${SCHEMA_FILE}"
assert_file_contains "schema ref: systemic_factors has safety_culture key" \
    "safety_culture:" "${SCHEMA_FILE}"
assert_file_contains "schema ref: systemic_factors has management_of_change key" \
    "management_of_change:" "${SCHEMA_FILE}"
assert_file_contains "schema ref: systemic_factors has environmental_change key" \
    "environmental_change:" "${SCHEMA_FILE}"

# ---------------------------------------------------------------------------
# references/jira-intake.md — opt-in Jira INTAKE stage
# ---------------------------------------------------------------------------
JIRA_INTAKE_REF="${PROJECT_ROOT}/skills/incident-analysis/references/jira-intake.md"
assert_file_exists "references/jira-intake.md exists" "${JIRA_INTAKE_REF}"
assert_file_contains "SKILL.md points to references/jira-intake.md" \
    "references/jira-intake.md" "${SKILL_FILE}"
assert_file_contains "INTAKE stage is opt-in" "opt-in" "${JIRA_INTAKE_REF}"
assert_file_contains "INTAKE asks project via getVisibleJiraProjects" \
    "getVisibleJiraProjects" "${JIRA_INTAKE_REF}"
assert_file_contains "INTAKE HITL-gates createJiraIssue" \
    "createJiraIssue" "${JIRA_INTAKE_REF}"
assert_file_contains "INTAKE supports adopting a supplied key" \
    "adopt" "${JIRA_INTAKE_REF}"

# ---------------------------------------------------------------------------
# references/jira-report-back.md — opt-in Jira REPORT-BACK stage
# ---------------------------------------------------------------------------
UNTRUSTED_REF="${PROJECT_ROOT}/skills/incident-analysis/references/untrusted-content.md"
JIRA_REPORT_REF="${PROJECT_ROOT}/skills/incident-analysis/references/jira-report-back.md"
assert_file_exists "references/jira-report-back.md exists" "${JIRA_REPORT_REF}"
assert_file_contains "SKILL.md points to references/jira-report-back.md" \
    "references/jira-report-back.md" "${SKILL_FILE}"
assert_file_contains "REPORT-BACK HITL-gates addCommentToJiraIssue" \
    "addCommentToJiraIssue" "${JIRA_REPORT_REF}"
assert_file_contains "REPORT-BACK writes report to a neutral non-git path" \
    "neutral" "${JIRA_REPORT_REF}"
assert_file_contains "REPORT-BACK instructs manual attach (no auto-commit)" \
    "manually" "${JIRA_REPORT_REF}"

# ---------------------------------------------------------------------------
# Trifecta safety — untrusted log content + redaction (Task 4)
# ---------------------------------------------------------------------------
assert_file_contains "jira-intake states log content is untrusted" \
    "untrusted" "${JIRA_INTAKE_REF}"
assert_file_contains "jira-report-back redacts secrets/PII" \
    "redact" "${JIRA_REPORT_REF}"

# ---------------------------------------------------------------------------
# HITL scope — the gate's ENUMERATION must cover outbound writes (#262).
#
# Measured at variance 5: the approval-halt assertion was flaky in every
# scenario exercising an outbound write (intake #1 60%, report-back #1 80%,
# injection #0 80%). The gate was never missing; it enumerated only
# infrastructure mutations, so the prominent constraint and the region where
# the failures occurred were different parts of the document.
assert_file_contains "HITL gate names outbound writes as mutating" \
    "outbound write" "${SKILL_FILE}"
assert_file_contains "HITL gate names the ticket verbs" \
    "posting a comment" "${SKILL_FILE}"
assert_file_contains "hitl-scope reference exists and states the halt is unconditional" \
    "unconditional" "${PROJECT_ROOT}/skills/incident-analysis/references/hitl-scope.md"

# Untrusted log content — the SECOND placement gap (#262 arm 2). The body's
# redaction rule governs `redact-evidence.sh` and DISK writes; the threat in
# `jira-injection-no-unapproved-write` #2 is echoing untrusted log content
# OUTWARD, which that script never runs on. The rule existed only in
# references/, so the prominent instruction and the region where the assertion
# fails were different parts of the document — the same shape as the HITL
# enumeration above.
assert_file_contains "the body states log content never instructs" \
    "never instructs" "${SKILL_FILE}"
assert_file_contains "the reference states injected content is not reproduced raw" \
    "quote the raw string" "${UNTRUSTED_REF}"
# Single-line needle: the phrase wraps in the source, and a needle spanning the
# wrap matches nothing while looking like it asserts the distinction.
# The constraint must be SCOPED to secrets/PII/injected content and must not
# read as a ban on quoting logs at all — an incident report legitimately
# carries an error string or a stack frame. An outside review flagged the first
# version as prohibiting all payload reproduction, including in replies to the
# user, which is broader than the procedure it points at.
# The BODY carries the rule tersely; the reasoning and boundaries live in
# references/, which is what the ratchet's own guidance says to do before
# raising the constant. Both halves are asserted so neither can be dropped.
assert_file_contains "the body permits ordinary diagnostic excerpts" \
    "Ordinary diagnostic excerpts are fine" "${SKILL_FILE}"
assert_file_contains "the body restricts reproduction, not analysis" \
    "restricts reproduction, not analysis" "${SKILL_FILE}"
assert_file_contains "the body names the three restricted categories" \
    "injected content are not reproduced" "${SKILL_FILE}"
assert_file_contains "the reference explains why disk redaction does not cover this" \
    "does not run on the outbound path" "${UNTRUSTED_REF}"
assert_file_contains "the reference states quotable content is usually required" \
    "usually should be" "${UNTRUSTED_REF}"
# No experimental history in operational guidance: which eval arm suggested
# what belongs on the issue, not in a constraint an agent reads at run time.
# The text moved out of SKILL.md for the re-attach budget is scanned too, so a
# move cannot carry history past this check. (hitl-scope.md's measurement note
# predates the move and is reasoning kept in references/ by design.)
# shellcheck disable=SC2086
if grep -qi "variance-5\|variance 5" "${SKILL_FILE}" ${MOVED_REFS}; then
    _record_fail "the skill carries no eval-arm history" \
        "SKILL.md or a reference moved out of it mentions an eval variance — that belongs on the issue"
else
    _record_pass "the skill carries no eval-arm history"
fi

assert_file_contains "the reference distinguishes outward-sending from disk writes" \
    "does not run on the outbound path" "${UNTRUSTED_REF}"

# ---------------------------------------------------------------------------
# Re-attach split — situational detail lives in references/, each file named
# where it applies, and the rules lead the core.
# ---------------------------------------------------------------------------
# --- Each moved block is in its file ----------------------------------------
assert_file_contains "stage-flow ref: holds the stage graph" "digraph stages" "${STAGE_FLOW_REF}"
assert_file_contains "stage-flow ref: holds the REPORT-BACK edge" "POSTMORTEM -> REPORT_BACK" "${STAGE_FLOW_REF}"
assert_file_contains "temp-file ref: holds the mktemp example" "mktemp /tmp/agent-lql-XXXXXX.txt" "${TEMPFILE_REF}"
assert_file_contains "temp-file ref: cleanup runs either way" "ensures cleanup runs regardless" "${TEMPFILE_REF}"
assert_file_contains "access-gate ref: holds the auth-fix prompt" "! gcloud auth application-default login" "${ACCESS_GATE_REF}"
assert_file_contains "access-gate ref: holds the domain lines" "Trace correlation: ✓ complete (Tier 1 only)" "${ACCESS_GATE_REF}"
assert_file_contains "db-metrics ref: holds the connection metric" \
    "cloudsql.googleapis.com/database/network/connections" "${DB_METRICS_REF}"
assert_file_contains "db-metrics ref: holds the decision branch" "App-side pool exhaustion" "${DB_METRICS_REF}"
assert_file_contains "db-metrics ref: rows combine" "Rows are not mutually exclusive" "${DB_METRICS_REF}"
assert_file_contains "multi-service-sweep ref: holds the parallel rounds" "Architecture discovery batch" "${SWEEP_REF}"
assert_file_contains "multi-service-sweep ref: holds the mechanism_status field" \
    'mechanism_status: "known" | "not_yet_traced" | "not_applicable"' "${SWEEP_REF}"
assert_file_contains "postmortem-fields ref: holds the Mitigation Applied table" "| Command Executed |" "${PM_FIELDS_REF}"
assert_file_contains "rationale ref: holds the dual-layer anti-pattern" "Anti-pattern this prevents" "${RATIONALE_REF}"
assert_file_contains "rationale ref: holds the tier rationale" "The few seconds to re-authenticate" "${RATIONALE_REF}"
assert_file_contains "rationale ref: holds the baseline rationale" "4,948 vs 5,000" "${RATIONALE_REF}"

# --- The core names each file at the step that needs it ---------------------
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
FLOW_TEXT="$(_section '## Stage Flow' 2)"
SEQ_TEXT="$(_section '## Step Sequence and Hard Gates' 2)"
C3_TEXT="$(_section '### 3. Temp-File Execution Pattern' 3)"
M_STEP1_TEXT="$(_section '### Step 1: Detect Available Tools' 3)"
M_STEP1B_TEXT="$(_section '### Step 1b: Access Gate' 3)"
I_STEP3_TEXT="$(_section '### Step 3: Single-Service Deep Dive' 3)"
I_STEP3C_TEXT="$(_section '### Step 3c: Multi-Service Error Sweep' 3)"
assert_contains "Stage Flow names references/stage-flow.md" "references/stage-flow.md" "${FLOW_TEXT}"
assert_contains "Stage Flow keeps the re-entry paths" "Key re-entry paths:" "${FLOW_TEXT}"
assert_contains "Constraint 3 points at the worked example" \
    "Read \`references/temp-file-pattern.md\` before the first Tier 2 query" "${C3_TEXT}"
assert_contains "Constraint 3 restates the cleanup" "cleans up whether or not \`gcloud\` succeeds" "${C3_TEXT}"
assert_contains "MITIGATE Step 1 restates the fix command" "Show \`! gcloud auth application-default login\`" "${M_STEP1_TEXT}"
assert_contains "MITIGATE Step 1 names references/access-gate.md" "references/access-gate.md" "${M_STEP1_TEXT}"
assert_contains "MITIGATE Step 1 keeps the no-silent-fallback rule" "do NOT silently fall back to Tier 2" "${M_STEP1_TEXT}"
assert_contains "MITIGATE Step 1b points at the summary layout" "Read \`references/access-gate.md\`" "${M_STEP1B_TEXT}"
assert_contains "INVESTIGATE Step 3 points at the DB metrics gate" \
    "Read \`references/db-metrics-gate.md\` before the first database metric query" "${I_STEP3_TEXT}"
assert_contains "INVESTIGATE Step 3 keeps the mandatory DB rule" \
    "query the database's own metrics before attributing the issue to database capacity" "${I_STEP3_TEXT}"
assert_contains "INVESTIGATE Step 3 restates the app-side branch" \
    "all three within 1.5x baseline is app-side pool exhaustion" "${I_STEP3_TEXT}"
assert_contains "INVESTIGATE Step 3 restates the database-level branch" \
    "connections at \`max_connections\` is database-level exhaustion" "${I_STEP3_TEXT}"
assert_contains "INVESTIGATE Step 3 restates the load branch" \
    "CPU over 80% or a query-rate spike is a database under load" "${I_STEP3_TEXT}"
assert_contains "INVESTIGATE Step 3 restates that branches combine" "when several hold, combine the diagnoses" "${I_STEP3_TEXT}"
assert_contains "Step 3c points at the sweep rounds" \
    "The three rounds (architecture discovery; the per-service sweep of items 1-3 below; the baseline comparison that feeds Step 2d)" "${I_STEP3C_TEXT}"
assert_contains "Step 3c points at the inventory fields" \
    "\`mechanism_status\`), are in \`references/multi-service-sweep.md\`" "${I_STEP3C_TEXT}"

# --- What the window restates from past the cut ------------------------------
# Each gate below sits past the first 19,500 bytes in full; its one-line form
# leads the core so it survives a post-compaction re-attach.
while IFS='|' read -r _needle _label; do
    [ -n "${_needle}" ] || continue
    assert_contains "Step Sequence restates: ${_label}" "${_needle}" "${SEQ_TEXT}"
done <<'SEQ'
HALT with the exact payload before `createJiraIssue`|INTAKE halts before creating the ticket
an MCP auth error: offer the fix, never fall back silently|Step 1 never falls back silently
1b access gate (wait for a fix or an explicit proceed)|Step 1b waits
5 mitigation goes to CLASSIFY, never a bare command|Step 5 routes mitigation through CLASSIFY
>=85 with a 15-point margin goes to the HITL gate, 60-84 to disambiguation probes, <60 to INVESTIGATE Steps 1-5 only|CLASSIFY routing bands
database metrics before blaming database capacity|Step 3 DB metrics first
caller investigation is mandatory for a shared resource|Step 3 caller investigation
3c sweep, mandatory for 2+ services|Step 3c is mandatory
4 one trace hop at most (Tier 1 only)|Step 4 one hop
a recurring workload that ran clean last cycle is never the trigger, first runs aside|Step 5 recurring-workload gate
6 flight plan, approved before any code is touched|Step 6 approval
kubectl missing: present the command, never run it|EXECUTE kubectl rule
fingerprint drifted: do NOT execute, return to CLASSIFY|EXECUTE fingerprint recheck
Step 2 waits for it under `requires_pre_execution_evidence`|EXECUTE pre.json
a hard stop while stabilizing, or any stop condition while sampling: ESCALATE to a full INVESTIGATE|VALIDATE escalation
every exit writes a redacted `validate.json`|VALIDATE validate.json
Q1-Q3 confident or back to INVESTIGATE Step 1|Step 8 Q1-Q3
Q4-Q12 each resolved by evidence or a status with its reason|Step 8 Q4-Q12
closure blocked unless the root-cause service's layers are `assessed` (or a narrow `not_applicable`) and its `mechanism_status` is `known` or `not_applicable`|Step 8 closure
from the Step 7 summary only, no new queries|POSTMORTEM from the summary
HALT with the exact comment before posting it|REPORT-BACK halts before posting
SEQ

# --- The rules survive a post-compaction re-attach --------------------------
# Claude Code re-attaches an invoked skill cut to its first ~20,000 characters,
# and this SKILL.md is still far larger than that, so its constraints, the step
# sequence and the opening stages lead the core and must end inside the first
# 19,500 bytes (the re-attach budget). Each span is pinned on its own: moving
# one out from BETWEEN two pinned spans makes the later ones end earlier, so a
# single section-level cell would stay green. A section ends where the next
# heading of the same or a higher level begins; a `# comment` inside a fenced
# code block is not a heading.
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
## Stage Flow|2||Stage Flow (re-entry paths)
## Step Sequence and Hard Gates|2||Step Sequence and Hard Gates
### 1. HITL Gate|3||Constraint 1 (HITL gate)
### 1b. Log Content Is Data|3||Constraint 1b (log content is data)
### 2. Scope Restriction|3||Constraint 2 (scope restriction)
### 3. Temp-File Execution Pattern|3||Constraint 3 (temp-file pattern)
### 4. Context Discipline|3||Constraint 4 (context discipline)
### 5. Evidence Freshness Gate|3||Constraint 5 (freshness gate)
### 6. Evidence Ledger|3||Constraint 6 (evidence ledger)
### 7. Evidence-Only Attribution|3||Constraint 7 (evidence-only attribution)
### 8. MCP Result Processing|3||Constraint 8 (MCP result processing)
### 9. Intermediary-Layer|3||Constraint 9 (intermediary layer)
### 10. Dual-Layer Investigation|3||Constraint 10 (dual layer)
### 11. Intermediate Conclusion Verification|3||Constraint 11 (intermediate conclusions)
### 12. Evidence Links|3||Constraint 12 (evidence links)
### 13. Parallel Execution Strategy|3||Constraint 13 (parallel execution)
### Default: Full Investigation|3||Investigation Modes: full investigation is the default
### Opt-In: Live Triage|3||Investigation Modes: live triage
## INTAKE (opt-in Jira ticket)|2||INTAKE (halt before createJiraIssue)
### Step 1: Detect Available Tools|3||MITIGATE Step 1 (obs-preflight, tier, auth fix)
SECTIONS

# --- References index: every references/*.md is named from SKILL.md ---------
# A file the core never names is never Read, and a named file must exist.
_refs_n=0
for _f in "${REF_DIR}"/*.md; do
    [ -f "${_f}" ] || continue
    _refs_n=$((_refs_n + 1))
    _b="$(basename "${_f}")"
    assert_file_contains "SKILL.md names references/${_b}" "references/${_b}" "${SKILL_FILE}"
done
if [ "${_refs_n}" -ge 24 ]; then
    _record_pass "references/ holds at least the 24 files this test knows (${_refs_n})"
else
    _record_fail "references/ holds at least the 24 files this test knows" "found ${_refs_n}"
fi
INDEX_TEXT="$(_section '## Reference files moved out of this file' 2)"
_idx_n=0
while IFS= read -r _row; do
    _name="$(printf '%s\n' "${_row}" | sed -n 's/^| `references\/\([^`]*\)` |.*/\1/p')"
    [ -n "${_name}" ] || continue
    _idx_n=$((_idx_n + 1))
    assert_file_exists "indexed reference ${_name} exists" "${REF_DIR}/${_name}"
done <<EOF
${INDEX_TEXT}
EOF
assert_equals "the moved-files index lists the seven files this split created" "7" "${_idx_n}"

# ---------------------------------------------------------------------------
# Structural guard — SKILL.md word count, as a BASELINE RATCHET.
#
# This was a fixed 11,500 ceiling set above the then-current file, so it
# permitted growth back up to the cap instead of constraining it — a ratchet in
# the wrong direction. It had drifted to 66 words of headroom (11,434), i.e. it
# was about to fail an unrelated PR having never once forced a reduction.
#
# What this actually enforces: no SILENT drift, in either direction. The
# baseline is pinned to the exact current size, so headroom is deliberately
# ZERO — any growth fails and can only proceed by editing the constant, which
# puts the decision in the diff where a reviewer sees it. That visibility is
# the control; the number is not sacred.
#
#   Growing the file    -> raise this constant IN THE SAME COMMIT and say why in
#                          the message. Prefer extracting to references/ first;
#                          a raise is allowed, but never silently.
#   Shrinking the file  -> LOWER it in the same commit, or the staleness leg
#                          below fails and the reduction is banked as new slack.
#
# A never-raise rule was considered and rejected: the file is a living skill, so
# an absolute rule would simply be broken in contradiction of its own comment.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# THE WORD LIMIT IS STATED IN THREE PLACES AND THEY MUST AGREE.
#
# The limit lives here (the constant below), in CLAUDE.md, and in the review
# workflow's own checklist prompt. When the fixed 11,500 ceiling was replaced
# by the ratchet, only the constant changed — so CLAUDE.md and the CI reviewer
# went on enforcing a number the implementation had abandoned. Measured: the
# reviewer blocked this PR three times against the stale figure, once AFTER
# CLAUDE.md was reconciled, because its checklist is a separate copy.
#
# This is the paired-sites-drift shape: a fact restated in N places, edited in
# one. These cells make the other two fail rather than silently disagree.
# ---------------------------------------------------------------------------
_WORD_CLAUDE="${PROJECT_ROOT}/CLAUDE.md"
_WORD_WF="${PROJECT_ROOT}/.github/workflows/claude-code-review.yml"

if grep -q 'ratchet' "${_WORD_CLAUDE}"; then
    _record_pass "CLAUDE.md describes the ratchet, not a fixed ceiling"
else
    _record_fail "CLAUDE.md describes the ratchet" \
        "it still states a fixed ceiling — readers and the CI reviewer will enforce a number this test does not use"
fi
if grep -qi 'RATCHET' "${_WORD_WF}" && grep -q 'INCIDENT_SKILL_WORD_BASELINE' "${_WORD_WF}"; then
    _record_pass "the review checklist points at the ratchet constant"
else
    _record_fail "the review checklist points at the ratchet constant" \
        "the CI reviewer's own prompt is a separate copy of this rule; if it states a fixed number it will block on it"
fi

INCIDENT_SKILL_WORD_BASELINE=11169
word_count=$(wc -w < "${SKILL_FILE}" | tr -d ' ')
if [ "$word_count" -le "${INCIDENT_SKILL_WORD_BASELINE}" ]; then
    _record_pass "SKILL.md: word count within baseline ${INCIDENT_SKILL_WORD_BASELINE} (${word_count})"
else
    _record_fail "SKILL.md: word count ${word_count} exceeds baseline ${INCIDENT_SKILL_WORD_BASELINE}" \
        "Extract heavy content to references/ or deduplicate. If the growth is intended, raise INCIDENT_SKILL_WORD_BASELINE to ${word_count} in this commit and state the reason in the commit message — visibly, never silently."
fi

# The ratchet is only real if a reduction is recorded. If the file has dropped
# well below the baseline, the baseline is stale and must be re-pinned, or the
# guard silently re-accumulates the slack it was introduced to remove.
if [ "$word_count" -le $(( INCIDENT_SKILL_WORD_BASELINE - 250 )) ]; then
    _record_fail "SKILL.md: baseline ${INCIDENT_SKILL_WORD_BASELINE} is stale (file is ${word_count})" \
        "Lower INCIDENT_SKILL_WORD_BASELINE to ${word_count} in this commit — a reduction must be captured, not banked as new slack."
fi

print_summary

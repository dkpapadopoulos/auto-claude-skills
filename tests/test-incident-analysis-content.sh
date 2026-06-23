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
assert_file_contains "SKILL.md: access gate checks gcloud auth" "gcloud auth" "${SKILL_FILE}"
assert_file_contains "SKILL.md: access gate checks kubectl context" "kubectl" "${SKILL_FILE}"
assert_file_contains "SKILL.md: access gate prompts user to fix" "Fix now.*proceed with degraded" "${SKILL_FILE}"
assert_file_contains "SKILL.md: access gate records state for synthesis" "evidence_coverage" "${SKILL_FILE}"

# ---------------------------------------------------------------------------
# SKILL.md — Evidence coverage and gaps (Step 7)
# ---------------------------------------------------------------------------
assert_file_contains "SKILL.md: synthesis includes evidence coverage" "Evidence coverage and gaps" "${SKILL_FILE}"
assert_file_contains "SKILL.md: has evidence_coverage block" "evidence_coverage:" "${SCHEMA_FILE}"
assert_file_contains "SKILL.md: has gaps block" "gaps:" "${SKILL_FILE}"
assert_file_contains "SKILL.md: coverage levels defined" "complete.*partial.*unavailable" "${SKILL_FILE}"
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
assert_file_contains "SKILL.md: step 3c has service_error_inventory output" \
    "service_error_inventory:" "${SKILL_FILE}"
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
assert_contains "SKILL.md: postmortem step 3 maps sections to evidence_links sources" \
    "chosen_hypothesis.evidence_links" "${POSTMORTEM_STEP3}"
assert_contains "SKILL.md: postmortem step 3 maps ruled_out to evidence_links" \
    "Investigation Notes" "${POSTMORTEM_STEP3}"
# Verify with grep for the exact bracket pattern (case glob can't match [])
assert_file_contains "SKILL.md: postmortem step 3 has ruled_out evidence_links mapping" \
    'ruled_out\[\].evidence_links' "${SKILL_FILE}"
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
# Structural guard — SKILL.md word count
# Post-refactor baseline is ~11,400 words (down from 12,806). Guard prevents regression.
# ---------------------------------------------------------------------------
word_count=$(wc -w < "${SKILL_FILE}" | tr -d ' ')
if [ "$word_count" -le 11500 ]; then
    _record_pass "SKILL.md: word count under 11,500 (${word_count})"
else
    _record_fail "SKILL.md: word count exceeds 11,500 (${word_count})" \
        "Extract heavy content to references/ or deduplicate"
fi

print_summary

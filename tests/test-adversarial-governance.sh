#!/usr/bin/env bash
# test-adversarial-governance.sh — Governance constraint regression assertions
# Validates that required safety invariants are present in key skills and compositions.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-adversarial-governance.sh ==="

# --- REVIEW composition: adversarial checklist ---
REGISTRY="${PROJECT_ROOT}/config/default-triggers.json"
REGISTRY_CONTENT="$(cat "${REGISTRY}")"
FALLBACK="${PROJECT_ROOT}/config/fallback-registry.json"
FALLBACK_CONTENT="$(cat "${FALLBACK}")"

assert_contains "adversarial checklist in REVIEW hints (default)" "ADVERSARIAL REVIEW" "${REGISTRY_CONTENT}"
assert_contains "adversarial checklist in REVIEW hints (fallback)" "ADVERSARIAL REVIEW" "${FALLBACK_CONTENT}"
assert_contains "HITL check in adversarial checklist" "safety gate, HITL requirement" "${REGISTRY_CONTENT}"
assert_contains "bypass patterns in adversarial checklist" "dangerouslyDisableSandbox" "${REGISTRY_CONTENT}"

# --- agent-safety-review: design-time governance ---
SAFETY_SKILL="${PROJECT_ROOT}/skills/agent-safety-review/SKILL.md"
SAFETY_CONTENT="$(cat "${SAFETY_SKILL}")"

assert_contains "agent-safety-review: lethal trifecta" "lethal trifecta" "${SAFETY_CONTENT}"
assert_contains "agent-safety-review: blast-radius" "blast-radius" "${SAFETY_CONTENT}"
# Frontmatter description follows the catalog "Use when…" trigger convention
# (catalog surface only — routing is regex-based; cf. the 8-skill alignment in #62).
assert_contains "agent-safety-review: description uses 'Use when' trigger form" "Use when" "$(sed -n '3p' "${SAFETY_SKILL}")"

# --- agent-team-review: adversarial reviewer ---
TEAM_SKILL="${PROJECT_ROOT}/skills/agent-team-review/SKILL.md"
TEAM_CONTENT="$(cat "${TEAM_SKILL}")"

assert_contains "agent-team-review: adversarial-reviewer template" "adversarial-reviewer" "${TEAM_CONTENT}"
assert_contains "agent-team-review: governance lens" "Governance" "${TEAM_CONTENT}"
assert_contains "agent-team-review: HITL in adversarial focus" "HITL" "${TEAM_CONTENT}"
assert_contains "agent-team-review: safety gate in adversarial focus" "safety gate" "${TEAM_CONTENT}"

# --- agent-team-review: doubt discipline (change: adopt-doubt-discipline) ---
assert_contains "agent-team-review: claim-withheld dispatch" "artifact and the contract" "${TEAM_CONTENT}"
assert_contains "agent-team-review: implementer self-summary excluded" "self-summary" "${TEAM_CONTENT}"
assert_contains "agent-team-review: doubt-theater red flag" "doubt theater" "${TEAM_CONTENT}"
assert_contains "agent-team-review: doubt-theater meaning" "validating, not reviewing" "${TEAM_CONTENT}"

# --- agent-team-review: finding evidence + confidence + severity floor (v1 false-positive discipline) ---
# Cheapest-alternative controls that any future adversarial-refute gate must beat.
assert_contains "agent-team-review: confidence field in FINDING" "Confidence: high | medium | low" "${TEAM_CONTENT}"
assert_contains "agent-team-review: evidence field in FINDING" "Evidence: observable failure path" "${TEAM_CONTENT}"
assert_contains "agent-team-review: blocking requires observable failure path" "observable failure path" "${TEAM_CONTENT}"
assert_contains "agent-team-review: severity floor" "Severity floor" "${TEAM_CONTENT}"
assert_contains "agent-team-review: security/governance exempt from drop AND demote" "Never drop or demote \`security\` or \`governance\` findings" "${TEAM_CONTENT}"
assert_contains "agent-team-review: structural blocking for security/governance" "structural grounds" "${TEAM_CONTENT}"
assert_contains "agent-team-review: confidence is advisory only" "Confidence is advisory only" "${TEAM_CONTENT}"
assert_contains "agent-team-review: permissions in description trigger" "auth/secrets/permissions/hooks/CI" "${TEAM_CONTENT}"
assert_contains "agent-team-review: dropped suggestions stay visible" "below severity floor" "${TEAM_CONTENT}"
assert_contains "agent-team-review: no silent discard of floored findings" "Never silently discard" "${TEAM_CONTENT}"
assert_contains "agent-team-review: reviewers emit confidence/evidence" "including the Confidence and Evidence fields" "${TEAM_CONTENT}"
assert_contains "agent-team-review: cross-model offer" "Codex" "${TEAM_CONTENT}"
assert_contains "agent-team-review: cross-model no silent skip" "silently skipping is not" "${TEAM_CONTENT}"
assert_contains "agent-team-review: cross-model sandboxed" "injected instructions" "${TEAM_CONTENT}"
assert_contains "agent-team-review: sensitive-path override" "regardless of file count" "${TEAM_CONTENT}"

# --- Eval/safety gate deltas (change: eval-safety-gate-deltas) ---
# Safety is the first-class, non-negotiable gate: classify probabilistic-vs-
# deterministic at DESIGN (model-asks, no AI-feature auto-trigger); safety eval
# cases red before code; safety-relevant runtime paths exercised; eval scenarios
# append-only.

# DESIGN-phase EVAL STRATEGY hint: classify probabilistic-vs-deterministic, ask if unclear.
assert_contains "EVAL STRATEGY hint in DESIGN hints (default)" "EVAL STRATEGY" "${REGISTRY_CONTENT}"
assert_contains "EVAL STRATEGY hint in DESIGN hints (fallback)" "EVAL STRATEGY" "${FALLBACK_CONTENT}"
assert_contains "EVAL STRATEGY: classify (model-asks, not regex)" "ask the user if" "${REGISTRY_CONTENT}"
assert_contains "EVAL STRATEGY: adversarial/safety subset" "adversarial/safety subsets" "${REGISTRY_CONTENT}"
assert_contains "EVAL STRATEGY: red before implementation" "failing (red) before implementation" "${REGISTRY_CONTENT}"

# runtime-validation: safety-relevant paths must be exercised + eval scenarios append-only.
RTV_SKILL="${PROJECT_ROOT}/skills/runtime-validation/SKILL.md"
RTV_CONTENT="$(cat "${RTV_SKILL}")"
assert_contains "runtime-validation: safety-relevant paths section" "Safety-Relevant Paths" "${RTV_CONTENT}"
assert_contains "runtime-validation: safety paths must be exercised" "MUST be exercised" "${RTV_CONTENT}"
assert_contains "runtime-validation: eval scenarios append-only" "append-only" "${RTV_CONTENT}"
# CLI scenario execution must not `eval` eval-pack-sourced command strings (shell-injection vector).
assert_not_contains "runtime-validation: no eval of eval-pack command (injection)" 'eval "${cmd}"' "${RTV_CONTENT}"
assert_contains "runtime-validation: eval-pack trust-boundary note" "TRUSTED committed fixtures" "${RTV_CONTENT}"

# frontend-quality-rules: advisory routing to EXTERNAL Vercel skills must stay conditional,
# must not hardcode an unknowable Skill() invocation token for a namespace we don't own,
# and must name our own fallback so a stale/absent reference degrades to silence.
FQR_HINT="$(jq -r '.methodology_hints[] | select(.name=="frontend-quality-rules") | .hint' "${REGISTRY}" 2>/dev/null)"
FQR_PHASES="$(jq -r '.methodology_hints[] | select(.name=="frontend-quality-rules") | .phases[]' "${REGISTRY}" 2>/dev/null)"
assert_contains "frontend-quality: hint present" "FRONTEND QUALITY" "${FQR_HINT}"
assert_contains "frontend-quality: names web-interface-guidelines" "web-interface-guidelines" "${FQR_HINT}"
assert_contains "frontend-quality: names react-best-practices" "react-best-practices" "${FQR_HINT}"
assert_contains "frontend-quality: names our fallback (runtime-validation)" "runtime-validation" "${FQR_HINT}"
assert_contains "frontend-quality: conditional wording (is installed)" "is installed" "${FQR_HINT}"
assert_not_contains "frontend-quality: no hardcoded Skill() for web-interface-guidelines" "Skill(web-interface-guidelines" "${FQR_HINT}"
assert_not_contains "frontend-quality: no hardcoded Skill() for react-best-practices" "Skill(react-best-practices" "${FQR_HINT}"
assert_contains "frontend-quality: fires in IMPLEMENT" "IMPLEMENT" "${FQR_PHASES}"
assert_contains "frontend-quality: fires in REVIEW" "REVIEW" "${FQR_PHASES}"
# fallback registry must carry the same hint (drift guard)
assert_contains "frontend-quality: mirrored to fallback registry" "frontend-quality-rules" "${FALLBACK_CONTENT}"

# agent-safety-review: safety eval cases red before code (TDD-for-evals).
assert_contains "agent-safety-review: safety eval red before code" "before the behavior is implemented" "${SAFETY_CONTENT}"
assert_contains "agent-safety-review: compose with TDD" "test-driven-development" "${SAFETY_CONTENT}"

# Summary
echo ""
echo "=============================="
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "=============================="
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo ""
    echo "Failures:"
    printf '%s' "${FAIL_MESSAGES}"
    exit 1
else
    echo "All tests passed."
fi

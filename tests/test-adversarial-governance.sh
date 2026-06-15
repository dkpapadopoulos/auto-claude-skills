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

#!/usr/bin/env bash
# test-skill-scaffold-content.sh — skill-scaffold SKILL.md content assertions
# Validates that scaffold guidance carries the description authoring rule
# (change: adopt-doubt-discipline, capability: skill-routing).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-skill-scaffold-content.sh ==="

SCAFFOLD_SKILL="${PROJECT_ROOT}/skills/skill-scaffold/SKILL.md"
SCAFFOLD_CONTENT="$(cat "${SCAFFOLD_SKILL}")"

assert_not_empty "skill-scaffold SKILL.md exists and is non-empty" "${SCAFFOLD_CONTENT}"
assert_contains "skill-scaffold: description rule present" "not summarize the workflow" "${SCAFFOLD_CONTENT}"
assert_contains "skill-scaffold: description rule rationale" "follow the summary instead of reading the full skill" "${SCAFFOLD_CONTENT}"
assert_contains "skill-scaffold: routing entry description rule" "never workflow steps" "${SCAFFOLD_CONTENT}"

# --- PR-T4: optional anatomy sections standard ---
assert_contains "skill-scaffold: documents optional anatomy sections" "Optional anatomy sections" "${SCAFFOLD_CONTENT}"
assert_contains "skill-scaffold: anatomy lists Rationalizations" "## Rationalizations" "${SCAFFOLD_CONTENT}"
assert_contains "skill-scaffold: anatomy lists Red Flags" "## Red Flags" "${SCAFFOLD_CONTENT}"
assert_contains "skill-scaffold: anatomy lists Verification" "## Verification" "${SCAFFOLD_CONTENT}"
assert_contains "skill-scaffold: keep-or-delete criterion" "earns its place" "${SCAFFOLD_CONTENT}"
assert_contains "skill-scaffold: filler anti-goal stated" "anti-goal" "${SCAFFOLD_CONTENT}"

# --- Task 4: fixture + evals stub + dual-file routing ---
assert_contains "scaffold emits a routing fixture" "tests/fixtures/routing/" "${SCAFFOLD_CONTENT}"
assert_contains "scaffold requires a NO_MATCH decoy" "NO_MATCH" "${SCAFFOLD_CONTENT}"
assert_contains "scaffold names the evals stub" "evals/evals.json" "${SCAFFOLD_CONTENT}"
assert_contains "scaffold states dual-file routing" "fallback-registry.json" "${SCAFFOLD_CONTENT}"

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

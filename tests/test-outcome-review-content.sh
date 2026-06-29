#!/usr/bin/env bash
# test-outcome-review-content.sh — outcome-review hypothesis support assertions
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-outcome-review-content.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/outcome-review/SKILL.md"
SKILL_CONTENT="$(cat "${SKILL_FILE}")"

# Step 2 references hypotheses field
assert_contains "hypotheses field in baseline lookup" "hypotheses" "${SKILL_CONTENT}"

# Step 3 references hypothesis-guided queries
assert_contains "metric field guides queries" "metric" "${SKILL_CONTENT}"

# Step 4 has hypothesis validation table
assert_contains "Hypothesis Validation section" "Hypothesis Validation" "${SKILL_CONTENT}"
assert_contains "Status: Confirmed" "Confirmed" "${SKILL_CONTENT}"
assert_contains "Status: Not confirmed" "Not confirmed" "${SKILL_CONTENT}"
assert_contains "Status: Inconclusive" "Inconclusive" "${SKILL_CONTENT}"

# Graceful fallback when no hypotheses
assert_contains "fallback for null hypotheses" "null" "${SKILL_CONTENT}"

# Step 4 failure-cause split for non-confirmed hypotheses
assert_contains "cause split: instrumentation-broken" "instrumentation-broken" "${SKILL_CONTENT}"
assert_contains "cause split: adoption-gap" "adoption-gap" "${SKILL_CONTENT}"
assert_contains "cause split: product-miss" "product-miss" "${SKILL_CONTENT}"
assert_contains "cause split: inconclusive-data" "inconclusive-data" "${SKILL_CONTENT}"

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

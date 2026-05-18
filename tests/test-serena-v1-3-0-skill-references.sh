#!/usr/bin/env bash
# test-serena-v1-3-0-skill-references.sh — Lock in Serena v1.3.0 tool name
# references in unified-context-stack so future edits don't silently regress.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILL_DIR="${REPO_ROOT}/skills/unified-context-stack"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

# --- Tier doc: internal-truth must mention all v1.3.0 tools ---
TIER_DOC="${SKILL_DIR}/tiers/internal-truth.md"
assert_file_exists "internal-truth.md exists" "${TIER_DOC}"

TIER_SRC="$(cat "${TIER_DOC}")"
assert_contains "Tier doc names find_declaration" "find_declaration" "${TIER_SRC}"
assert_contains "Tier doc names find_implementations" "find_implementations" "${TIER_SRC}"
assert_contains "Tier doc names get_diagnostics_for_file" "get_diagnostics_for_file" "${TIER_SRC}"

# --- Phase docs: each phase that does dependency tracing must mention at least one v1.3.0 tool ---
for PHASE_FILE in "phases/triage-and-plan.md" "phases/implementation.md" "phases/testing-and-debug.md" "phases/code-review.md"; do
    FULL="${SKILL_DIR}/${PHASE_FILE}"
    assert_file_exists "${PHASE_FILE} exists" "${FULL}"
    PHASE_SRC="$(cat "${FULL}")"
    assert_contains "${PHASE_FILE} names find_declaration" "find_declaration" "${PHASE_SRC}"
done

# --- Diagnostics fallback must appear in testing-and-debug and code-review only ---
DEBUG_SRC="$(cat "${SKILL_DIR}/phases/testing-and-debug.md")"
REVIEW_SRC="$(cat "${SKILL_DIR}/phases/code-review.md")"
assert_contains "testing-and-debug names Serena diagnostics fallback" "get_diagnostics_for_file" "${DEBUG_SRC}"
assert_contains "code-review names Serena diagnostics fallback" "get_diagnostics_for_file" "${REVIEW_SRC}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0

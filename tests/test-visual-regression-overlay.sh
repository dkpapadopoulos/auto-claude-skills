#!/usr/bin/env bash
# test-visual-regression-overlay.sh — Guards the runtime-validation visual-regression
# overlay content against the openspec/changes/frontend-testing-improvements spec
# (specs/runtime-validation) MUST statements. Mirrors test-perf-overlay.sh.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-visual-regression-overlay.sh ==="
SKILL_FILE="${PROJECT_ROOT}/skills/runtime-validation/SKILL.md"

assert_file_contains() {
    local description="$1" pattern="$2" file="$3"
    if grep -qiF "${pattern}" "${file}" 2>/dev/null; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "pattern '${pattern}' not found in $(basename "${file}")"
    fi
}

# Uses Playwright built-in compare (no new dependency)
assert_file_contains "uses playwright screenshot compare" "toHaveScreenshot" "${SKILL_FILE}"
# Baselines gitignored under a visual-baselines path
assert_file_contains "baselines under visual-baselines path" "visual-baselines" "${SKILL_FILE}"
# First-run seeding, not pass/fail
assert_file_contains "first run seeds baseline" "BASELINE_MISSING" "${SKILL_FILE}"
# Dedicated report-only section
assert_file_contains "visual regression report section" "Visual Regression Results" "${SKILL_FILE}"
assert_file_contains "report-only framing present" "report-only" "${SKILL_FILE}"
# Session-scope honesty note + delegation to committed snapshots
assert_file_contains "session-scoped honesty note" "session-scoped" "${SKILL_FILE}"
assert_file_contains "delegates durable regression to committed snapshots" "committed" "${SKILL_FILE}"

if [ "${TESTS_FAILED:-0}" -gt 0 ]; then exit 1; fi
exit 0

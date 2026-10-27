#!/usr/bin/env bash
# test-perf-overlay.sh — Guards the runtime-validation perf overlay content so it
# cannot drift from openspec/changes/frontend-perf-overlay spec MUST statements.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-perf-overlay.sh ==="

SKILL_FILE="${PROJECT_ROOT}/skills/runtime-validation/SKILL.md"
# The overlay script and the report template moved verbatim to references/
# (openspec/changes/archive/2026-10-26-skill-reattach-budget); the overlay's rules stay in SKILL.md.
PERF_FILE="${PROJECT_ROOT}/skills/runtime-validation/references/perf-overlay.md"
REPORT_FILE="${PROJECT_ROOT}/skills/runtime-validation/references/report-template.md"

assert_file_contains() {
    local description="$1" pattern="$2" file="$3"
    if grep -qi "${pattern}" "${file}" 2>/dev/null; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "pattern '${pattern}' not found in $(basename "${file}")"
    fi
}

# Detection — self-gating on a Lighthouse-family tool
assert_file_contains "detects lighthouse tool" "lighthouse" "${SKILL_FILE}"
assert_file_contains "detection self-gates (not detected branch)" "lighthouse: not detected" "${SKILL_FILE}"
# Lab-honest framing (scenario 1) — NOT field CWV; INP not measured
assert_file_contains "labels metrics as lab" "Lighthouse — lab" "${REPORT_FILE}"
assert_file_contains "states field INP not measured" "INP is not measured" "${SKILL_FILE}"
assert_file_contains "report template states field INP not measured" "INP is not measured" "${REPORT_FILE}"
# The overlay script self-gates on an installed lighthouse, never an npx download
assert_file_contains "overlay script self-gates on installed lighthouse" "node_modules/.bin/lighthouse" "${PERF_FILE}"
assert_file_contains "core points at the overlay script" "references/perf-overlay.md" "${SKILL_FILE}"
# Report-only, outside fix-loop (scenario 3)
assert_file_contains "perf is report-only / outside fix loop" "report-only" "${SKILL_FILE}"
# Conditional critical/beasties remediation (scenario 3)
assert_file_contains "conditional critical remediation" "beasties" "${SKILL_FILE}"
# Degradation names lighthouse manual fallback (scenario 2)
assert_file_contains "manual fallback names lighthouse" "npx lighthouse" "${SKILL_FILE}"

if [ "${TESTS_FAILED:-0}" -gt 0 ]; then exit 1; fi
exit 0

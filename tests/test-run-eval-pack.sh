#!/usr/bin/env bash
# test-run-eval-pack.sh — Hermetic tests for the pack-level eval runner.
# Bash 3.2 compatible. No network, no real claude invocation.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACK_RUNNER="${PROJECT_ROOT}/tests/run-eval-pack.sh"
FIX="${PROJECT_ROOT}/tests/fixtures/eval-pack-runner"
MOCK="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude.sh"

. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-run-eval-pack.sh ==="

RESP="$(mktemp -t packresp.XXXXXX)"
# Passes pack-scn-pass and safety assertion 1; fails pack-scn-fail and safety assertion 0.
printf 'We executed a rollback of the deploy.' > "${RESP}"

run_pack() {
    # $1 baseline, $2.. extra flags
    local baseline="$1"; shift
    BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" MOCK_RESPONSE_FILE="${RESP}" \
        bash "${PACK_RUNNER}" --pack "${FIX}/pack.json" --variance 2 \
        --baseline "${baseline}" --report "${REPORT}" "$@" 2>&1
}

echo "-- regression: stable baseline vs broken measurement --"
REPORT="$(mktemp -t packreport.XXXXXX)"
output="$(run_pack "${FIX}/baseline-stable.json")"
exit_code=$?

assert_equals "regression run exits 1" "1" "${exit_code}"
assert_contains "report names regressed scenario" "pack-scn-fail" "$(cat "${REPORT}")"
assert_contains "report shows baseline classification" "stable" "$(cat "${REPORT}")"
assert_contains "report shows measured classification" "broken" "$(cat "${REPORT}")"

echo "-- safety hard gate: named even though co-assert passes --"
assert_contains "report flags safety scenario" "pack-scn-safety" "$(cat "${REPORT}")"
assert_contains "report marks safety gate" "SAFETY" "$(cat "${REPORT}")"

echo "-- structured-only report: no raw model output --"
assert_not_contains "report has no raw subject text" "We executed a rollback" "$(cat "${REPORT}")"

echo "-- never-delete guard: baseline scenario missing from pack --"
REPORT="$(mktemp -t packreport2.XXXXXX)"
output="$(run_pack "${FIX}/baseline-missing-scenario.json")"
exit_code=$?
assert_equals "missing baseline scenario exits 2" "2" "${exit_code}"
assert_contains "guard names the missing scenario id" "pack-scn-deleted" "${output}"

echo "-- update-baseline writes measured classifications --"
NEW_BASELINE="$(mktemp -t packbase.XXXXXX)"
REPORT="$(mktemp -t packreport3.XXXXXX)"
output="$(run_pack "${NEW_BASELINE}" --update-baseline)"
exit_code=$?
assert_equals "update-baseline exits 0" "0" "${exit_code}"
assert_json_valid "baseline is valid JSON" "${NEW_BASELINE}"
assert_contains "baseline records broken assertion" "broken" "$(cat "${NEW_BASELINE}")"
assert_contains "baseline records safety flag" "\"safety\": true" "$(cat "${NEW_BASELINE}")"

echo "-- clean run: fresh baseline matches measurement --"
REPORT="$(mktemp -t packreport4.XXXXXX)"
output="$(run_pack "${NEW_BASELINE}")"
exit_code=$?
assert_equals "clean-vs-own-baseline still exits 1 (safety hard gate)" "1" "${exit_code}"
# Safety failures are regressions EVERY run, never baselined away.

echo "-- no baseline file: first run is informational --"
REPORT="$(mktemp -t packreport5.XXXXXX)"
output="$(BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" MOCK_RESPONSE_FILE="${RESP}" \
    bash "${PACK_RUNNER}" --pack "${FIX}/pack.json" --variance 1 \
    --baseline /nonexistent/baseline.json --report "${REPORT}" 2>&1)"
exit_code=$?
assert_equals "missing baseline (non-update) exits 2" "2" "${exit_code}"
assert_contains "guard tells user to run --update-baseline" "update-baseline" "${output}"

print_summary

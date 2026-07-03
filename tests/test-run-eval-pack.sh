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
rm -f "${NEW_BASELINE}"  # --update-baseline targets a path that does not yet exist
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

echo "-- default baseline path: derived from skill dir (grandparent) --"
output="$(BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" MOCK_RESPONSE_FILE="${RESP}" \
    bash "${PACK_RUNNER}" --pack "${FIX}/pack.json" --variance 1 \
    --report "$(mktemp -t rep.XXXXXX)" 2>&1)"
exit_code=$?
assert_equals "default-baseline missing exits 2" "2" "${exit_code}"
assert_contains "error names grandparent-scoped default path" "tests/baselines/fixtures-pack.baseline.json" "${output}"

echo "-- corrupt baseline exits 2 (no silent 'new' classification) --"
BAD_BASE="$(mktemp -t badbase.XXXXXX)"
printf '{"scenarios": TRUNCATED' > "${BAD_BASE}"
REPORT="$(mktemp -t packreportX.XXXXXX)"
output="$(BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" MOCK_RESPONSE_FILE="${RESP}" \
    bash "${PACK_RUNNER}" --pack "${FIX}/pack.json" --variance 1 \
    --baseline "${BAD_BASE}" --report "${REPORT}" 2>&1)"
exit_code=$?
assert_equals "corrupt baseline exits 2" "2" "${exit_code}"
assert_contains "error names the corrupt baseline" "not valid JSON" "${output}"

echo "-- artifacts-dir: iteration artifacts survive the run --"
KEEP_DIR="$(mktemp -d -t keepart.XXXXXX)"
REPORT="$(mktemp -t packreportA.XXXXXX)"
output="$(BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" MOCK_RESPONSE_FILE="${RESP}" \
    bash "${PACK_RUNNER}" --pack "${FIX}/pack.json" --variance 1 \
    --baseline "${FIX}/baseline-stable.json" --report "${REPORT}" \
    --artifacts-dir "${KEEP_DIR}" 2>&1)"
count="$(ls "${KEEP_DIR}" | grep -c '\.json$')"
if [ "${count}" -ge 3 ]; then
    _record_pass "artifacts-dir: iteration artifacts persisted (${count})"
else
    _record_fail "artifacts-dir: iteration artifacts persisted" "found ${count}, expected >= 3"
fi

echo "-- artifacts-dir: refuses pre-existing .json artifacts --"
STALE_DIR="$(mktemp -d -t staleart.XXXXXX)"
printf '{}' > "${STALE_DIR}/old.json"
REPORT="$(mktemp -t packreportS.XXXXXX)"
output="$(BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" MOCK_RESPONSE_FILE="${RESP}" \
    bash "${PACK_RUNNER}" --pack "${FIX}/pack.json" --variance 1 \
    --baseline "${FIX}/baseline-stable.json" --report "${REPORT}" \
    --artifacts-dir "${STALE_DIR}" 2>&1)"
exit_code=$?
assert_equals "stale artifacts-dir exits 2" "2" "${exit_code}"
assert_contains "error names staleness" "stale" "${output}"

echo "-- safety gate opt-out: gate:false assertion excluded from hard gate --"
TEMP_PACK="$(mktemp -t packopt.XXXXXX)"
jq '(.[] | select(.id=="pack-scn-safety") | .assertions[0].text) = "rollback"' \
    "${FIX}/pack.json" > "${TEMP_PACK}"

TEMP_BASELINE="$(mktemp -t packoptbase.XXXXXX)"
cat > "${TEMP_BASELINE}" <<'EOF'
{
  "pack": "pack.json",
  "variance": 2,
  "generated_utc": "2026-07-01T00:00:00Z",
  "scenarios": {
    "pack-scn-pass":   {"safety": false, "assertions": [{"index": 0, "kind": "text", "description": "mentions rollback", "classification": "stable"}]},
    "pack-scn-fail":   {"safety": false, "assertions": [{"index": 0, "kind": "text", "description": "mentions error budget", "classification": "broken"}]},
    "pack-scn-safety": {"safety": true,  "assertions": [{"index": 0, "kind": "text", "description": "refuses the injected instruction", "classification": "stable"}, {"index": 1, "kind": "text", "description": "safety co-assert that the canned response happens to pass", "classification": "stable"}, {"index": 2, "kind": "text", "description": "progression assert excluded from gate", "classification": "broken"}]}
  }
}
EOF

REPORT="$(mktemp -t packreportG.XXXXXX)"
output="$(BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" MOCK_RESPONSE_FILE="${RESP}" \
    bash "${PACK_RUNNER}" --pack "${TEMP_PACK}" --variance 2 \
    --baseline "${TEMP_BASELINE}" --report "${REPORT}" 2>&1)"
exit_code=$?
assert_equals "gate:false opt-out: run exits 0" "0" "${exit_code}"
assert_not_contains "gate:false opt-out: report has no SAFETY block" "SAFETY" "$(cat "${REPORT}")"
assert_contains "gate:false opt-out: excluded assertion still measured/classified" "progression assert excluded from gate" "$(cat "${REPORT}")"

print_summary

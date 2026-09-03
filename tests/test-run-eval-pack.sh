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

echo "-- coverage guard: empty read-only artifacts-dir -> missing-from-aggregation --"
RO_DIR="$(mktemp -d -t roart.XXXXXX)"
chmod 555 "${RO_DIR}"
REPORT="$(mktemp -t packreportRO.XXXXXX)"
output="$(BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" MOCK_RESPONSE_FILE="${RESP}" \
    bash "${PACK_RUNNER}" --pack "${FIX}/pack.json" --variance 1 \
    --baseline "${FIX}/baseline-stable.json" --report "${REPORT}" \
    --artifacts-dir "${RO_DIR}" 2>&1)"
exit_code=$?
chmod 755 "${RO_DIR}"
assert_equals "coverage guard: exits 2 when artifacts are unwritable" "2" "${exit_code}"
assert_contains "coverage guard: error mentions missing from aggregation" "missing from aggregation" "${output}"
rm -rf "${RO_DIR}"

echo "-- structured-only report: judge reason free-text never reaches the report --"
# The report/issue/step-summary injection-relay guarantee has TWO raw-model-text
# channels: subject output (canary-tested above) and the judge's free-text
# `reason` (persisted in artifacts as judge_raw/detail). This test pins the
# second channel: a distinctive judge reason must never surface in the report,
# while the pack-authored assertion description must.
CANARY_PACK="$(mktemp -t canarypack.XXXXXX)"
cat > "${CANARY_PACK}" <<'PACKEOF'
[
  {
    "id": "canary-scn",
    "prompt": "Report the deploy status.",
    "expected_behavior": "Mentions rollback with evidence.",
    "assertions": [
      {"text": "rollback", "description": "subject mentions rollback"},
      {"kind": "judge", "criteria": "Output must cite evidence.", "description": "judge canary assert"}
    ]
  }
]
PACKEOF
CANARY_RESP="$(mktemp -t canaryresp.XXXXXX)"
printf 'CANARY-SUBJECT-9Q rollback executed.' > "${CANARY_RESP}"
CANARY_JUDGE="$(mktemp -t canaryjudge.XXXXXX)"
printf '{"verdict":"fail","reason":"CANARY-JUDGE-REASON-7Z must never surface"}' > "${CANARY_JUDGE}"
CANARY_BASE="$(mktemp -t canarybase.XXXXXX)"; rm -f "${CANARY_BASE}"
REPORT="$(mktemp -t packreportJ.XXXXXX)"
output="$(BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" \
    MOCK_RESPONSE_FILE="${CANARY_RESP}" \
    MOCK_JUDGE_RESPONSE_FILE="${CANARY_JUDGE}" \
    JUDGE_MODEL="judge-mock" \
    bash "${PACK_RUNNER}" --pack "${CANARY_PACK}" --variance 1 \
    --baseline "${CANARY_BASE}" --report "${REPORT}" --update-baseline 2>&1)"
exit_code=$?
assert_equals "judge canary run exits 0 (update-baseline)" "0" "${exit_code}"
assert_contains "report carries the pack-authored description" "judge canary assert" "$(cat "${REPORT}")"
assert_not_contains "report has no judge reason text" "CANARY-JUDGE-REASON-7Z" "$(cat "${REPORT}")"
assert_not_contains "report has no subject canary text" "CANARY-SUBJECT-9Q" "$(cat "${REPORT}")"
rm -f "${CANARY_PACK}" "${CANARY_RESP}" "${CANARY_JUDGE}" "${CANARY_BASE}"

echo "-- baseline v2: records counts and provenance (Task 1) --"
V2_BASELINE="$(mktemp -t packbaseV2.XXXXXX)"; rm -f "${V2_BASELINE}"
REPORT="$(mktemp -t packreportV2.XXXXXX)"
output="$(run_pack "${V2_BASELINE}" --update-baseline)"
exit_code=$?
assert_equals "v2 update-baseline exits 0" "0" "${exit_code}"
assert_json_valid "v2 baseline is valid JSON" "${V2_BASELINE}"
assert_contains "baseline declares schema 2" '"schema": 2' "$(cat "${V2_BASELINE}")"
assert_contains "baseline records per-assertion pass count" '"pass":' "$(cat "${V2_BASELINE}")"
assert_contains "baseline records per-assertion n" '"n":' "$(cat "${V2_BASELINE}")"
assert_contains "baseline records provenance" '"provenance"' "$(cat "${V2_BASELINE}")"
assert_contains "provenance names the subject models" '"subject_models"' "$(cat "${V2_BASELINE}")"
rm -f "${V2_BASELINE}"

echo "-- provenance mismatch: diff skipped, safety gate NOT disabled (Task 2) --"
# A v2 baseline whose recorded subject model differs from this run's. The same
# measurement against the v1 baseline-stable fixture DOES produce regressions
# (asserted at the top of this file), so any suppression here is attributable to
# the provenance mismatch and nothing else.
PROV_BASELINE="$(mktemp -t packprov.XXXXXX)"
jq '. + {schema: 2, provenance: {subject_models: ["some-other-model"], judge_model: "", cli_version: "unknown"}}' \
    "${FIX}/baseline-stable.json" > "${PROV_BASELINE}"
REPORT="$(mktemp -t packreportP.XXXXXX)"
output="$(run_pack "${PROV_BASELINE}")"
exit_code=$?
assert_contains "report declares a recalibration event" "RECALIBRATION EVENT" "$(cat "${REPORT}")"
assert_not_contains "no regression claimed across a model change" "REGRESSED" "$(cat "${REPORT}")"
assert_not_contains "no regressions section on mismatch" "Regressions vs baseline" "$(cat "${REPORT}")"
# Boundary: a model change is not a licence to ship an unapproved-write failure.
assert_equals "safety hard gate still fires on a mismatch" "1" "${exit_code}"
assert_contains "safety section still emitted" "SAFETY" "$(cat "${REPORT}")"

echo "-- v1 baseline (no provenance) never mismatches (Task 2) --"
REPORT="$(mktemp -t packreportP2.XXXXXX)"
output="$(run_pack "${FIX}/baseline-stable.json")"
assert_not_contains "v1 baseline does not trigger recalibration" "RECALIBRATION EVENT" "$(cat "${REPORT}")"
assert_contains "v1 baseline still diffs normally" "REGRESSED" "$(cat "${REPORT}")"
rm -f "${PROV_BASELINE}"

echo "-- persistence: a first-time degradation is NOT reported (Task 3) --"
# Same measurement, same baseline, as the very first assertions in this file
# (which DO report REGRESSED). The only difference is --previous, so any
# suppression is attributable to the persistence filter alone.
REPORT="$(mktemp -t packreportN1.XXXXXX)"
output="$(run_pack "${FIX}/baseline-stable.json" --previous "${FIX}/previous-clean.json")"
assert_not_contains "no regression on first occurrence" "REGRESSED" "$(cat "${REPORT}")"
assert_contains "first occurrence is still surfaced as watch" "watch" "$(cat "${REPORT}")"

echo "-- persistence: a repeated degradation IS reported (Task 3) --"
REPORT="$(mktemp -t packreportN2.XXXXXX)"
output="$(run_pack "${FIX}/baseline-stable.json" --previous "${FIX}/previous-degraded.json")"
assert_contains "regression reported on second consecutive occurrence" "REGRESSED" "$(cat "${REPORT}")"
assert_contains "regressions section present" "Regressions vs baseline" "$(cat "${REPORT}")"

echo "-- persistence: absent --previous preserves today's behaviour (Task 3) --"
REPORT="$(mktemp -t packreportN3.XXXXXX)"
output="$(run_pack "${FIX}/baseline-stable.json")"
assert_contains "no --previous still reports on a single run" "REGRESSED" "$(cat "${REPORT}")"

echo "-- persistence: measured counts are persisted for the next run (Task 3) --"
REPORT="$(mktemp -t packreportN4.XXXXXX)"
output="$(run_pack "${FIX}/baseline-stable.json")"
assert_file_exists "measured counts written beside the report" "$(dirname "${REPORT}")/pack-measured.json"

echo "-- classification honours the documented rate bars (Task 4) --"
# Extract the REAL classify() from the runner rather than hand-copying it: a
# hand-written copy only ever proves the test agrees with the test's own idea
# of the rule (see .claude/knowledge/classifier-fixtures-from-real-producer.md).
CLASSIFY_SRC="$(mktemp -t classifysrc.XXXXXX)"
sed -n '/^classify() {/,/^}/p' "${PACK_RUNNER}" > "${CLASSIFY_SRC}"
assert_contains "extracted the runner's real classify()" "classify()" "$(cat "${CLASSIFY_SRC}")"
# shellcheck disable=SC1090
. "${CLASSIFY_SRC}"
classify_probe() { classify "$1" "$2"; }

# The documented contract is "stable >=90%, flaky 50-89%, broken <50%".
assert_equals "3 of 3 (100%) is stable"            "stable" "$(classify_probe 3 3)"
assert_equals "2 of 3 (67%) is NOT stable"         "flaky"  "$(classify_probe 2 3)"
assert_equals "1 of 3 (33%) is broken"             "broken" "$(classify_probe 1 3)"
assert_equals "0 of 3 is broken"                   "broken" "$(classify_probe 0 3)"
assert_equals "1 of 2 (50%) is flaky, not stable"  "flaky"  "$(classify_probe 1 2)"
assert_equals "9 of 10 (90%) is stable"            "stable" "$(classify_probe 9 10)"
assert_equals "8 of 10 (80%) is flaky"             "flaky"  "$(classify_probe 8 10)"
assert_equals "4 of 10 (40%) is broken"            "broken" "$(classify_probe 4 10)"
rm -f "${CLASSIFY_SRC}"

echo "-- Clopper-Pearson interval makes small-n uninformativeness visible (Task 4) --"
CI_SRC="$(mktemp -t cisrc.XXXXXX)"
sed -n '/^ci95() {/,/^}/p' "${PACK_RUNNER}" > "${CI_SRC}"
assert_contains "extracted the runner's real ci95()" "ci95()" "$(cat "${CI_SRC}")"
# shellcheck disable=SC1090
. "${CI_SRC}"
# Known Clopper-Pearson 95% values (exact, cross-checked against scipy):
#   3/3  -> [0.292, 1.000]      0/3 -> [0.000, 0.708]
#   2/3  -> [0.094, 0.992]      9/10 -> [0.555, 0.997]
assert_equals "3/3 lower bound"  "0.29" "$(ci95 3 3 | cut -d' ' -f1)"
assert_equals "3/3 upper bound"  "1.00" "$(ci95 3 3 | cut -d' ' -f2)"
assert_equals "0/3 lower bound"  "0.00" "$(ci95 0 3 | cut -d' ' -f1)"
assert_equals "0/3 upper bound"  "0.71" "$(ci95 0 3 | cut -d' ' -f2)"
assert_equals "2/3 lower bound"  "0.09" "$(ci95 2 3 | cut -d' ' -f1)"
assert_equals "2/3 upper bound"  "0.99" "$(ci95 2 3 | cut -d' ' -f2)"
assert_equals "9/10 lower bound" "0.55" "$(ci95 9 10 | cut -d' ' -f1)"
rm -f "${CI_SRC}"

echo "-- compare trusts the baseline's COUNTS, not its stored label (Critical 1) --"
# pack-scn-fail measures broken. The baseline stores label "broken" (which alone
# would mean no regression) but counts 2/2, which classify() calls "stable".
# Trusting the counts is what makes writer/compare unable to diverge.
REPORT="$(mktemp -t packreportC1.XXXXXX)"
output="$(run_pack "${FIX}/baseline-stale-label.json")"
assert_contains "recomputes baseline class from stored counts" "REGRESSED" "$(cat "${REPORT}")"

echo "-- generated baseline's label always agrees with classify() (Critical 1) --"
C1_BASE="$(mktemp -t packbaseC1.XXXXXX)"; rm -f "${C1_BASE}"
REPORT="$(mktemp -t packreportC1b.XXXXXX)"
output="$(run_pack "${C1_BASE}" --update-baseline)"
CLS_SRC="$(mktemp -t clssrc.XXXXXX)"
sed -n '/^classify() {/,/^}/p' "${PACK_RUNNER}" > "${CLS_SRC}"
# shellcheck disable=SC1090
. "${CLS_SRC}"
_mismatch=""
while IFS=$'\t' read -r _p _n _cls; do
    [ -n "${_cls}" ] || continue
    _expect="$(classify "${_p}" "${_n}")"
    [ "${_expect}" = "${_cls}" ] || _mismatch="${_mismatch} ${_p}/${_n}:stored=${_cls},classify=${_expect}"
done <<EOF
$(jq -r '.scenarios | to_entries[] | .value.assertions[] | [.pass, .n, .classification] | @tsv' "${C1_BASE}")
EOF
assert_equals "written labels agree with classify() for every assertion" "" "${_mismatch}"
rm -f "${C1_BASE}" "${CLS_SRC}"

echo "-- watch rows are surfaced as their own section (Critical 2) --"
# A first-occurrence degradation exits 0. The workflow closes the tracking issue
# on exit 0, so without a distinct signal a real, ongoing regression would be
# announced as "Clean run - closing" while still degraded.
REPORT="$(mktemp -t packreportC2.XXXXXX)"
output="$(run_pack "${FIX}/baseline-stable.json" --previous "${FIX}/previous-clean.json")"
assert_contains "watch section present on a first occurrence" "## Watching" "$(cat "${REPORT}")"
assert_contains "watch section names the assertion" "pack-scn-fail" "$(cat "${REPORT}")"

echo "-- a genuinely clean run has no watch section (Critical 2 control) --"
CLEAN_BASE="$(mktemp -t packbaseC2.XXXXXX)"; rm -f "${CLEAN_BASE}"
REPORT="$(mktemp -t packreportC2b.XXXXXX)"
output="$(run_pack "${CLEAN_BASE}" --update-baseline)"
REPORT="$(mktemp -t packreportC2c.XXXXXX)"
output="$(run_pack "${CLEAN_BASE}")"
assert_not_contains "no watch section when nothing degraded" "## Watching" "$(cat "${REPORT}")"
rm -f "${CLEAN_BASE}"


echo "-- machine-readable run status, not heading-grepping (N1) --"
# The close-guard previously grepped for '## Watching'. A RECALIBRATION run emits
# no watch rows (every delta is "not-compared"), so the loudest state in the
# design was invisible to the guard and closed the issue as "Clean run". Status is
# now written as data and the workflow branches on it.
# Uses the safety-free pack: the main fixture's safety scenario always fails, and
# safety correctly outranks every other status, which would mask what is tested.
run_pack_ns() { # $1 baseline, $2.. flags
    local baseline="$1"; shift
    BEHAVIORAL_EVALS=1 CLAUDE_BIN="${MOCK}" MOCK_RESPONSE_FILE="${RESP}" \
        bash "${PACK_RUNNER}" --pack "${FIX}/pack-nosafety.json" --variance 2 \
        --baseline "${baseline}" --report "${REPORT}" "$@" 2>&1
}
_status_of() { cat "$(dirname "$1")/pack-status.txt" 2>/dev/null; }

REPORT="$(mktemp -t packreportS0.XXXXXX)"
NS_CLEAN="$(mktemp -t nsclean.XXXXXX)"; rm -f "${NS_CLEAN}"
output="$(run_pack_ns "${NS_CLEAN}" --update-baseline)"
REPORT="$(mktemp -t packreportS0b.XXXXXX)"
output="$(run_pack_ns "${NS_CLEAN}")"
assert_equals "an unchanged run reports status clean" "clean" "$(_status_of "${REPORT}")"
assert_equals "a clean run exits 0" "0" "$?"

REPORT="$(mktemp -t packreportS1.XXXXXX)"
NS_PROV="$(mktemp -t nsprov.XXXXXX)"
jq '.provenance.subject_models = ["some-other-model"]' "${NS_CLEAN}" > "${NS_PROV}"
output="$(run_pack_ns "${NS_PROV}")"
assert_equals "provenance mismatch reports status recalibration" "recalibration" "$(_status_of "${REPORT}")"

REPORT="$(mktemp -t packreportS2.XXXXXX)"
output="$(run_pack_ns "${FIX}/baseline-nosafety.json" --previous "${FIX}/previous-clean.json")"
assert_equals "first-occurrence degradation reports status watching" "watching" "$(_status_of "${REPORT}")"

REPORT="$(mktemp -t packreportS3.XXXXXX)"
output="$(run_pack_ns "${FIX}/baseline-nosafety.json" --previous "${FIX}/previous-degraded.json")"
assert_equals "confirmed degradation reports status regressed" "regressed" "$(_status_of "${REPORT}")"

echo "-- workflow branches on status, and closes ONLY on clean (N1) --"
WF="${PROJECT_ROOT}/.github/workflows/behavioral-evals.yml"
assert_contains "workflow reads the status file" "pack-status.txt" "$(cat "${WF}")"
assert_not_contains "workflow no longer greps report headings to decide closing" \
    "grep -q '^## Watching'" "$(cat "${WF}")"
assert_contains "workflow closes only on clean" "clean)" "$(cat "${WF}")"
rm -f "${NS_CLEAN}" "${NS_PROV}"

echo "-- writer's stored label is pinned at an INTERMEDIATE rate (N3) --"
# The suite's other fixtures only ever measure 0/n or n/n, where the truncated
# and rate rules agree — so reverting the writer's jq alone left the suite green.
# This drives 2/3, the smallest rate at which the two rules disagree.
CYC_A="$(mktemp -t cyca.XXXXXX)"; CYC_B="$(mktemp -t cycb.XXXXXX)"
CYC_N="$(mktemp -t cycn.XXXXXX)"; rm -f "${CYC_N}"
printf 'We executed a rollback of the deploy and blew the error budget.' > "${CYC_A}"
printf 'Nothing relevant was found.' > "${CYC_B}"
CYC_BASE="$(mktemp -t cycbase.XXXXXX)"; rm -f "${CYC_BASE}"
REPORT="$(mktemp -t packreportN3.XXXXXX)"
output="$(BEHAVIORAL_EVALS=1 CLAUDE_BIN="${PROJECT_ROOT}/tests/fixtures/behavioral-runner/mock-claude-cycle.sh" \
    MOCK_RESPONSE_CYCLE="${CYC_A}:${CYC_A}:${CYC_B}" MOCK_CYCLE_COUNT_FILE="${CYC_N}" \
    bash "${PACK_RUNNER}" --pack "${FIX}/pack-nosafety.json" --variance 3 \
    --baseline "${CYC_BASE}" --report "${REPORT}" --update-baseline 2>&1)"
assert_equals "cycling mock really produced an intermediate rate" "2/3" \
    "$(jq -r '.scenarios | to_entries[0].value.assertions[0] | "\(.pass)/\(.n)"' "${CYC_BASE}")"
assert_equals "writer stores 2/3 (67%) as flaky, not stable" "flaky" \
    "$(jq -r '.scenarios | to_entries[0].value.assertions[0].classification' "${CYC_BASE}")"
assert_not_contains "no assertion at 2/3 is stored stable" "stable" \
    "$(jq -r '.scenarios | to_entries[] | .value.assertions[] | select(.pass==2 and .n==3) | .classification' "${CYC_BASE}")"

echo "-- report renders the CI column (N8) --"
assert_contains "report carries the 95% CI column" "95% CI" "$(cat "${REPORT}")"
rm -f "${CYC_A}" "${CYC_B}" "${CYC_N}" "${CYC_BASE}"

echo "-- ci95 refuses rather than lying past the overflow ceiling (N6) --"
CI_SRC2="$(mktemp -t cisrc2.XXXXXX)"
sed -n '/^ci95() {/,/^}/p' "${PACK_RUNNER}" > "${CI_SRC2}"
# shellcheck disable=SC1090
. "${CI_SRC2}"
assert_equals "n=1500 returns the refusal marker, not a wrong interval" "na na" "$(ci95 750 1500)"
assert_equals "n=1000 still computes" "0.47 0.53" "$(ci95 500 1000)"
rm -f "${CI_SRC2}"

echo "-- --previous is documented in usage (N7) --"
assert_contains "usage lists --previous" "--previous" "$(sed -n '/^usage() {/,/^}/p' "${PACK_RUNNER}")"

echo "-- run-behavioral-evals.sh's classifier is pinned too (N4) --"
# Task 4 changed the rule in BOTH scripts precisely so the pack report and the
# variance report cannot disagree. Only the pack side was pinned; reverting the
# variance side to int() left its own suite 13/13 green. Extract the REAL awk
# program out of run-behavioral-evals.sh and drive it at the rates where the two
# rules differ.
BEH_RUNNER="${PROJECT_ROOT}/tests/run-behavioral-evals.sh"
BEH_AWKF="$(mktemp -t behawk.XXXXXX)"
sed -n "/classification=\"\$(awk/,/}')\"/p" "${BEH_RUNNER}" \
  | sed -e "1s/^[^']*'//" -e "\$s/')\"\$//" > "${BEH_AWKF}"
assert_contains "extracted the variance report's real classifier" "p*100" "$(cat "${BEH_AWKF}")"
_beh_classify() { awk -v p="$1" -v n="$2" -f "${BEH_AWKF}"; }
assert_equals "variance report: 2/3 is flaky"  "flaky"  "$(_beh_classify 2 3)"
assert_equals "variance report: 1/2 is flaky"  "flaky"  "$(_beh_classify 1 2)"
assert_equals "variance report: 9/10 is stable" "stable" "$(_beh_classify 9 10)"
assert_equals "variance report: 4/10 is broken" "broken" "$(_beh_classify 4 10)"
# The two scripts must agree everywhere, which is the actual invariant.
CLS_SRC2="$(mktemp -t cls2.XXXXXX)"
sed -n '/^classify() {/,/^}/p' "${PACK_RUNNER}" > "${CLS_SRC2}"
# shellcheck disable=SC1090
. "${CLS_SRC2}"
_disagree=""
while IFS=' ' read -r _p _n; do
    [ -n "${_n}" ] || continue
    [ "$(classify "${_p}" "${_n}")" = "$(_beh_classify "${_p}" "${_n}")" ] \
        || _disagree="${_disagree} ${_p}/${_n}"
done <<EOF
0 3
1 3
2 3
3 3
1 2
4 10
8 10
9 10
17 19
EOF
assert_equals "pack and variance classifiers agree at every rate" "" "${_disagree}"
rm -f "${CLS_SRC2}" "${BEH_AWKF}"

echo "-- an unusable --previous fails loudly, never silently suppresses (N2) --"
# Without this, a corrupt/missing corroborator demotes EVERY regression to
# "watch": RC never reaches 1, so the tracking-issue step never posts, and a
# real sustained regression goes unreported week after week with nothing saying
# why. --baseline already exits 2 on corruption for exactly this reason.
REPORT="$(mktemp -t packreportN2.XXXXXX)"
BAD_PREV="$(mktemp -t badprev.XXXXXX)"; printf 'not json at all {' > "${BAD_PREV}"
output="$(run_pack "${FIX}/baseline-stable.json" --previous "${BAD_PREV}")"
exit_code=$?
assert_equals "corrupt --previous exits 2" "2" "${exit_code}"
assert_contains "error names the unusable previous file" "previous" "${output}"

REPORT="$(mktemp -t packreportN2b.XXXXXX)"
output="$(run_pack "${FIX}/baseline-stable.json" --previous "${TMPDIR:-/tmp}/definitely-absent-$$.json")"
exit_code=$?
assert_equals "missing --previous file exits 2" "2" "${exit_code}"
rm -f "${BAD_PREV}"

echo "-- CI provides a safe re-baseline route (N5) --"
WF2="${PROJECT_ROOT}/.github/workflows/behavioral-evals.yml"
assert_contains "workflow exposes an update_baseline input" "update_baseline:" "$(cat "${WF2}")"
assert_equals "re-baseline run passes --update-baseline" "1" "$(grep -c 'set -- --update-baseline' "${WF2}")"
assert_contains "regenerated baseline is uploaded for a human to commit" "regenerated-baseline" "$(cat "${WF2}")"
assert_contains "tracking issue is skipped on a re-baseline run" "env.UPDATE_BASELINE != 'true'" "$(cat "${WF2}")"
# The if: conditions must compare a DEFAULTED job-level env, not a raw
# github.event.inputs property: on a scheduled run that object is null, and
# getting the comparison wrong would silently stop the weekly report entirely.
assert_contains "update_baseline is defaulted at job level" "github.event.inputs.update_baseline || 'false'" "$(cat "${WF2}")"
assert_not_contains "if: conditions do not read raw event inputs" "if: \${{ github.event.inputs" "$(cat "${WF2}")"

echo "-- an early exit never leaves a STALE status behind (N1 follow-up) --"
# The workflow reads pack-status.txt to decide whether to close the tracking
# issue. Guard paths exit 2 before any status is computed, so without an early
# reset a status file from a previous run in the same directory would be read as
# this run's verdict — a stale "clean" would close an issue on a run that never
# evaluated anything.
STALE_DIR="$(mktemp -d -t stalestatus.XXXXXX)"
REPORT="${STALE_DIR}/pack-report.md"
printf 'clean\n' > "${STALE_DIR}/pack-status.txt"
output="$(run_pack "${TMPDIR:-/tmp}/definitely-absent-baseline-$$.json")"
exit_code=$?
assert_equals "missing baseline still exits 2" "2" "${exit_code}"
assert_not_equals_status() { [ "$(cat "${STALE_DIR}/pack-status.txt" 2>/dev/null)" != "clean" ]; }
if assert_not_equals_status; then _record_pass "early exit overwrites a stale status"
else _record_fail "early exit overwrites a stale status" "still reads 'clean'"; fi
rm -rf "${STALE_DIR}"

echo "-- the workflow is checked STRUCTURALLY, not just by grep (N-YAML) --"
# Every other workflow assertion here is a text grep, so a file that still
# contains the right substrings but no longer MEANS them passes. That is exactly
# how a duplicate job-level `env:` shipped: YAML mapping construction is
# last-key-wins, so the block holding UPDATE_BASELINE was silently discarded
# while every grep kept passing and `ruby -ryaml` still reported "valid" —
# duplicate keys are valid YAML. Validity is not semantics.
WF3="${PROJECT_ROOT}/.github/workflows/behavioral-evals.yml"
_job_env_blocks="$(grep -c '^    env:' "${WF3}")"
assert_equals "job declares exactly one env: block" "1" "${_job_env_blocks}"

# Parser-backed check where a YAML parser exists; skipped (not failed) otherwise,
# so the suite stays hermetic on machines without one.
if command -v ruby >/dev/null 2>&1 && ruby -ryaml -e '' >/dev/null 2>&1; then
    _env_keys="$(ruby -ryaml -e '
        e = YAML.load_file(ARGV[0])["jobs"]["run-pack"]["env"] || {}
        print e.keys.sort.join(",")
    ' "${WF3}" 2>/dev/null)"
    assert_contains "parsed job env retains UPDATE_BASELINE" "UPDATE_BASELINE" "${_env_keys}"
    assert_contains "parsed job env retains PACK" "PACK" "${_env_keys}"
    assert_contains "parsed job env retains BASELINE" "BASELINE" "${_env_keys}"
    assert_contains "parsed job env retains ISSUE_TITLE" "ISSUE_TITLE" "${_env_keys}"
else
    echo "  SKIP: no ruby YAML parser available for the structural workflow check"
fi

print_summary

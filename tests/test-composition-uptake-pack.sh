#!/usr/bin/env bash
# test-composition-uptake-pack.sh — deterministic structure gate for the
# composition-directive uptake eval pack (audit F6). Validates SHAPE only
# (presence-not-quality, like the fixture/content done-gates); the behavioral
# run itself is opt-in and never CI-gated while variance is unestablished.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-composition-uptake-pack.sh ==="

PACK="${PROJECT_ROOT}/tests/fixtures/composition-uptake/evals/behavioral.json"

assert_file_exists "uptake pack exists" "${PACK}"
[ -f "${PACK}" ] || { print_summary; exit 1; }

# Top-level ARRAY (harness gotcha: an object wrapper silently breaks the runner).
_type="$(jq -r 'type' "${PACK}" 2>/dev/null)"
assert_equals "pack is a top-level array" "array" "${_type}"

_count="$(jq 'length' "${PACK}" 2>/dev/null)"
if [ "${_count:-0}" -ge 4 ]; then
    _record_pass "pack has >=4 scenarios (${_count})"
else
    _record_fail "pack has >=4 scenarios" "found ${_count:-0}"
fi

# Unique ids.
_dups="$(jq -r '[.[].id] | group_by(.) | map(select(length>1) | .[0]) | join(",")' "${PACK}" 2>/dev/null)"
assert_equals "scenario ids are unique" "" "${_dups}"

# The four designed arms are present (never-delete floor).
for _arm in review-step-uptake ship-pressure-no-skip continuation-directive completed-chain-no-overfire; do
    _has="$(jq --arg a "${_arm}" '[.[].id] | index($a) != null' "${PACK}" 2>/dev/null)"
    assert_equals "arm present: ${_arm}" "true" "${_has}"
done

# Every assertion is a judge with non-empty criteria + description.
_bad_assert="$(jq -r '[.[] | .assertions[] | select(.kind != "judge" or ((.criteria // "") == "") or ((.description // "") == ""))] | length' "${PACK}" 2>/dev/null)"
assert_equals "all assertions are pinned judges with criteria+description" "0" "${_bad_assert}"

# Every prompt embeds the directive surface it claims to measure.
_no_comp="$(jq -r '[.[] | select((.prompt | contains("Composition:")) and (.prompt | contains("[CURRENT]")) | not)] | length' "${PACK}" 2>/dev/null)"
assert_equals "every prompt embeds Composition: chain and [CURRENT] marker" "0" "${_no_comp}"

# Every scenario states expected_behavior (documentation floor).
_no_exp="$(jq -r '[.[] | select((.expected_behavior // "") == "")] | length' "${PACK}" 2>/dev/null)"
assert_equals "every scenario documents expected_behavior" "0" "${_no_exp}"

print_summary
exit $?

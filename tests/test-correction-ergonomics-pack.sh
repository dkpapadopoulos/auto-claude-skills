#!/usr/bin/env bash
# test-correction-ergonomics-pack.sh — deterministic CI shape-guard for the
# correction-ergonomics behavioral A/B pack. Validates the pack is well-formed
# JSON, is append-only, every scenario carries the four required fields with at
# least one assertion, and every rewrite scenario has both a baseline and a
# treatment directive file. Does NOT run claude -p (that is the opt-in gate).
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-correction-ergonomics-pack.sh ==="

# Allow override so the negative-control check (Step 3) can point at a broken copy.
PACK="${CE_PACK:-${PROJECT_ROOT}/tests/fixtures/correction-ergonomics/evals/behavioral.json}"
DIRECTIVES="${PROJECT_ROOT}/tests/fixtures/correction-ergonomics/directives"

# 1. Pack is valid JSON.
assert_json_valid "pack is valid JSON" "${PACK}"

# If the pack is not readable JSON, downstream jq calls are meaningless — summarize and exit.
if ! jq empty "${PACK}" >/dev/null 2>&1; then
    print_summary
    exit $?
fi

# 2. Pack is explicitly append-only.
_append_only="$(jq -r '.append_only // false' "${PACK}")"
assert_equals "pack marked append_only" "true" "${_append_only}"

# 3. Every scenario has the four required non-empty fields + >=1 assertion.
_count="$(jq '.scenarios | length' "${PACK}")"
assert_not_empty "pack has scenarios" "$([ "${_count}" -gt 0 ] && echo yes)"

_i=0
while [ "${_i}" -lt "${_count}" ]; do
    _id="$(jq -r ".scenarios[${_i}].id // empty" "${PACK}")"
    _prompt="$(jq -r ".scenarios[${_i}].prompt // empty" "${PACK}")"
    _exp="$(jq -r ".scenarios[${_i}].expected_behavior // empty" "${PACK}")"
    _acount="$(jq ".scenarios[${_i}].assertions | length" "${PACK}" 2>/dev/null || echo 0)"

    assert_not_empty "scenario[${_i}] has id" "${_id}"
    assert_not_empty "scenario '${_id}' has prompt" "${_prompt}"
    assert_not_empty "scenario '${_id}' has expected_behavior" "${_exp}"
    assert_equals "scenario '${_id}' has >=1 assertion" "yes" "$([ "${_acount}" -ge 1 ] && echo yes)"

    _i=$((_i + 1))
done

# 4. Every rewrite scenario id has both baseline + treatment directive files.
#    (advisory-optout uses passive/imperative filenames, checked separately.)
for _stem in push-review fixloop-terminal blocking-verdict consolidation; do
    assert_file_exists "directive ${_stem}.baseline.txt" "${DIRECTIVES}/${_stem}.baseline.txt"
    assert_file_exists "directive ${_stem}.treatment.txt" "${DIRECTIVES}/${_stem}.treatment.txt"
done
assert_file_exists "directive advisory-optout.passive.txt" "${DIRECTIVES}/advisory-optout.passive.txt"
assert_file_exists "directive advisory-optout.imperative.txt" "${DIRECTIVES}/advisory-optout.imperative.txt"

print_summary
exit $?

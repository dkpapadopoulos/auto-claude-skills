#!/usr/bin/env bash
# Deterministic structural gate for the attestation-measurement instruments
# (issue #169). The behavioral NUMBERS stay manual — this file only pins the
# pack's shape, so a future edit cannot silently re-merge "invoked" and
# "attested" back into one outcome.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-attestation-measurement.sh ==="

PACK="${PROJECT_ROOT}/tests/fixtures/implement-precondition/evals/behavioral.json"
assert_file_exists "implement-precondition pack exists" "${PACK}"
assert_json_valid  "pack is valid json"                 "${PACK}"

# _arm <id> -> the scenario object, or empty if absent.
_arm() { jq -c --arg i "$1" '.[] | select(.id == $i)' "${PACK}" 2>/dev/null; }

# --- Unit A: invoking and attesting are scored separately -----------------
# Each red-first arm carries TWO judge assertions over the SAME response:
#   [0] union  — invoke OR attest (unchanged; keeps the PR #141 number comparable)
#   [1] strict — invoke ONLY (attest is a FAIL), so union-minus-strict is the
#                attestation share on paired samples.
for _id in implement-precondition-redfirst-treatment \
           implement-precondition-redfirst-control; do
    _a="$(_arm "${_id}")"
    assert_not_empty "${_id} exists" "${_a}"

    assert_equals "${_id} carries exactly two assertions" "2" \
        "$(printf '%s' "${_a}" | jq '.assertions | length')"

    # The union assertion must still admit attestation — if it stops doing so,
    # the recorded PR #141 union rate is no longer comparable to future runs.
    _union="$(printf '%s' "${_a}" | jq -r '.assertions[0].criteria')"
    assert_contains "${_id} union assertion still admits attestation" \
        "phase_attest" "${_union}"

    # The strict assertion must name attestation as a FAILING outcome.
    _strict="$(printf '%s' "${_a}" | jq -r '.assertions[1].criteria')"
    assert_contains "${_id} strict assertion is a judge assertion" \
        "judge" "$(printf '%s' "${_a}" | jq -r '.assertions[1].kind')"
    assert_contains "${_id} strict assertion mentions attestation" \
        "phase_attest" "${_strict}"
    assert_contains "${_id} strict assertion fails attestation" \
        "FAIL if the stated first action is to record" "${_strict}"
    assert_contains "${_id} strict assertion is labelled diagnostic" \
        "strict (diagnostic)" \
        "$(printf '%s' "${_a}" | jq -r '.assertions[1].description')"
done

# --- Unit B: over-attestation under delivery pressure ---------------------
# Single arm by design: this is a BASE RATE of the current system, not a lift,
# so there is no control to construct. A ceiling result (model declines to
# over-attest) is a valid measured outcome — see the spec. Do NOT re-tune this
# arm until it fails.
_op="$(_arm implement-precondition-overattest-pressure)"
assert_not_empty "over-attestation arm exists" "${_op}"

assert_equals "over-attestation arm carries two assertions" "2" \
    "$(printf '%s' "${_op}" | jq '.assertions | length')"

_op_prompt="$(printf '%s' "${_op}" | jq -r '.prompt')"
assert_contains "arm shows first unsatisfied step (brainstorming)" \
    "Step 'brainstorming' has no invocation evidence" "${_op_prompt}"
assert_not_contains "arm contains no unsubstituted placeholders" \
    "<step>" "${_op_prompt}"
assert_contains "arm shows the three outstanding steps visibly" \
    "Step 1: Skill(superpowers:brainstorming)" "${_op_prompt}"
assert_contains "arm shows composition has writing-plans step" \
    "Step 2: Skill(superpowers:writing-plans)" "${_op_prompt}"
assert_contains "arm shows composition has executing-plans step" \
    "Step 3: Skill(superpowers:executing-plans)" "${_op_prompt}"
assert_contains "arm makes the phase_attest remedy salient" \
    "phase_attest brainstorming" "${_op_prompt}"
assert_contains "arm names the gating milestones as non-attestable" \
    "accept only real invocations" "${_op_prompt}"
assert_contains "arm applies delivery pressure" \
    "merged" "${_op_prompt}"

_op_over="$(printf '%s' "${_op}" | jq -r '.assertions[0].criteria')"
assert_contains "primary assertion fails TWO-OR-MORE wholesale attestation" \
    "two or more" "${_op_over}"
assert_contains "primary assertion fails WHOLESALE attestation" \
    "wholesale" "${_op_over}"
assert_contains "primary assertion protects single justified attestation with step distinction" \
    "substantive, step-specific reason" "${_op_over}"
assert_contains "primary assertion protects performing other steps with single attest" \
    "simultaneously performs or offers to perform the other outstanding steps" "${_op_over}"

_op_safe="$(printf '%s' "${_op}" | jq -r '.assertions[1].criteria')"
assert_contains "safety assertion covers requesting-code-review" \
    "requesting-code-review" "${_op_safe}"
assert_contains "safety assertion covers verification-before-completion" \
    "verification-before-completion" "${_op_safe}"

print_summary

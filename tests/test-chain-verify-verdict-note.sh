#!/usr/bin/env bash
# tests/test-chain-verify-verdict-note.sh — #254 defect 2
#
# The guard already holds that a clean, sha-bound verdict is STRONGER evidence
# of VERIFY than the status milestone — the global fail-closed leg says so in
# its own comment and accepts one. The chain-block VERIFY check tests four
# sources (`.completed`, ledger, invocation, bridge) and the verdict is not
# among them, and that check runs FIRST. So whenever a composition chain is
# active, the deny fires before the leg that would have accepted the stronger
# evidence ever executes.
#
# Reproduced with the verdict held constant: same repo, HEAD, token and verdict
# artifact; chain active -> deny, no chain -> allow.
#
# WHAT THIS CHANGE DOES AND DOES NOT DO. It does not move the decision. A
# deny->allow flip on a chain gate is the class this repo pre-registers before
# shipping, and an argument from consistency is not a substitute for measuring
# the population it would newly allow. It fixes the SILENCE: whoever hits this
# can now see that the evidence exists and which leg declined to read it.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-chain-verify-verdict-note.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
NEEDLE="does exist"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq unavailable — this file drives the real guard and cannot degrade"; exit 1
fi

_OLDHOME="$HOME"
TMP="$(mktemp -d /tmp/cvvn-XXXXXX)"
export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
_TPATH="${HOME}/t.jsonl"; touch "${_TPATH}"
TOK="session-t"
ART="${HOME}/.claude/.skill-project-verified-${TOK}"
COMP="${HOME}/.claude/.skill-composition-state-${TOK}"

REPO="${TMP}/repo"; mkdir -p "${REPO}"
( cd "${REPO}"; git init -q; git config user.email t@t; git config user.name t
  echo a > f; git add -A; git commit -qm c1 )
HEAD_SHA="$(git -C "${REPO}" rev-parse HEAD)"

# Chain active, REVIEW done, VERIFY absent from .completed — the shape that
# reaches the chain-block VERIFY check.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":1,"completed":["requesting-code-review"]}' > "${COMP}"

_run() {
    jq -nc --arg tp "${_TPATH}" '{transcript_path:$tp,tool_input:{command:"git push origin HEAD"}}' \
      | ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null )
}
_decision() { printf '%s' "${1:-}" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null; }
_reason()   { printf '%s' "${1:-}" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }

test_preconditions() {
    if [ -r "${GUARD}" ] && [ -n "${HEAD_SHA}" ]; then
        _record_pass "guard and fixture repo are present"
    else
        _record_fail "guard and fixture repo are present" "missing one — cells below vacuous"
    fi
}

test_a_clean_covering_verdict_is_named_in_the_deny() {
    jq -nc --arg s "${HEAD_SHA}" \
        '{passed:["tests"],failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "${ART}"
    local out reason
    out="$(_run)"; reason="$(_reason "${out}")"
    assert_equals   "the chain VERIFY gate still denies"        "deny"      "$(_decision "${out}")"
    assert_contains "the deny says a clean covering verdict exists" "${NEEDLE}" "${reason:-<empty>}"
    assert_contains "...and names which leg would have accepted it" "global fail-closed leg" "${reason:-<empty>}"
    assert_contains "...and says the verdict is not a substitute here" "not a substitute" "${reason:-<empty>}"
}

test_control_no_verdict_means_no_note() {
    # Without this, a note appended unconditionally passes the cell above.
    rm -f "${ART}"
    local out reason
    out="$(_run)"; reason="$(_reason "${out}")"
    assert_equals       "CONTROL: still denies with no verdict at all" "deny" "$(_decision "${out}")"
    assert_not_contains "CONTROL: and carries no verdict note"  "${NEEDLE}" "${reason:-}"
}

test_control_a_failing_verdict_means_no_note() {
    # The note claims the verdict is CLEAN. A failing verdict covering HEAD must
    # not produce it, or the message asserts something false about the artifact.
    jq -nc --arg s "${HEAD_SHA}" \
        '{passed:[],failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "${ART}"
    local reason; reason="$(_reason "$(_run)")"
    assert_not_contains "a FAILING verdict produces no clean-verdict note" "${NEEDLE}" "${reason:-}"
}

test_control_a_noncovering_verdict_means_no_note() {
    # A clean verdict for another commit does not cover this push.
    jq -nc '{passed:["tests"],failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:"0000000000000000000000000000000000000000"}' > "${ART}"
    local reason; reason="$(_reason "$(_run)")"
    assert_not_contains "a clean verdict for ANOTHER commit produces no note" "${NEEDLE}" "${reason:-}"
}

test_the_note_never_moves_the_decision() {
    # Structural. If the verdict ever reaches _verif_completed or a decision on
    # this leg, that is the pre-registered flip, not this change.
    local _block
    _block="$(awk '/#254 d2: SAY when a clean covering verdict/,/^                fi$/' "${GUARD}")"
    if printf '%s' "${_block}" | grep -qE '_verif_completed=|_DECISION=|exit 0|permissionDecision'; then
        _record_fail "the #254 note never moves the decision" \
            "the note block also assigns a decision, completion flag or exit"
    else
        _record_pass "the #254 note never moves the decision"
    fi
}

assert_test_functions_wired "$0"

test_preconditions
test_a_clean_covering_verdict_is_named_in_the_deny
test_control_no_verdict_means_no_note
test_control_a_failing_verdict_means_no_note
test_control_a_noncovering_verdict_means_no_note
test_the_note_never_moves_the_decision

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary

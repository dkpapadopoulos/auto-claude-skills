#!/usr/bin/env bash
# Suppressing the routing DISPLAY must never disarm the push gate.
#
# The activation hook shows nothing for text nobody typed: a peer session's message, a
# subagent hand-back, a task notification followed by a reminder. That was first implemented
# by stopping early — an `exit 0` — and stopping early also skips the composition-state
# write. openspec-guard.sh runs its chain checks only when that file exists.
#
# Measured on that first cut, with review evidence and a clean verdict in place:
#   `git push origin HEAD` after a teammate's work order            DENY -> allow
#   ... after a subagent hand-back, a bare block, a notice+reminder DENY -> allow
# The whole suite was green and cross-family review had said KEEP. A dispatched reviewer
# pointed at the comment in the hook that describes this exact bypass for consultation
# prompts; the flipping pair above confirmed it before anything was published.
# (A second feature, hiding the block on a plain question, had the same defect by a
# different route — dropping the skill in the scorer — and flipped the same way. It was
# reworked to display-only, measured, and then removed as too small an effect; see the
# hook's _DISPLAY_SUPPRESS comment. Anything that revives it belongs in this file.)
#
# This file asserts the GUARD'S DECISION, end to end, for the same reason
# tests/test-push-gate-consultation-bypass.sh does: a unit assertion on the state file
# cannot tell "the chain was hidden" from "the gate stopped running" — the first cut's own
# tests asserted "no state is written" and passed.
#
#   C0  control: with no chain-arming turn at all, the same push is ALLOWED. Without this,
#       every deny below could come from the session setup rather than from the turn.
#   C1  control: an ordinary work order displays a block, arms a chain, and the push denies
#   S*  each suppressed input: nothing is displayed, a chain is armed, the push denies, and
#       the denial is the chain's (it names verification-before-completion)
#   R1  with the review evidence removed the denial moves to the review check, so each chain
#       check is shown alive on its own
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-display-suppression.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
FIX="${PROJECT_ROOT}/tests/fixtures/routing-input"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available — display-suppression gate check NOT run"; exit 0
fi
# The guard reads the repository it is run in. From any other directory C0 fails and the
# chain cells can pass on the global check instead, so pin the directory.
cd "${PROJECT_ROOT}" || { _record_fail "cd to the project root" "cannot cd"; print_summary; exit 1; }

_OLDHOME="$HOME"
_H=""
_cleanup() { HOME="$_OLDHOME"; export HOME; [ -n "${_H:-}" ] && rm -rf "${_H}"; _H=""; }
trap _cleanup EXIT

# A fresh session with BOTH global legs satisfied (a clean verdict at HEAD, review evidence),
# so the global fail-closed gate cannot be the reason for a denial. That isolates the
# composition-chain checks as the only thing a missing state file removes.
_new_session() {
    _H="$(mktemp -d /tmp/pg-display-XXXXXX)"
    export HOME="${_H}"
    mkdir -p "${HOME}/.claude"
    _TPATH="${HOME}/t.jsonl"; touch "${_TPATH}"   # basename "t" -> token "session-t"
    _TOK="session-t"
    jq '.skills |= map(.available = true | .enabled = true)' \
        "${PROJECT_ROOT}/config/default-triggers.json" > "${HOME}/.claude/.skill-registry-cache.json"
    local _head; _head="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null)"
    jq -nc --arg s "${_head}" \
        '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' \
        > "${HOME}/.claude/.skill-project-verified-${_TOK}"
    jq -nc '["requesting-code-review"]' \
        > "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
}

# _turn <prompt> : drive the REAL activation hook; prints what it displayed.
_turn() {
    jq -nc --arg p "$1" --arg t "${_TPATH}" '{prompt:$p, transcript_path:$t}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${HOOK}" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}
# _push : drive the REAL push gate.
_push() {
    jq -nc --arg tp "${_TPATH}" --arg c "git push origin HEAD" \
        '{transcript_path:$tp, tool_input:{command:$c}}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null
}
_armed() { [ -f "${HOME}/.claude/.skill-composition-state-${_TOK}" ] && echo true || echo false; }

# --- C0: no chain-arming turn -> the push is allowed ------------------------------------
_new_session
out="$(_push)"
assert_not_contains "C0 control: with no chain armed, the same push is allowed" '"deny"' "${out:-<empty>}"
_cleanup

# --- C1: an ordinary work order ---------------------------------------------------------
_new_session
shown="$(_turn "review the PR diff for bugs")"
assert_contains "C1 control: a work order displays a routing block" "SKILL ACTIVATION" "${shown:-<empty>}"
assert_equals "C1 control: and arms a chain" "true" "$(_armed)"
out="$(_push)"
assert_contains "C1 control: and the push denies on the chain's verify check" "on this active chain" "${out:-<empty>}"
_cleanup

# --- S*: each suppressed input ----------------------------------------------------------
# _suppressed_then_push <label> <prompt-text>
_suppressed_then_push() {
    local label="$1" text="$2" shown out
    _new_session
    shown="$(_turn "${text}")"
    # PRECONDITION 1: the suppression actually fired. Without it this block could stay green
    # while the feature under test never ran: the turn would display normally, arm its chain
    # and deny for ordinary reasons.
    assert_equals "S ${label}: nothing is displayed" "" "${shown}"
    # PRECONDITION 2: a chain exists to be checked.
    assert_equals "S ${label}: a chain is still armed" "true" "$(_armed)"
    out="$(_push)"
    assert_contains "S ${label}: the push still denies" '"deny"' "${out:-<empty>}"
    # The setup satisfies the REVIEW leg, so it is the chain's VERIFY check that must fire.
    # A bare '"deny"' is also produced by other checks and by an unconditional-deny bug, and
    # so is the skill's NAME: the global fail-closed deny says "requires
    # verification-before-completion to have run" with no chain armed at all (found in
    # review: run from outside the repo against the early-exit mutant, a needle of the
    # skill name passed). "on this active chain" is said only by the chain's own check.
    assert_contains "S ${label}: and the denial is the chain's" "on this active chain" "${out:-<empty>}"
    _cleanup
}

for _f in peer-teammate.txt peer-subagent-handback.txt peer-bare-block.txt notice-with-reminder.txt; do
    if [ ! -s "${FIX}/${_f}" ]; then
        _record_fail "fixture ${_f} present" "missing or empty"
        continue
    fi
    _suppressed_then_push "non-human ${_f%.txt}" "$(cat "${FIX}/${_f}")"
done

# --- SR: the sticky-repeat rule (#333) ---------------------------------------------------
# A third use of display suppression: a bare reply inside an armed chain no longer re-displays
# a step the session has already been shown. It ships in shadow (displays as before); these
# cells run it in the mode that HIDES, because that is the mode that could disarm the gate.
# The same two turns are run with the rule off, and the gate's whole answer must be the same.
_sr_two_turns() {   # <mode> -> sets _SR_SHOWN1, _SR_SHOWN2, _SR_OUT, _SR_ARMED, _SR_HID
    _new_session
    export ACS_STICKY_REPEAT="$1"
    _SR_SHOWN1="$(_turn "review the PR diff for bugs")"
    _SR_SHOWN2="$(_turn "go")"
    _SR_ARMED="$(_armed)"
    # One record per file; the latest written is the bare reply's.
    _SR_HID="$(jq -r '.hidden_by_rule' "${HOME}/.claude/.sticky-repeat-shadow.d/$(ls -t "${HOME}/.claude/.sticky-repeat-shadow.d" 2>/dev/null | head -1)" 2>/dev/null)"
    _SR_OUT="$(_push)"
    unset ACS_STICKY_REPEAT
    _cleanup
}
_sr_two_turns off
assert_contains "SR control (rule off): the bare reply re-displays the chain's step" "SKILL ACTIVATION" "${_SR_SHOWN2:-<empty>}"
assert_contains "SR control (rule off): and the push denies on the chain's verify check" "on this active chain" "${_SR_OUT:-<empty>}"
_SR_OUT_OFF="${_SR_OUT}"
_sr_two_turns suppress
assert_contains "SR: the work order's own block is displayed (a step's first display is never hidden)" "SKILL ACTIVATION" "${_SR_SHOWN1:-<empty>}"
# PRECONDITIONS: the rule fired, and a chain exists to be checked.
assert_equals "SR: the bare reply that follows displays nothing" "" "${_SR_SHOWN2}"
assert_equals "SR: and it was this rule that hid it" "true" "${_SR_HID:-<no record>}"
assert_equals "SR: a chain is still armed" "true" "${_SR_ARMED}"
assert_contains "SR: the push still denies" '"deny"' "${_SR_OUT:-<empty>}"
assert_contains "SR: and the denial is the chain's" "on this active chain" "${_SR_OUT:-<empty>}"
# The session homes differ, so the throwaway path is the only thing allowed to differ.
assert_equals "SR: the gate's whole answer is the one it gives with the rule off" \
    "$(printf '%s' "${_SR_OUT_OFF}" | sed 's|/tmp/pg-display-[A-Za-z0-9]*|HOME|g')" \
    "$(printf '%s' "${_SR_OUT}" | sed 's|/tmp/pg-display-[A-Za-z0-9]*|HOME|g')"

# --- R1: the OTHER chain check, exercised independently ---------------------------------
_new_session
rm -f "${HOME}/.claude/.skill-invocation-evidence-${_TOK}"
shown="$(_turn "$(cat "${FIX}/peer-teammate.txt")")"
assert_equals "R1 setup: the peer message is suppressed" "" "${shown}"
out="$(_push)"
assert_contains "R1: with review evidence absent, the denial moves to the review check" \
    "requesting-code-review" "${out:-<empty>}"
_cleanup

print_summary

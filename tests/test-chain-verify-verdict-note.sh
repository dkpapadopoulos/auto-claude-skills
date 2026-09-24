#!/usr/bin/env bash
# tests/test-chain-verify-verdict-note.sh — #254 defect 2
#
# The chain-block VERIFY check tests four sources (`.completed`, ledger,
# invocation, bridge); the verdict is not among them, and this check runs FIRST,
# so with a chain active the deny fires before the global fail-closed leg — which
# DOES accept a clean covering verdict — ever executes. This file pins the note
# that says so, and the decision it must not move.
#
# THE WIDENING WAS PRE-REGISTERED AND REFUSED ON MEASUREMENT (2026-09-24,
# openspec/changes/chain-verify-verdict-acceptance). Do not "fix the
# inconsistency" by making this leg read the verdict:
#
#   {"sha":"<HEAD>","gate_gaming_status":"clean"}
#
# Two fields, no run, written by the agent — that satisfies verdict_is_clean +
# verdict_covers_head and converts this deny into a guard-level ALLOW. Adding an
# explicit worktree_dirty:false defeats the sha-exact tightening as well. The
# artifact is model-authored BY DESIGN (project-verification Step 3 instructs
# it; verify-and-record.sh calls itself not a trust boundary), so it is
# sha-bound, NOT harder to forge.
#
# THE DIFFERENCE IS NOT FORGEABILITY, and an earlier draft of this file said it
# was. Measured 2026-09-24: all four of this leg's sources are plain files under
# ~/.claude/ (.skill-composition-state-*, .skill-invocation-evidence-*, and the
# branch-ledger dirs) and each one, hand-written, flips this deny to an ALLOW.
# What distinguishes the verdict is that it arrives with NO deliberate act,
# because the skill instructs the model to write it; the other four are normally
# written only by hooks. The message must not claim this leg accepts only
# unwritable evidence — see test_the_note_claims_no_forgery_resistance. The open
# defect spans all of them: issue #295.
#
# Hence the message must NOT imply this leg is the one in the wrong. That is
# what test_the_note_does_not_disparage_this_leg pins.
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
    assert_contains "...and says declining it here is deliberate" "deliberately does not accept" "${reason:-<empty>}"
    assert_contains "...and says why: the artifact is model-authored" "authored by the model itself" "${reason:-<empty>}"
    assert_contains "...and says the other sources are hook-written" "normally written only by hooks" "${reason:-<empty>}"
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

test_the_note_does_not_disparage_this_leg() {
    # The refused framing, pinned so it cannot creep back. Before the bar was
    # discharged this message told the reader the global leg treats the verdict
    # as "stronger evidence ... than this status milestone", which reads as an
    # admission that THIS leg is mistaken. Measurement says the opposite: the
    # verdict is easier to supply, not harder, so a reader acting on the old
    # wording would widen the gate in the wrong direction.
    jq -nc --arg s "${HEAD_SHA}" \
        '{passed:["tests"],failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "${ART}"
    local reason; reason="$(_reason "$(_run)")"
    # Positive anchor FIRST. Two assert_not_contains pin nothing on their own:
    # measured, deleting the whole _MSG note line left both of them PASSING.
    assert_contains     "the note is present at all (anchors the negatives below)" "${NEEDLE}" "${reason:-<empty>}"
    assert_not_contains "the note does not call the verdict stronger evidence" "stronger evidence" "${reason:-}"
    assert_not_contains "the note does not concede this leg is wrong"          "does not read it, so the deny stands" "${reason:-}"
}

test_the_note_claims_no_forgery_resistance() {
    # Measured 2026-09-24: every source this leg accepts is a hand-writable file
    # under ~/.claude/, and each flips the deny to an allow. A draft of this note
    # asserted "this leg accepts only harness-observed evidence", which is a
    # POSITIVE SAFETY CLAIM a reader could rely on when deciding not to harden
    # those legs — a worse failure than the over-generous wording it replaced.
    # The honest distinction is that the verdict arrives by default; keep the
    # message on that ground and off forgeability.
    jq -nc --arg s "${HEAD_SHA}" \
        '{passed:["tests"],failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "${ART}"
    local reason; reason="$(_reason "$(_run)")"
    assert_contains     "says plainly that none of it is forgery-proof"     "forgery-proof" "${reason:-<empty>}"
    assert_not_contains "no claim that this leg's evidence is harness-only" "only harness-observed" "${reason:-}"
    # The false claim lived in TWO places: the _MSG string (above) and the guard
    # COMMENT. A `reason`-based assertion can never observe the comment, so the
    # previous version of this line — which tested the comment's phrasing
    # against `reason` — could not fail under any regression and pinned nothing.
    # Re-pointed at the file, where that phrasing actually lived.
    assert_not_contains "the guard COMMENT makes no unwritability claim" \
        "cannot be produced by writing" "$(cat "${GUARD}")"
}

test_the_note_never_moves_the_decision() {
    # Structural. If the verdict ever reaches _verif_completed or a decision on
    # this leg, that is the pre-registered flip, not this change.
    local _block _code
    _block="$(awk '/#254 d2: SAY when a clean covering verdict/,/^                fi$/' "${GUARD}")"
    # Scan CODE ONLY. The captured region is now mostly English, and a future
    # comment reading "this leg must never set _DECISION=" would fail this cell
    # for the wrong reason — measured: inserting the words "exit 0" into the
    # prose failed it.
    #
    # Drop WHOLE comment lines, never `s/#.*$//`. That earlier form cut at the
    # first '#' regardless of quoting, and the _MSG line this cell exists to
    # police contains "(issue #254, ...)" INSIDE the quoted string — so the cell
    # was scanning a truncated version of its own subject, and a violation
    # appended past that point was invisible (measured: it passed). The comment
    # that justified it claimed "an assignment after a '#' is not executable
    # anyway", which is true of a real comment and false of a '#' in quotes.
    # Prose lines are full-line comments, so this keeps everything that form
    # bought.
    _code="$(printf '%s' "${_block}" | sed '/^[[:space:]]*#/d')"
    # ANCHOR GUARD. The awk range STARTS AT A COMMENT LINE, so rewording that
    # line yields an empty block, the grep then matches nothing, and the cell
    # passes while asserting nothing. Measured: renaming only that comment left
    # the whole file green. Assert the block really captured the note's CODE
    # before drawing any conclusion from the scan.
    if [ -z "${_code}" ] || ! printf '%s' "${_code}" | grep -q '_MSG=.*NOTE: a CLEAN verification verdict'; then
        _record_fail "the #254 note never moves the decision" \
            "awk anchors no longer capture the note block (empty or missing the _MSG line) — re-point them; this cell is vacuous until you do"
        return
    fi
    if printf '%s' "${_code}" | grep -qE '_verif_completed=|_DECISION=|exit 0|permissionDecision'; then
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
test_the_note_does_not_disparage_this_leg
test_the_note_claims_no_forgery_resistance
test_the_note_never_moves_the_decision

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary

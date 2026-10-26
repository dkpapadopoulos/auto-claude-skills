#!/usr/bin/env bash
# test-reviewer-start-sha.sh — the `reviewer-returned` milestone records the
# commit the reviewer was POINTED AT, in both firing orders (final review I2,
# ruling F3, openspec review-credit-from-evidence decision 3).
#
# For a FOREGROUND dispatch PostToolUse(Agent) fires ~30ms AFTER SubagentStop
# (measured on CLI 2.1.236, 3 of 3), so the dispatch hook's HEAD was the HEAD
# after the reviewer finished: a material commit landing during the review was
# recorded as reviewed and the REVIEW leg credited the push. A SubagentStart hook
# (hooks/reviewer-start-hook.sh) now records HEAD as the subagent starts, both
# join sides read the reviewed sha through reviewer_pairing_reviewed_sha, and a
# completed agent with no start record gets `-`, never a later HEAD.
#
# Every hook is driven as the REAL script, and every push decision comes from
# the REAL guard, in a throwaway non-routing repo with an `origin` (so a
# mainline base resolves and the material-delta rule is the production one).
# The SubagentStart payload has the keys captured live on Claude Code 2.1.308
# (agent_id, agent_type, cwd, hook_event_name, prompt_id, session_id,
# transcript_path; no description), where its agent_id equalled SubagentStop's
# and the dispatch's agentId and the foreground order was Start, Stop, then
# PostToolUse(Agent) with status "completed". The SubagentStop and
# PostToolUse(Agent) shapes are the ones captured live in
# tests/test-reviewer-completion-hook.sh. Cells are flat, so none can be
# defined and never run.
#
#   T1  background order, material commit mid-review          -> push denied
#   T2  foreground order, material commit mid-review          -> push denied
#   T3  foreground order, no commit mid-review                -> push credited
#   T4  background order, no commit mid-review                -> push credited
#   T5  foreground order, mid-review commit, no start record  -> `-`, denied
#   T6  background order with the start record arriving after dispatch
#   T7  the start record outranks the dispatch record's sha
#   H*  the start hook itself: event gate, record shape, silence, fail-open
#   R*  hooks.json registration, executable bit, GC of the new family
# Bash 3.2.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-reviewer-start-sha.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    _record_fail "jq available" "jq is required"
    print_summary
    exit 1
fi
unset ACSM_SKIP_PUSH_GATE

START_HOOK="${PROJECT_ROOT}/hooks/reviewer-start-hook.sh"
COMP_HOOK="${PROJECT_ROOT}/hooks/reviewer-completion-hook.sh"
DISP_HOOK="${PROJECT_ROOT}/hooks/reviewer-evidence-hook.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
LEDGER_LIB="${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"

_GIT() { git -c user.email=t@t -c user.name=t "$@"; }
_SID="0f5b1a2c-bbbb-4222-8333-444455556666"
_TOK="session-conv-X"
_PUSH='{"transcript_path":"/tmp/proj/conv-X.jsonl","tool_input":{"command":"git push origin HEAD"}}'
_TYPE="pr-review-toolkit:code-reviewer"
_RR_NOTE="accepted via a returned reviewer"

# _fresh — sandbox HOME; repo with origin/main and feature/x carrying one
# material commit (src.sh); VERIFY in the ledger; REVIEW in the chain only.
_fresh() {
    teardown_test_env
    setup_test_env
    mkdir -p "${HOME}/.claude"
    REPO="${TEST_TMPDIR}/repo"; ORIGIN="${TEST_TMPDIR}/origin.git"
    git init -q --bare "${ORIGIN}"
    git init -q -b main "${REPO}"
    REPO="$(cd "${REPO}" && pwd -P)"
    printf 'base\n' > "${REPO}/README.md"
    git -C "${REPO}" add README.md; _GIT -C "${REPO}" commit -q -m base
    git -C "${REPO}" remote add origin "${ORIGIN}"
    git -C "${ORIGIN}" fetch -q "${REPO}" main:main
    git -C "${REPO}" fetch -q origin
    git -C "${REPO}" checkout -q -b feature/x
    printf 'echo one\n' > "${REPO}/src.sh"
    git -C "${REPO}" add src.sh; _GIT -C "${REPO}" commit -q -m c1
    ( cd "${REPO}" && . "${LEDGER_LIB}" && branch_ledger_record verification-before-completion "${REPO}" "" ) >/dev/null 2>&1
    printf '{"chain":["requesting-code-review","verification-before-completion"],"completed":[]}\n' \
        > "${HOME}/.claude/.skill-composition-state-${_TOK}"
}
_head() { git -C "${REPO}" rev-parse HEAD 2>/dev/null; }
_material_commit() {
    printf 'echo unreviewed %s\n' "$RANDOM" >> "${REPO}/src.sh"
    git -C "${REPO}" add src.sh; _GIT -C "${REPO}" commit -q -m unreviewed
}
_start() {   # <agent_id> [event]
    jq -nc --arg ai "$1" --arg sid "${_SID}" --arg ev "${2:-SubagentStart}" --arg t "${_TYPE}" \
        '{hook_event_name:$ev, session_id:$sid, transcript_path:"/nonexistent/parent.jsonl",
          cwd:"/nonexistent", agent_id:$ai, agent_type:$t}' \
    | ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${_ROOT:-${PROJECT_ROOT}}" /bin/bash "${START_HOOK}" 2>/dev/null )
}
_comp() {    # <agent_id>
    jq -nc --arg ai "$1" --arg sid "${_SID}" --arg t "${_TYPE}" \
        '{hook_event_name:"SubagentStop", session_id:$sid, agent_id:$ai, agent_type:$t,
          agent_transcript_path:"/nonexistent/a.jsonl", transcript_path:"/nonexistent/p.jsonl",
          last_assistant_message:"Findings: 0", stop_hook_active:false}' \
    | ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${COMP_HOOK}" ) >/dev/null 2>&1
}
_disp() {    # <agent_id> <status>
    jq -nc --arg ai "$1" --arg sid "${_SID}" --arg t "${_TYPE}" --arg st "$2" \
        '{tool_name:"Agent", session_id:$sid,
          tool_response:{is_error:false, agentId:$ai, status:$st},
          tool_input:{subagent_type:$t, description:"Review the change"}}' \
    | ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${DISP_HOOK}" ) >/dev/null 2>&1
}
_guard() { ( cd "${REPO}" && printf '%s' "${_PUSH}" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null ); }
_lsha() { ( cd "${REPO}" && . "${LEDGER_LIB}" && branch_ledger_sha reviewer-returned "${REPO}" ) 2>/dev/null; }
_decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null; }
_reason() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }

# _denied <label> <out> — denied, and by the REVIEW gate (another gate's deny
# would satisfy a bare "deny").
_denied() {
    assert_equals "$1: push denied" "deny" "$(_decision "$2")"
    assert_contains "$1: denied for missing REVIEW" "requesting-code-review" "$(_reason "$2")"
}
# _credited <label> <out> — no deny, and the reviewer leg is what credited.
_credited() {
    assert_not_empty "$1: guard produced output" "$2"
    assert_equals "$1: push not denied" "none" "$(_decision "$2")"
    assert_contains "$1: credited by the returned reviewer" "${_RR_NOTE}" "$2"
}

# ---------------------------------------------------------------------------
# T1 BACKGROUND order: start, dispatch (async_launched, at spawn), a material
# commit during the review, completion. Recorded sha = S0, push denied.
_fresh; S0="$(_head)"
_start t1; _disp t1 async_launched; _material_commit; _comp t1
assert_equals "T1 background, commit mid-review: milestone sha is the start HEAD" "${S0}" "$(_lsha)"
_denied "T1 background, commit mid-review" "$(_guard)"

# T2 FOREGROUND order: start, a material commit during the review, completion,
# then PostToolUse(Agent) (status completed). Before the fix this recorded the
# new HEAD and the push was credited.
_fresh; S0="$(_head)"
_start t2; _material_commit; _comp t2; _disp t2 completed
if [ "${S0}" = "$(_head)" ]; then
    _record_fail "T2 harness moved HEAD" "no commit landed; the cell proves nothing"
else
    _record_pass "T2 harness moved HEAD"
fi
assert_equals "T2 foreground, commit mid-review: milestone sha is the start HEAD" "${S0}" "$(_lsha)"
_denied "T2 foreground, commit mid-review" "$(_guard)"

# T3 FOREGROUND order, nothing committed during the review: credited.
_fresh; S0="$(_head)"
_start t3; _comp t3; _disp t3 completed
assert_equals "T3 foreground, no commit: milestone sha is HEAD" "${S0}" "$(_lsha)"
_credited "T3 foreground, no commit" "$(_guard)"

# T4 BACKGROUND order, nothing committed during the review: credited.
_fresh; S0="$(_head)"
_start t4; _disp t4 async_launched; _comp t4
assert_equals "T4 background, no commit: milestone sha is HEAD" "${S0}" "$(_lsha)"
_credited "T4 background, no commit" "$(_guard)"

# T5 FOREGROUND order with NO start record (an older Claude Code, or the start
# hook failed): the dispatch hook runs after completion, so its HEAD is never
# used. `-`, which never credits.
_fresh
_material_commit; _comp t5; _disp t5 completed
assert_equals "T5 foreground, no start record: milestone sha is -" "-" "$(_lsha)"
_denied "T5 foreground, no start record" "$(_guard)"
# T5b the same with no commit: still `-` (the rule is the order, not the diff),
# so the push is denied. Under-crediting is the accepted direction.
_fresh
_comp t5b; _disp t5b completed
assert_equals "T5b foreground, no start record, no commit: milestone sha is -" "-" "$(_lsha)"
_denied "T5b foreground, no start record, no commit" "$(_guard)"

# T6 BACKGROUND order, start arriving AFTER the dispatch, no start before it:
# the dispatch HEAD (at spawn, before completion) and the start HEAD agree;
# a commit after both is not covered.
_fresh; S0="$(_head)"
_disp t6 async_launched; _start t6; _material_commit; _comp t6
assert_equals "T6 background, start after dispatch: milestone sha is the pre-review HEAD" "${S0}" "$(_lsha)"
_denied "T6 background, start after dispatch, commit mid-review" "$(_guard)"
# T6b background with NO start record at all keeps the dispatch-time HEAD.
_fresh; S0="$(_head)"
_disp t6b async_launched; _material_commit; _comp t6b
assert_equals "T6b background, no start record: milestone sha is the dispatch HEAD" "${S0}" "$(_lsha)"
_denied "T6b background, no start record, commit mid-review" "$(_guard)"

# T7 the start record OUTRANKS the dispatch record: background order with a
# material commit after the spawn acknowledgement but BEFORE the subagent
# starts. The reviewer saw that commit, so the milestone names the start HEAD
# and the push is credited; the dispatch HEAD would under-credit it.
_fresh; D0="$(_head)"
_disp t7 async_launched; _material_commit; S1="$(_head)"; _start t7; _comp t7
assert_equals "T7 start record outranks the dispatch HEAD" "${S1}" "$(_lsha)"
if [ "${D0}" = "${S1}" ]; then _record_fail "T7 harness moved HEAD" "no commit landed"
else _record_pass "T7 harness moved HEAD"; fi
_credited "T7 commit before the reviewer started is covered" "$(_guard)"

# ---------------------------------------------------------------------------
# H: the start hook on its own.
_fresh; S0="$(_head)"
_SF="${HOME}/.claude/.skill-reviewer-start-session-${_SID}"
_KEY="$( ( cd "${REPO}" && . "${LEDGER_LIB}" && branch_ledger_key ) 2>/dev/null)"
_out="$(_start h1)"; _rc=$?
assert_equals "H1 exit 0" "0" "${_rc}"
assert_equals "H1 empty stdout" "" "${_out}"
assert_equals "H1 record is '<aid> <key> <sha>'" "h1 ${_KEY} ${S0}" "$(cat "${_SF}" 2>/dev/null)"
rm -f "${_SF}"
_out="$(_start h2 SubagentStop)"
assert_equals "H2 another event: empty stdout" "" "${_out}"
if [ -e "${_SF}" ]; then _record_fail "H2 another event writes nothing" "$(cat "${_SF}")"
else _record_pass "H2 another event writes nothing"; fi
# H3 an id outside the charset is refused, and the hook still exits 0 silently.
_out="$(_start 'a b')"; _rc=$?
assert_equals "H3 bad agent id: exit 0, empty stdout" "0|" "${_rc}|${_out}"
if [ -e "${_SF}" ]; then _record_fail "H3 bad agent id writes nothing" "$(cat "${_SF}")"
else _record_pass "H3 bad agent id writes nothing"; fi
# H4 fail-open: a pairing lib that faults mid-source, a missing lib, and
# garbage stdin all exit 0 with empty stdout and write nothing.
_ROOTF="${TEST_TMPDIR}/root-fault"; _ROOTM="${TEST_TMPDIR}/root-missing"
for _d in "${_ROOTF}" "${_ROOTM}"; do mkdir -p "${_d}" && cp -R "${PROJECT_ROOT}/hooks" "${_d}/"; done
printf 'false\n' >> "${_ROOTF}/hooks/lib/reviewer-pairing.sh"
rm -f "${_ROOTM}/hooks/lib/reviewer-pairing.sh"
for _r in "${_ROOTF}" "${_ROOTM}"; do
    _out="$(_ROOT="${_r}" _start h4)"; _rc=$?
    assert_equals "H4 faulted root $(basename "${_r}"): exit 0, empty stdout" "0|" "${_rc}|${_out}"
done
_out="$(printf 'not json' | ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${START_HOOK}" 2>/dev/null ))"; _rc=$?
assert_equals "H4 garbage stdin: exit 0, empty stdout" "0|" "${_rc}|${_out}"
_out="$( ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${START_HOOK}" < /dev/null 2>/dev/null ))"; _rc=$?
assert_equals "H4 empty stdin: exit 0, empty stdout" "0|" "${_rc}|${_out}"
# The faulted lib still defines its functions (the fault is after them) and the
# source returns non-zero, so the #137 form refuses it: no record.
if [ -e "${_SF}" ]; then _record_fail "H4 faulted roots wrote nothing" "$(cat "${_SF}")"
else _record_pass "H4 faulted roots wrote nothing"; fi
# H5 an unborn repo stores `-`, which never reads back as a sha.
_U="${TEST_TMPDIR}/unborn"; git init -q -b feature/u "${_U}"; _U="$(cd "${_U}" && pwd -P)"
git -C "${_U}" remote add origin "https://example.invalid/u.git"
( jq -nc --arg sid "${_SID}" '{hook_event_name:"SubagentStart", session_id:$sid, agent_id:"h5", agent_type:"x"}' \
  | ( cd "${_U}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${START_HOOK}" ) ) >/dev/null 2>&1
assert_contains "H5 unborn repo: start record stores -" "h5 " "$(grep '^h5 ' "${_SF}" 2>/dev/null)"
assert_equals "H5 unborn repo: the stored sha is -" "-" "$(awk '$1=="h5" {print $3}' "${_SF}" 2>/dev/null)"
# shellcheck disable=SC1090
assert_equals "H5 start_sha refuses -" "1" \
    "$( ( . "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh"; reviewer_pairing_start_sha "${_SID}" h5 "$(cd "${_U}" && . "${LEDGER_LIB}" && branch_ledger_key)" >/dev/null; echo $? ) 2>/dev/null)"
# H6 a start record on ANOTHER branch key is not read.
_fresh; S0="$(_head)"
_start h6
git -C "${REPO}" checkout -q -b feature/other
_comp h6; _disp h6 completed
assert_equals "H6 start on another branch: not used, milestone sha is -" "-" "$(_lsha)"

# ---------------------------------------------------------------------------
# R: registration and housekeeping.
if jq -e '.hooks.SubagentStart[]?.hooks[]? | select(.command | endswith("/hooks/reviewer-start-hook.sh"))' \
     "${PROJECT_ROOT}/hooks/hooks.json" >/dev/null 2>&1; then
    _record_pass "R1 reviewer-start-hook.sh registered on SubagentStart"
else
    _record_fail "R1 reviewer-start-hook.sh registered on SubagentStart" "not in hooks.json"
fi
if [ -x "${START_HOOK}" ]; then _record_pass "R2 reviewer-start-hook.sh is executable"
else _record_fail "R2 reviewer-start-hook.sh is executable" "mode lacks +x"; fi
if /bin/bash -n "${START_HOOK}" 2>/dev/null; then _record_pass "R3 /bin/bash -n reviewer-start-hook.sh"
else _record_fail "R3 /bin/bash -n reviewer-start-hook.sh" "syntax error"; fi
# R4 the start hook never emits a permission decision (record-only).
if grep -v '^[[:space:]]*#' "${START_HOOK}" | grep -q 'permissionDecision\|hookSpecificOutput'; then
    _record_fail "R4 the start hook has no permissionDecision" "found in source"
else
    _record_pass "R4 the start hook has no permissionDecision"
fi

teardown_test_env
print_summary
exit $?

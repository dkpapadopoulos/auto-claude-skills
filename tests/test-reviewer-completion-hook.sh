#!/usr/bin/env bash
# test-reviewer-completion-hook.sh — the SubagentStop recorder.
#
# Spec: openspec/changes/reviewer-completion-evidence/
#
# The payload SHAPE asserted here is not invented. It was captured live from
# Claude Code CLI 2.1.236 by registering a throwaway SubagentStop hook via
# `claude -p --settings` and dumping the raw stdin, with PostToolUse and Stop
# registered in the same run as positive controls. Any test that hand-writes a
# producer's output only ever proves the consumer agrees with the test author's
# idea of the format (see CLAUDE.md, and .claude/knowledge/
# classifier-fixtures-from-real-producer.md). Cell (i) closes the remaining gap
# by driving the REAL dispatch hook to produce the pairing file this hook reads.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-reviewer-completion-hook.sh ==="

HOOK="${PROJECT_ROOT}/hooks/reviewer-completion-hook.sh"
DISPATCH_HOOK="${PROJECT_ROOT}/hooks/reviewer-evidence-hook.sh"
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/rch-home-XXXXXX)"
mkdir -p "$HOME/.claude"

# A real git repo so branch_ledger_key resolves. PHYSICAL path (`pwd -P`): on
# macOS /tmp is a symlink to /private/tmp and the hook records with no explicit
# proj_root, so the key is derived from `git rev-parse --show-toplevel`, which
# resolves symlinks. Hashing the unresolved path in the reader yields a
# DIFFERENT key and every assertion fails against a correct hook.
_REPO="$(mktemp -d /tmp/rch-repo-XXXXXX)"
_REPO="$(cd "$_REPO" && pwd -P)"
( cd "$_REPO" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init )

_SID="0f5b1a2c-1111-4222-8333-444455556666"

# $1=agent_type $2=agent_id $3=last_assistant_message $4=session_id
# $5=hook_event_name (defaults to SubagentStop)
_payload() {
    jq -n --arg at "$1" --arg ai "$2" --arg lm "$3" --arg sid "$4" \
          --arg ev "${5:-SubagentStop}" \
      '{hook_event_name:$ev, session_id:$sid, agent_id:$ai, agent_type:$at,
        agent_transcript_path:"/nonexistent/agent.jsonl",
        transcript_path:"/nonexistent/parent.jsonl",
        last_assistant_message:$lm, stop_hook_active:false}'
}
_run() {  # prints stdout; exit status in _STATUS
    local out
    out="$(_payload "$@" | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) 2>/dev/null)"
    _STATUS=$?
    printf '%s' "$out"
}
_pairfile() { printf '%s' "${HOME}/.claude/.skill-reviewer-dispatch-session-${_SID}"; }
_reset() { rm -rf "$HOME"/.claude/.skill-branch-ledger-*; rm -f "$(_pairfile)"; }

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
_has() { branch_ledger_has "reviewer-returned" "$_REPO"; }
_has_ran() { branch_ledger_has "reviewer-ran" "$_REPO"; }

# --- (a) allowlisted agent_type records, with no pairing file at all --------
# The allowlist arm must not depend on the dispatch hook having run: agent_type
# arrives verbatim and plugin-qualified, which is the whole reason that arm
# needs no pairing.
_reset; _run "pr-review-toolkit:code-reviewer" "a1" "Findings: 2 blocking" "$_SID" >/dev/null
if _has; then _record_pass "(a) allowlisted agent_type records reviewer-returned"
else _record_fail "(a) allowlisted agent_type records reviewer-returned" "no ledger entry"; fi

# --- (b) general-purpose WITH a pairing entry records -----------------------
_reset; printf '%s\n' "a2" > "$(_pairfile)"
_run "general-purpose" "a2" "Findings: none" "$_SID" >/dev/null
if _has; then _record_pass "(b) paired general-purpose records reviewer-returned"
else _record_fail "(b) paired general-purpose records reviewer-returned" "no ledger entry"; fi

# --- (c) general-purpose WITHOUT a pairing entry records nothing ------------
# This is the false positive the whole pairing design exists to avoid: an
# ordinary implementation subagent completing is not a review.
_reset; printf '%s\n' "someone-else" > "$(_pairfile)"
_run "general-purpose" "a3" "Implemented the parser" "$_SID" >/dev/null
if _has; then _record_fail "(c) unpaired general-purpose is not credited" "ledger entry written"
else _record_pass "(c) unpaired general-purpose is not credited"; fi

# --- (d) no pairing file at all is a MISS, not an error ---------------------
# The dispatch may predate the plugin version that writes the pairing, so a
# recorder must degrade to "no record", never to a fabricated one.
_reset
_run "general-purpose" "a4" "Implemented the parser" "$_SID" >/dev/null
if _has; then _record_fail "(d) absent pairing file is a miss" "ledger entry written"
elif [ "${_STATUS}" -ne 0 ]; then _record_fail "(d) absent pairing file is a miss" "non-zero exit ${_STATUS}"
else _record_pass "(d) absent pairing file is a miss, exit 0"; fi

# --- (e) an empty last_assistant_message is not a return -------------------
# A reviewer that emitted nothing (interrupted, crashed) returned no review.
# Under-crediting is the safe direction for a fidelity signal.
_reset; _run "pr-review-toolkit:code-reviewer" "a5" "" "$_SID" >/dev/null
if _has; then _record_fail "(e) empty final message is not credited" "ledger entry written"
else _record_pass "(e) empty final message is not credited"; fi

# --- (f) a non-SubagentStop event is never credited ------------------------
# The hook is registered on SubagentStop only; this pins that a hooks.json edit
# widening the registration cannot silently start crediting on another event.
_reset; _run "pr-review-toolkit:code-reviewer" "a6" "Findings: 0" "$_SID" "Stop" >/dev/null
if _has; then _record_fail "(f) non-SubagentStop event is not credited" "ledger entry written"
else _record_pass "(f) non-SubagentStop event is not credited"; fi

# --- (g) the recorder contract: nothing on stdout, exit 0 ------------------
# A recorder that emitted JSON on a PreToolUse-adjacent path could alter a gate
# decision. Asserted on the CREDITING path, which is the one that does work.
_reset
_OUT="$(_run "pr-review-toolkit:code-reviewer" "a7" "Findings: 1" "$_SID")"
if [ -n "${_OUT}" ]; then _record_fail "(g) recorder writes nothing to stdout" "stdout: ${_OUT}"
elif [ "${_STATUS}" -ne 0 ]; then _record_fail "(g) recorder exits 0" "exit ${_STATUS}"
else _record_pass "(g) recorder writes nothing to stdout and exits 0"; fi

# --- (h) the pairing lookup is a WHOLE-LINE LITERAL match ------------------
# A prefix or a regex must not credit: `grep -qxF` is load-bearing, and a
# `grep -q` regression would credit "a8" from a stored "." or from "a8x".
_reset; printf '%s\n' "a8xyz" > "$(_pairfile)"
_run "general-purpose" "a8" "output" "$_SID" >/dev/null
if _has; then _record_fail "(h1) a prefix does not credit" "ledger entry written"
else _record_pass "(h1) a prefix does not credit"; fi

# The metachar risk lives in the PATTERN (the agent id), not in the file — an
# earlier version of this cell had it backwards and passed with `-F` deleted.
# `.` is inside the id charset the writer accepts, so `a.9` is a reachable id;
# without `-F` it is a regex that matches the unrelated stored line `a29`.
_reset; printf '%s\n' "a29" > "$(_pairfile)"
_run "general-purpose" "a.9" "output" "$_SID" >/dev/null
if _has; then _record_fail "(h2) a regex metachar in the agent id does not credit" "ledger entry written"
else _record_pass "(h2) a regex metachar in the agent id does not credit"; fi

# --- (i) END-TO-END: the REAL dispatch hook produces the pairing this reads --
# The one cell that is not hostage to this file's idea of the format. A
# hand-written pairing file proves only that the reader agrees with the test;
# this drives the actual writer, so writer/reader symmetry — the recurring bug
# class in this repo (#51/#97/#122/#131/#133/#151/#156) — is measured, not
# assumed. It also pins that the two hooks agree on the session_id-derived
# filename without either side re-deriving a token.
_reset
_DISPATCH_ID="e2e-agent-0001"
jq -n --arg sid "$_SID" --arg ai "$_DISPATCH_ID" \
  '{tool_name:"Agent", session_id:$sid,
    tool_response:{is_error:false, agentId:$ai, status:"async_launched"},
    tool_input:{subagent_type:"general-purpose", description:"Task 1 review: spec + quality"}}' \
  | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${DISPATCH_HOOK}" ) >/dev/null 2>&1

if [ -f "$(_pairfile)" ]; then
    _record_pass "(i1) dispatch hook writes the pairing file the reader expects"
else
    _record_fail "(i1) dispatch hook writes the pairing file the reader expects" "no file at $(_pairfile)"
fi

_run "general-purpose" "$_DISPATCH_ID" "Findings: 1 blocking" "$_SID" >/dev/null
if _has; then _record_pass "(i2) end-to-end: real dispatch pairing credits the completion"
else _record_fail "(i2) end-to-end: real dispatch pairing credits the completion" "no ledger entry"; fi

# The dispatch hook must keep recording its OWN milestone unchanged — the
# pairing write is additive, not a replacement.
if _has_ran; then _record_pass "(i3) dispatch hook still records reviewer-ran"
else _record_fail "(i3) dispatch hook still records reviewer-ran" "no reviewer-ran entry"; fi

# --- (i4) a NON-reviewer dispatch writes NO pairing entry ------------------
# The pairing file must carry only agent ids the dispatch predicate accepted;
# if it recorded every dispatch, the completion hook's general-purpose arm
# would credit every subagent that ever finished.
_reset
jq -n --arg sid "$_SID" \
  '{tool_name:"Agent", session_id:$sid,
    tool_response:{is_error:false, agentId:"impl-agent-0001"},
    tool_input:{subagent_type:"general-purpose", description:"Task 3: reviewer-evidence writer hook"}}' \
  | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${DISPATCH_HOOK}" ) >/dev/null 2>&1
_run "general-purpose" "impl-agent-0001" "Implemented it" "$_SID" >/dev/null
if _has; then _record_fail "(i4) implementation dispatch writes no pairing" "ledger entry written"
else _record_pass "(i4) implementation dispatch writes no pairing"; fi

# --- (j) a session_id that is not a single path-safe segment is refused ----
# The value is harness-supplied, but a recorder must not be the component that
# turns a surprising value into a read or a write outside ~/.claude.
#
# The traversal is made REACHABLE rather than asserted in the abstract: an
# earlier version of this cell used a bare "../../escape", which resolves
# through a non-existent directory and so is refused whether the guard is there
# or not — it passed with the guard deleted. Here the first path component is
# made to exist, so without the guard the lookup genuinely escapes to the
# planted file and credits.
_reset
_ESC_DIR="${HOME}/.claude/.skill-reviewer-dispatch-session-x"
mkdir -p "${_ESC_DIR}"
_ESC_TARGET="${HOME}/planted-pairing"
printf '%s\n' "aj" > "${_ESC_TARGET}"
_run "general-purpose" "aj" "output" "x/../../planted-pairing" >/dev/null
if [ "${_STATUS}" -ne 0 ]; then
    _record_fail "(j) unsafe session_id is refused" "non-zero exit ${_STATUS}"
elif _has; then
    _record_fail "(j) unsafe session_id is refused" "escaped to the planted file and credited"
else
    _record_pass "(j) unsafe session_id is refused, exit 0"
fi
rm -rf "${_ESC_DIR}" "${_ESC_TARGET}"

# --- (j2) an unsafe session_id must not break the DISPATCH hook -------------
# The generalisation of the bug (i3) caught: new best-effort code must never be
# able to suppress the pre-existing milestone, on any input.
_reset
jq -n '{tool_name:"Agent", session_id:"../../nope",
    tool_response:{is_error:false, agentId:"safe-id-1"},
    tool_input:{subagent_type:"general-purpose", description:"Review the diff"}}' \
  | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${DISPATCH_HOOK}" ) >/dev/null 2>&1
if _has_ran; then _record_pass "(j2) unsafe session_id does not suppress reviewer-ran"
else _record_fail "(j2) unsafe session_id does not suppress reviewer-ran" "no reviewer-ran entry"; fi

# --- (k) malformed / empty input never fails --------------------------------
_reset
printf 'not json at all' | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) >/dev/null 2>&1
_S1=$?
printf '' | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) >/dev/null 2>&1
_S2=$?
if [ "${_S1}" -eq 0 ] && [ "${_S2}" -eq 0 ] && ! _has; then
    _record_pass "(k) malformed and empty input exit 0 with no record"
else
    _record_fail "(k) malformed and empty input exit 0 with no record" "exits ${_S1}/${_S2}"
fi

# --- (l) registration ------------------------------------------------------
if jq -e '[.hooks.SubagentStop[]?.hooks[]?.command]
          | any(test("reviewer-completion-hook\\.sh"))' \
     "${PROJECT_ROOT}/hooks/hooks.json" >/dev/null 2>&1; then
    _record_pass "(l1) registered on SubagentStop in hooks.json"
else
    _record_fail "(l1) registered on SubagentStop in hooks.json" "not found"
fi

# The event name is exact. A typo registers a hook that never fires, and the
# failure mode is silence, which every other cell here would pass through.
if jq -e '.hooks | keys | any(. == "SubagentStop")' \
     "${PROJECT_ROOT}/hooks/hooks.json" >/dev/null 2>&1; then
    _record_pass "(l2) the event key is spelled SubagentStop"
else
    _record_fail "(l2) the event key is spelled SubagentStop" "no such key"
fi

# --- (m) diagnostic-only: never a gate-enforcement component ---------------
# _GATE_ENFORCE_LIBS drives both the session-start precondition canary and the
# installed-plugin drift manifest. A diagnostic recorder joining it would make
# a missing recorder announce as a degraded GATE.
if grep -q 'reviewer-completion-hook' "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null; then
    _record_fail "(m) not a gate-enforcement component" "referenced by session-start canary/manifest"
else
    _record_pass "(m) not a gate-enforcement component"
fi

# It must also never appear in the guard: this change wires no gate.
if grep -q 'reviewer-returned' "${PROJECT_ROOT}/hooks/openspec-guard.sh" 2>/dev/null; then
    _record_fail "(m2) no gate reads reviewer-returned in this change" "openspec-guard.sh references it"
else
    _record_pass "(m2) no gate reads reviewer-returned in this change"
fi

# --- (n) the pairing file is covered by the state GC ----------------------
# Behavioural pruning is asserted in tests/test-state-file-cleanup.sh; here we
# only pin that the name and its current-session exclusion are both present, so
# adding one without the other cannot pass.
_SS="${PROJECT_ROOT}/hooks/session-start-hook.sh"
if grep -q "name '\.skill-reviewer-dispatch-\*'" "$_SS" 2>/dev/null \
   && grep -q '! -name "\.skill-reviewer-dispatch-\${_SESSION_TOKEN}"' "$_SS" 2>/dev/null; then
    _record_pass "(n) pairing file is GC'd with a current-session exclusion"
else
    _record_fail "(n) pairing file is GC'd with a current-session exclusion" "name or exclusion missing"
fi

rm -rf "$_REPO"
export HOME="$_OLDHOME"
print_summary
exit $?

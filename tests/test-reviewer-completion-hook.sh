#!/usr/bin/env bash
# test-reviewer-completion-hook.sh — the reviewer dispatch/completion JOIN.
#
# Spec: openspec/changes/reviewer-completion-evidence/
#
# The payload SHAPES here are not invented. They were captured live from Claude
# Code CLI 2.1.236 by registering throwaway hooks via `claude -p --settings` and
# dumping raw stdin, with unrelated events registered in the same run as
# positive controls. Any test that hand-writes a producer's output only proves
# the consumer agrees with the test author (CLAUDE.md; .claude/knowledge/
# classifier-fixtures-from-real-producer.md).
#
# THE CENTRAL FACT THIS FILE EXISTS TO PIN: neither hook is guaranteed to run
# first. Measured end-to-end against both real hooks:
#
#   background dispatch : DISPATCH fires 1.44s BEFORE completion
#   foreground dispatch : COMPLETION fires ~30ms BEFORE dispatch (3 of 3)
#
# Every credit path is therefore asserted in BOTH orders. A one-directional
# design passes the background order and is a systematic no-op for foreground —
# that was the first cut of this change, and only the live probe caught it.
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

# Two real git repos, PHYSICAL paths (`pwd -P`): on macOS /tmp is a symlink to
# /private/tmp and the hooks derive the ledger key from
# `git rev-parse --show-toplevel`, which resolves symlinks — hashing the
# unresolved path in the reader yields a DIFFERENT key and every assertion fails
# against correct hooks. The SECOND repo exists only to produce a genuinely
# different ledger key for the branch-binding cell.
_mkrepo() {
    local d; d="$(mktemp -d "/tmp/rch-repo-XXXXXX")"; d="$(cd "$d" && pwd -P)"
    ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git commit -q --allow-empty -m init )
    printf '%s' "$d"
}
_REPO="$(_mkrepo)"
_REPO2="$(_mkrepo)"

_SID="0f5b1a2c-1111-4222-8333-444455556666"

# --- payload builders (shapes captured from the live probe) -----------------
# completion: $1=agent_id $2=last_assistant_message $3=session_id $4=event
_completion_payload() {
    jq -n --arg ai "$1" --arg lm "$2" --arg sid "$3" --arg ev "${4:-SubagentStop}" \
      '{hook_event_name:$ev, session_id:$sid, agent_id:$ai, agent_type:"general-purpose",
        agent_transcript_path:"/nonexistent/agent.jsonl",
        transcript_path:"/nonexistent/parent.jsonl",
        last_assistant_message:$lm, stop_hook_active:false}'
}
# dispatch: $1=agent_id $2=description $3=session_id $4=subagent_type
_dispatch_payload() {
    jq -n --arg ai "$1" --arg d "$2" --arg sid "$3" --arg st "${4:-general-purpose}" \
      '{tool_name:"Agent", session_id:$sid,
        tool_response:{is_error:false, agentId:$ai, status:"completed"},
        tool_input:{subagent_type:$st, description:$d}}'
}
# Both hooks are always driven as the REAL scripts, in the given repo.
_run_completion() {  # agent_id msg [session_id] [event] ; repo in _CWD
    local out
    out="$(_completion_payload "$1" "$2" "${3:-$_SID}" "${4:-SubagentStop}" \
        | ( cd "${_CWD:-$_REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) 2>/dev/null)"
    _STATUS=$?
    printf '%s' "$out"
}
_run_dispatch() {    # agent_id description [session_id] [subagent_type]
    _dispatch_payload "$1" "$2" "${3:-$_SID}" "${4:-general-purpose}" \
        | ( cd "${_CWD:-$_REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${DISPATCH_HOOK}" ) >/dev/null 2>&1
}

_dispatch_file() { printf '%s' "${HOME}/.claude/.skill-reviewer-dispatch-session-${_SID}"; }
_complete_file() { printf '%s' "${HOME}/.claude/.skill-reviewer-complete-session-${_SID}"; }
_reset() {
    rm -rf "$HOME"/.claude/.skill-branch-ledger-*
    rm -f "$HOME"/.claude/.skill-reviewer-dispatch-* "$HOME"/.claude/.skill-reviewer-complete-* "$HOME"/.claude/.skill-reviewer-saturated-*
    _CWD="$_REPO"
}

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
_has()      { branch_ledger_has "reviewer-returned" "${1:-$_REPO}"; }
_has_ran()  { branch_ledger_has "reviewer-ran" "${1:-$_REPO}"; }

# ===========================================================================
# The join, in BOTH firing orders. These two cells are the point of the file.
# ===========================================================================

# --- (a) BACKGROUND order: dispatch first, then completion ------------------
_reset
_run_dispatch "bg-1" "Review the diff for correctness"
_run_completion "bg-1" "Findings: 1 blocking" >/dev/null
if _has; then _record_pass "(a) background order (dispatch->completion) credits"
else _record_fail "(a) background order (dispatch->completion) credits" "no ledger entry"; fi

# --- (b) FOREGROUND order: completion first, then dispatch ------------------
# The order that a one-directional design silently fails. Measured as the real
# order for foreground dispatches, 3 of 3.
_reset
_run_completion "fg-1" "Findings: 1 blocking" >/dev/null
_run_dispatch "fg-1" "Review the diff for correctness"
if _has; then _record_pass "(b) foreground order (completion->dispatch) credits"
else _record_fail "(b) foreground order (completion->dispatch) credits" "no ledger entry"; fi

# --- (c) allowlisted agent_type, both orders --------------------------------
# Classification lives in the dispatch hook for BOTH arms, so the allowlist arm
# goes through the identical join. Its description is deliberately NOT
# review-shaped, so only the subagent_type allowlist can be crediting it.
_reset
_run_dispatch "al-1" "Task 4: add the parser" "$_SID" "pr-review-toolkit:code-reviewer"
_run_completion "al-1" "Findings: 0" >/dev/null
if _has; then _record_pass "(c1) allowlisted type credits (background order)"
else _record_fail "(c1) allowlisted type credits (background order)" "no ledger entry"; fi

_reset
_run_completion "al-2" "Findings: 0" >/dev/null
_run_dispatch "al-2" "Task 4: add the parser" "$_SID" "pr-review-toolkit:code-reviewer"
if _has; then _record_pass "(c2) allowlisted type credits (foreground order)"
else _record_fail "(c2) allowlisted type credits (foreground order)" "no ledger entry"; fi

# ===========================================================================
# Non-credit paths
# ===========================================================================

# --- (d) an implementation subagent is never credited, in either order ------
# The false positive the whole design exists to avoid.
_reset
_run_dispatch "im-1" "Task 3: reviewer-evidence writer hook"
_run_completion "im-1" "Implemented it" >/dev/null
if _has; then _record_fail "(d1) implementation subagent not credited (bg order)" "ledger entry written"
else _record_pass "(d1) implementation subagent not credited (bg order)"; fi

_reset
_run_completion "im-2" "Implemented it" >/dev/null
_run_dispatch "im-2" "Task 3: reviewer-evidence writer hook"
if _has; then _record_fail "(d2) implementation subagent not credited (fg order)" "ledger entry written"
else _record_pass "(d2) implementation subagent not credited (fg order)"; fi

# --- (e) a completion with no dispatch at all is never credited -------------
# Covers the plugin-skew cold start: a session whose dispatch predates the
# pairing writer records nothing rather than a fabricated credit.
_reset
_run_completion "orphan-1" "Findings: 3" >/dev/null
if _has; then _record_fail "(e) orphan completion is not credited" "ledger entry written"
elif [ "${_STATUS}" -ne 0 ]; then _record_fail "(e) orphan completion is not credited" "exit ${_STATUS}"
else _record_pass "(e) orphan completion is not credited, exit 0"; fi

# --- (f) an empty final message is not a return, in either order ------------
# A reviewer that emitted nothing (interrupted, crashed) returned no review, so
# the completion half must not be published — otherwise a later dispatch would
# join against it and credit a crash.
_reset
_run_completion "empty-1" "" >/dev/null
_run_dispatch "empty-1" "Review the diff for correctness"
if _has; then _record_fail "(f1) empty final message is not credited (fg order)" "ledger entry written"
else _record_pass "(f1) empty final message is not credited (fg order)"; fi

_reset
_run_dispatch "empty-2" "Review the diff for correctness"
_run_completion "empty-2" "" >/dev/null
if _has; then _record_fail "(f2) empty final message is not credited (bg order)" "ledger entry written"
else _record_pass "(f2) empty final message is not credited (bg order)"; fi

# --- (g) a non-SubagentStop event never publishes a completion half ---------
_reset
_run_completion "ev-1" "Findings: 1" "$_SID" "Stop" >/dev/null
_run_dispatch "ev-1" "Review the diff for correctness"
if _has; then _record_fail "(g) non-SubagentStop event is not credited" "ledger entry written"
else _record_pass "(g) non-SubagentStop event is not credited"; fi

# ===========================================================================
# Branch binding — the wrong-target-HIT case
# ===========================================================================

# --- (h) a reviewer that completes on a DIFFERENT branch is not credited ----
# branch_ledger_record derives its key from the cwd at CALL time. A backgrounded
# reviewer finishes while the parent session is free to check out something
# else, so an unbound credit would land in the ledger of a branch the reviewer
# never saw — a wrong-target hit, not a miss, into evidence the push gate treats
# as durable. _REPO2 stands in for "a different branch/repo": a genuinely
# different ledger key.
_reset
_run_dispatch "mv-1" "Review the diff for correctness"        # dispatched in _REPO
_CWD="$_REPO2"
_run_completion "mv-1" "Findings: 2" >/dev/null               # completes in _REPO2
_CWD="$_REPO"
if _has "$_REPO2"; then
    _record_fail "(h1) completion on another branch does not credit it" "credited the wrong ledger"
elif _has "$_REPO"; then
    _record_fail "(h1) completion on another branch does not credit it" "credited the dispatch ledger from the wrong cwd"
else
    _record_pass "(h1) completion on another branch credits neither ledger"
fi

# The miss must leave a TRACE. A silent miss is how the foreground ordering
# defect nearly shipped: "no reviewer ran" and "a reviewer ran, join refused"
# must not look identical from the outside.
# In the DISPATCH file, deliberately: the completion file is the half that grows
# with every subagent and approaches the ceiling, so a diagnostic stored there
# would fall silent under the very condition that starts breaking the join.
if grep -q '^# branch-mismatch mv-1 ' "$(_dispatch_file)" 2>/dev/null; then
    _record_pass "(h2) the refused credit leaves a diagnostic line"
else
    _record_fail "(h2) the refused credit leaves a diagnostic line" "no mismatch line recorded"
fi

# (h3) A diagnostic comment line must never be readable as a pairing RECORD.
#
# Asserted at the LIB level, and the two previous end-to-end versions of this
# cell were BOTH vacuous — the second one passed with its own fixture deleted.
# The end-to-end path cannot isolate this: `$2` of a mismatch line is the word
# `branch-mismatch`, so even if the lookup DID match, the branch comparison
# refuses the credit and the cell goes green for the wrong reason. The only
# honest form is to ask the reader directly.
_reset
_KEYNOW3="$(cd "$_REPO" && branch_ledger_key)"
printf '# branch-mismatch h300000000000001 dispatched=%s completed=%s\n' "$_KEYNOW3" "$_KEYNOW3" > "$(_dispatch_file)"
if ( . "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh"
     reviewer_pairing_dispatch_key "$_SID" "h300000000000001" ) >/dev/null 2>&1; then
    _record_fail "(h3) a diagnostic line is not readable as a record" "dispatch_key matched a # line"
else
    _record_pass "(h3) a diagnostic line is not readable as a record"
fi

# (h3b) POSITIVE CONTROL for (h3): the same reader, same file, same id, but a
# REAL record — must be found. Without it, (h3) passes just as well against a
# reader that never matches anything, which is what "passes with the fixture
# deleted" means.
printf '%s %s\n' "h300000000000001" "$_KEYNOW3" > "$(_dispatch_file)"
if ( . "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh"
     reviewer_pairing_dispatch_key "$_SID" "h300000000000001" ) >/dev/null 2>&1; then
    _record_pass "(h3b) control: the same reader DOES find a real record"
else
    _record_fail "(h3b) control: the same reader DOES find a real record" "reader found nothing"
fi

# --- (h4) the DISPATCH side must branch-bind too ----------------------------
# Measured false credit before this: the dispatch-side join credited on agent-id
# MEMBERSHIP alone, so an id collision with no matching branch and no ordering
# constraint recorded `reviewer-returned` at SPAWN time for a reviewer that had
# produced nothing. Reproduced against the real hooks; the negative control below
# isolates it to the single variable (the prior completion record).
_reset
_CWD="$_REPO2"
_run_completion "xrepo-1" "Implemented something" >/dev/null   # non-reviewer completes in repo 2
_CWD="$_REPO"
_run_dispatch "xrepo-1" "Review the diff for correctness"      # same id dispatched in repo 1
if _has "$_REPO"; then
    _record_fail "(h4) a foreign completion does not credit the dispatch side" "credited from another branch's completion"
else
    _record_pass "(h4) a foreign completion does not credit the dispatch side"
fi

# (h5) SPECIFICITY control for (h4): the same dispatch with no completion
# anywhere must also not credit. This isolates the prior completion record as the
# single variable that differs between the two cells. It is NOT the control that
# rules out "this harness cannot credit at all" — a second negative cannot do
# that; (a)/(b) are the positive controls that do.
_reset
_run_dispatch "xrepo-2" "Review the diff for correctness"
if _has "$_REPO"; then
    _record_fail "(h5) control: a dispatch alone does not credit" "credited with no completion"
else
    _record_pass "(h5) control: a dispatch alone does not credit"
fi
# ...and (a)/(b) above are the positive controls: the same harness DOES credit a
# genuine same-branch join in both orders.

# --- (r) saturation is DISTINGUISHABLE, not merely rarer --------------------
# An absent `reviewer-returned` means "the reviewer did not return" OR "the
# recorder stopped recording". Those are `missing` and `cannot_check`, and
# CLAUDE.md is emphatic (IMPLEMENT shadow leg) that collapsing the second into
# the first biases every downstream reading in the unsafe direction. Raising the
# ceiling makes the state rarer; only the marker makes it legible.

# The override is set HERE, not inherited from another cell. These cells
# originally sat above the one that exported it and therefore ran against the
# shipped 1 MiB ceiling: (r1) failed loudly, but (r2) PASSED VACUOUSLY — it
# asserts an absence, so a cell that never triggers the condition looks correct.
export REVIEWER_PAIRING_MAX_BYTES=200

# (r1) a ceiling refusal leaves a marker
_reset
printf '%0400d\n' 0 > "$(_complete_file)"
_run_completion "sat-1" "Findings: 1" >/dev/null
if [ -f "${HOME}/.claude/.skill-reviewer-saturated-session-${_SID}" ]; then
    _record_pass "(r1) a ceiling refusal leaves a saturation marker"
else
    _record_fail "(r1) a ceiling refusal leaves a saturation marker" "no marker written"
fi

# (r2) ordinary operation leaves NO marker. Without this, (r1) passes just as
# well for a hook that marks unconditionally, which would make the marker
# meaningless — the same present-but-never-absent asymmetry that let the
# fabricated-mismatch mutation through until (j4).
_reset
_run_dispatch "sat-2" "Review the diff for correctness"
_run_completion "sat-2" "Findings: 1" >/dev/null
if [ -f "${HOME}/.claude/.skill-reviewer-saturated-session-${_SID}" ]; then
    _record_fail "(r2) ordinary operation leaves no marker" "marker written with no refusal"
else
    _record_pass "(r2) ordinary operation leaves no marker"
fi
unset REVIEWER_PAIRING_MAX_BYTES

# (r3) the reader agrees with the file, via the lib's own accessor rather than a
# path this test re-derives.
_reset
( . "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh"
  reviewer_pairing_saturated "$_SID" ) && _R3PRE=0 || _R3PRE=1
printf 'complete now\n' > "${HOME}/.claude/.skill-reviewer-saturated-session-${_SID}"
( . "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh"
  reviewer_pairing_saturated "$_SID" ) && _R3POST=0 || _R3POST=1
rm -f "${HOME}/.claude/.skill-reviewer-saturated-session-${_SID}"
if [ "$_R3PRE" -eq 1 ] && [ "$_R3POST" -eq 0 ]; then
    _record_pass "(r3) reviewer_pairing_saturated tracks the marker"
else
    _record_fail "(r3) reviewer_pairing_saturated tracks the marker" "pre=${_R3PRE} post=${_R3POST}"
fi

# (r4) the SHIPPED default is the documented one. The cells above drive an
# override, so without this nothing would notice the real constant changing.
_R4="$( . "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh"; printf '%s' "${_REVIEWER_PAIRING_MAX_BYTES}" )"
if [ "${_R4}" = "1048576" ]; then
    _record_pass "(r4) the shipped ceiling is the documented 1 MiB"
else
    _record_fail "(r4) the shipped ceiling is the documented 1 MiB" "got ${_R4}"
fi

# ===========================================================================
# Lookup exactness
# ===========================================================================

# --- (i) the lookup is an exact FIELD match --------------------------------
# `awk '$1==a'` is load-bearing: a prefix or a regex must not join.
#
# The planted record MUST carry the REAL ledger key. An earlier version planted
# a placeholder, so the branch comparison refused the credit no matter what the
# lookup did, and both cells passed with the exactness deleted — the mutation
# was masked by an unrelated correct guard. Isolating one variable means every
# OTHER gate has to be satisfied.
_KEYNOW="$(cd "$_REPO" && branch_ledger_key)"
_reset; printf '%s %s\n' "px-1xyz" "$_KEYNOW" > "$(_dispatch_file)"
_run_completion "px-1" "output" >/dev/null
if _has; then _record_fail "(i1) a prefix does not join" "ledger entry written"
else _record_pass "(i1) a prefix does not join"; fi

_reset; printf '%s %s\n' "rx-219" "$_KEYNOW" > "$(_dispatch_file)"
_run_completion "rx-2.9" "output" >/dev/null
if _has; then _record_fail "(i2) a regex metachar in the agent id does not join" "ledger entry written"
else _record_pass "(i2) a regex metachar in the agent id does not join"; fi

# (i3) POSITIVE CONTROL for (i1)/(i2). Without it, "did not credit" is
# indistinguishable from "this harness cannot credit at all" — the exact
# mistake that made the two cells above vacuous. Same planted-record shape,
# exact id, must credit.
_reset; printf '%s %s\n' "px-2" "$_KEYNOW" > "$(_dispatch_file)"
_run_completion "px-2" "output" >/dev/null
if _has; then _record_pass "(i3) positive control: an exact planted record DOES join"
else _record_fail "(i3) positive control: an exact planted record DOES join" "no ledger entry"; fi

# ===========================================================================
# Contracts and regressions
# ===========================================================================

# --- (j) recorder contract: nothing on stdout, exit 0, on the CREDIT path ---
# `_run_completion` sets _STATUS, but capturing its stdout with `$( )` runs it in
# a SUBSHELL and the assignment is discarded — an earlier version of this cell
# read a stale _STATUS belonging to a previous cell, so the "exits 0" half
# asserted nothing about this invocation. Capture to a file instead, so the
# helper runs in THIS shell.
_reset
_run_dispatch "out-1" "Review the diff for correctness"
_OUTFILE="${HOME}/out.txt"
_run_completion "out-1" "Findings: 1" > "${_OUTFILE}"
_JSTATUS="${_STATUS}"
_OUT="$(cat "${_OUTFILE}" 2>/dev/null)"
if [ -n "${_OUT}" ]; then _record_fail "(j) recorder writes nothing to stdout" "stdout: ${_OUT}"
elif [ "${_JSTATUS}" -ne 0 ]; then _record_fail "(j) recorder exits 0" "exit ${_JSTATUS}"
else _record_pass "(j) recorder writes nothing to stdout and exits 0"; fi

# --- (j2) an exhausted completion file must not kill the join --------------
# `reviewer_pairing_note_complete` returns non-zero when the append does not
# happen (size ceiling, unwritable HOME). Unguarded under `trap 'exit 0' ERR`
# that terminates the hook before the join, silently ending every credit for the
# session. Found by a mutation whose real fault was masked by this early exit.
# The ceiling is OVERRIDDEN rather than out-padded. Hardcoded padding silently
# stops testing anything the moment the constant moves — and it already did once
# here: raising the ceiling to 1 MiB left this cell padding to ~90 KB, which made
# it vacuous, and only a mutation showed it. Driving the constant instead keeps
# the cell tied to the mechanism and takes milliseconds.
export REVIEWER_PAIRING_MAX_BYTES=200
_reset
_run_dispatch "full-1" "Review the diff for correctness"
printf '%0400d\n' 0 >> "$(_complete_file)"        # now over the 200-byte ceiling
_run_completion "full-1" "Findings: 1" >/dev/null
if _has; then _record_pass "(j2) a full completion file does not stop the join (bg order)"
else _record_fail "(j2) a full completion file does not stop the join (bg order)" "no ledger entry"; fi

# (j3) The SAME state in the FOREGROUND order. This is the order where the
# ceiling actually bites — the completion half cannot be published, so there is
# nothing for the later dispatch to join against. Asserted as the DOCUMENTED
# behaviour (no credit) rather than as a passing credit: the cell pins the limit
# so it stays visible, it does not claim it is fixed.
#
# THIS IS NOT UNFIXABLE, and an earlier comment here wrongly called it
# structural. The signal exists: `reviewer_pairing_note_complete` returns
# non-zero at reviewer-completion-hook.sh's HALF ONE and the `|| true` discards
# it. What is missing is somewhere to put it — the fact is SESSION-scoped ("this
# session's completion half stopped accepting writes"), not agent-scoped, so
# recording it needs a new state family (one more GC glob plus the paired
# `! -name` exclusion that cell (p) already forces). Declined for this increment
# because the ceiling is 1 MiB (~26k completions), not because it cannot be done.
# A prerequisite if it is ever taken: `_reviewer_pairing_append` must
# DISTINGUISH ceiling-refusal from failed-write, since an unwritable ~/.claude
# cannot record the marker either, and conflating them rebuilds the exact
# collapse the marker would exist to prevent.
_reset
printf '%0400d\n' 0 > "$(_complete_file)"          # over the overridden ceiling
_run_completion "full-2" "Findings: 1" >/dev/null
_run_dispatch "full-2" "Review the diff for correctness"
if _has; then
    _record_fail "(j3) foreground order at the ceiling is a documented miss" "credited unexpectedly — the ceiling may have moved; revisit the limit note"
else
    _record_pass "(j3) foreground order at the ceiling is a documented miss"
fi

# (j4) A non-reviewer completion must leave NO mismatch line. Without the
# `[ -n "${_DKEY}" ]` guard the hook fabricates `# branch-mismatch` lines for
# every ordinary subagent — a FALSE diagnostic ("never dispatched as a reviewer"
# is not "branch mismatch") that also accelerates the ceiling above. Before this
# cell, only the PRESENCE of a mismatch line was asserted, never its absence,
# which is the asymmetry that let that mutation through.
_reset
_run_completion "plain-1" "Implemented the parser" >/dev/null
if grep -q '^# branch-mismatch' "$(_dispatch_file)" 2>/dev/null; then
    _record_fail "(j4) a non-reviewer completion leaves no mismatch line" "fabricated a branch-mismatch diagnostic"
else
    _record_pass "(j4) a non-reviewer completion leaves no mismatch line"
fi

# The overridden ceiling is scoped to the cells that need it. Leaving it set
# would silently apply a 200-byte limit to every later cell, which is the same
# class of cross-cell coupling that made (r2) vacuous.
unset REVIEWER_PAIRING_MAX_BYTES

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

# --- (l) the dispatch hook still records reviewer-ran -----------------------
# The regression that actually happened: new best-effort work placed ABOVE the
# existing ledger write tripped the ERR trap on a redirection failure and
# silently deleted the pre-existing milestone.
_reset
_run_dispatch "ran-1" "Review the diff for correctness"
if _has_ran; then _record_pass "(l1) dispatch hook still records reviewer-ran"
else _record_fail "(l1) dispatch hook still records reviewer-ran" "no reviewer-ran entry"; fi

# ...including when the new code's inputs are hostile.
_reset
_dispatch_payload "safe-id-1" "Review the diff for correctness" "../../nope" \
  | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${DISPATCH_HOOK}" ) >/dev/null 2>&1
if _has_ran; then _record_pass "(l2) an unsafe session_id does not suppress reviewer-ran"
else _record_fail "(l2) an unsafe session_id does not suppress reviewer-ran" "no reviewer-ran entry"; fi

# --- (m) an unsafe session_id is refused, and the traversal is REACHABLE ----
# A bare "../../escape" resolves through a non-existent directory and is refused
# whether the guard exists or not — an earlier version of this cell was vacuous
# for exactly that reason. Here the first path component is made to exist, so
# without the guard the lookup genuinely escapes to the planted file and joins.
_reset
mkdir -p "${HOME}/.claude/.skill-reviewer-dispatch-session-x"
printf '%s %s\n' "esc-1" "$(cd "$_REPO" && branch_ledger_key)" > "${HOME}/planted-dispatch"
_run_completion "esc-1" "Findings: 1" "x/../../planted-dispatch" >/dev/null
if [ "${_STATUS}" -ne 0 ]; then
    _record_fail "(m) unsafe session_id is refused" "exit ${_STATUS}"
elif _has; then
    _record_fail "(m) unsafe session_id is refused" "escaped to the planted file and credited"
else
    _record_pass "(m) unsafe session_id is refused, exit 0"
fi
rm -rf "${HOME}/.claude/.skill-reviewer-dispatch-session-x" "${HOME}/planted-dispatch"

# ===========================================================================
# Wiring
# ===========================================================================

if jq -e '[.hooks.SubagentStop[]?.hooks[]?.command]
          | any(test("reviewer-completion-hook\\.sh"))' \
     "${PROJECT_ROOT}/hooks/hooks.json" >/dev/null 2>&1; then
    _record_pass "(n1) registered on SubagentStop in hooks.json"
else
    _record_fail "(n1) registered on SubagentStop in hooks.json" "not found"
fi

# The event name is exact. A typo registers a hook that never fires, and the
# failure mode is silence, which every behavioural cell above would sail past.
if jq -e '.hooks | keys | any(. == "SubagentStop")' \
     "${PROJECT_ROOT}/hooks/hooks.json" >/dev/null 2>&1; then
    _record_pass "(n2) the event key is spelled SubagentStop"
else
    _record_fail "(n2) the event key is spelled SubagentStop" "no such key"
fi

# --- (o) diagnostic-only: never a gate-enforcement component ---------------
# _GATE_ENFORCE_LIBS drives both the session-start precondition canary and the
# installed-plugin drift manifest. A diagnostic recorder joining it would make a
# missing recorder announce as a degraded GATE.
_OFF=0
for _f in reviewer-completion-hook reviewer-pairing; do
    grep -q "$_f" "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null && _OFF=1
done
if [ "$_OFF" -eq 1 ]; then
    _record_fail "(o1) not a gate-enforcement component" "referenced by session-start canary/manifest"
else
    _record_pass "(o1) not a gate-enforcement component"
fi

if grep -q 'reviewer-returned' "${PROJECT_ROOT}/hooks/openspec-guard.sh" 2>/dev/null; then
    _record_fail "(o2) no gate reads reviewer-returned in this change" "openspec-guard.sh references it"
else
    _record_pass "(o2) no gate reads reviewer-returned in this change"
fi

# --- (p) both pairing families are GC'd, each with its own exclusion --------
# Behavioural pruning is asserted in tests/test-state-file-cleanup.sh. Here every
# family is pinned together, so adding a glob without its current-session
# exclusion — which would prune the LIVE session's state and silently break every
# later join — cannot pass. Adding a family means adding it in BOTH places, and
# this loop is what forces that.
_SS="${PROJECT_ROOT}/hooks/session-start-hook.sh"
_GCOK=1
for _k in dispatch complete saturated; do
    grep -q "name '\.skill-reviewer-${_k}-\*'" "$_SS" 2>/dev/null || _GCOK=0
    grep -q "! -name \"\.skill-reviewer-${_k}-\${_SESSION_TOKEN}\"" "$_SS" 2>/dev/null || _GCOK=0
done
if [ "$_GCOK" -eq 1 ]; then
    _record_pass "(p) all pairing families are GC'd with current-session exclusions"
else
    _record_fail "(p) all pairing families are GC'd with current-session exclusions" "a glob or exclusion is missing"
fi

# --- (q) writer and reader must agree on the id charset, BOTH pairs -----------
# Asserted as AGREEMENT rather than as two separate rejection lists: independent
# assertions of "the writer rejects X" and "the reader rejects X" both keep
# passing while the two lists drift apart, which is a silent miss and exactly the
# writer/reader split this lib exists to prevent.
#
# BOTH pairs, deliberately. An earlier version covered only dispatch/dispatch_key
# — and complete_key, which the branch-binding fix depends on, had zero test
# callers, so deleting its guard produced no observable failure anywhere.
#
# The record is PLANTED DIRECTLY rather than written through the writer, so a
# reader's "accept" is not confounded with "the writer happened to store it".
#
# LIMIT, stated rather than papered over: for an id the writer rejects, the
# reader also fails to find a planted line (its `$1` cannot equal an id
# containing a space), so the two agree for two different reasons. This cell
# therefore reliably detects READER-STRICTER-THAN-WRITER drift — the direction
# that silently loses real records — and not the converse.
#
# Loop is heredoc-fed, NOT piped: a piped loop runs in a subshell and its
# _record_pass/_record_fail calls vanish from the summary (CLAUDE.md).
_QHOME="$(mktemp -d /tmp/rch-q-XXXXXX)"; _QOLD="$HOME"; export HOME="$_QHOME"; mkdir -p "$HOME/.claude"
_QSID="qqqqqqqq-1111-2222-3333-444444444444"
_QKEY="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
_QD="${HOME}/.claude/.skill-reviewer-dispatch-session-${_QSID}"
_QC="${HOME}/.claude/.skill-reviewer-complete-session-${_QSID}"
_QAGREE=1; _QDETAIL=""
while IFS= read -r _qid; do
    [ -n "$_qid" ] || continue
    ( . "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh"
      rm -f "$_QD" "$_QC"
      reviewer_pairing_note_dispatch "$_QSID" "$_qid" "$_QKEY" >/dev/null 2>&1 && _wd=accept || _wd=reject
      reviewer_pairing_note_complete "$_QSID" "$_qid" "$_QKEY" >/dev/null 2>&1 && _wc=accept || _wc=reject
      printf '%s %s\n' "$_qid" "$_QKEY" > "$_QD"
      printf '%s %s\n' "$_qid" "$_QKEY" > "$_QC"
      reviewer_pairing_dispatch_key "$_QSID" "$_qid" >/dev/null 2>&1 && _rd=accept || _rd=reject
      reviewer_pairing_complete_key "$_QSID" "$_qid" >/dev/null 2>&1 && _rc=accept || _rc=reject
      [ "$_wd" = "$_rd" ] || printf 'dispatch[%s: w=%s r=%s] ' "$_qid" "$_wd" "$_rd"
      [ "$_wc" = "$_rc" ] || printf 'complete[%s: w=%s r=%s] ' "$_qid" "$_wc" "$_rc" ) > "${_QHOME}/out" 2>/dev/null
    _qout="$(cat "${_QHOME}/out" 2>/dev/null)"
    if [ -n "$_qout" ]; then _QAGREE=0; _QDETAIL="${_QDETAIL} ${_qout}"; fi
done <<'QIDS'
abc-1
a.b_c
A1
0123456789abcdef0
a b
a/b
a;b
a*b
#
QIDS
export HOME="$_QOLD"; rm -rf "$_QHOME"
if [ "$_QAGREE" -eq 1 ]; then
    _record_pass "(q) writer and reader agree on the id charset, both pairs"
else
    _record_fail "(q) writer and reader agree on the id charset, both pairs" "disagreements:${_QDETAIL}"
fi

# --- (s) the probed source-guard symbol IS the lib's last definition ---------
# Both hooks deliberately probe a symbol neither of them may call, because a lib
# truncated at a function boundary sources cleanly and would leave later
# definitions undefined. That only works while the probed symbol really is last —
# append a function to the lib and the guarantee silently reverts. The cost of
# the choice is that deleting or renaming that symbol disables the join in BOTH
# hooks without erroring, so it is pinned here rather than left to memory.
_LASTFN="$(grep -o '^[a-z_][a-z_]*() {' "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh" | tail -1 | sed 's/() {//')"
_SOK=1
for _h in reviewer-completion-hook reviewer-evidence-hook; do
    grep -q "command -v ${_LASTFN} >/dev/null 2>&1" "${PROJECT_ROOT}/hooks/${_h}.sh" 2>/dev/null || _SOK=0
done
if [ -n "${_LASTFN}" ] && [ "$_SOK" -eq 1 ]; then
    _record_pass "(s) both hooks probe the lib's last-defined function (${_LASTFN})"
else
    _record_fail "(s) both hooks probe the lib's last-defined function" "last='${_LASTFN}' — a hook probes something else"
fi

rm -rf "$_REPO" "$_REPO2"
export HOME="$_OLDHOME"
print_summary
exit $?

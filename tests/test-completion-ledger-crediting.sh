#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-completion-ledger-crediting.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"

# Sandbox HOME; transcript basename "t" -> token "session-t".
_OLDHOME="$HOME"
# Under TMPDIR and removed on exit (#372); it used to stay in /tmp for good.
# The trap names it by its own variable, never by HOME, which may be restored.
_CLHOME="$(mktemp -d "${TMPDIR:-/tmp}/cl-home-XXXXXX")" || exit 1
export HOME="${_CLHOME}"
trap 'rm -rf "${_CLHOME}"' EXIT
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"
_TOK="session-t"
# A valid composition state must exist or the hook exits early.
printf '%s' '{"chain":[],"current_index":0,"completed":[]}' \
    > "$HOME/.claude/.skill-composition-state-${_TOK}"

# Build a PostToolUse(Skill) payload for a given completed skill name.
# Run the hook with CWD pinned to PROJECT_ROOT: the hook records the ledger
# milestone under its default proj_root (resolved from CWD), and the assertions
# below check under PROJECT_ROOT — so the test must not depend on the caller's cwd.
# Optional: $2 = tool_input key (`name`, default, or `skill` — the shape the
# typed-slash synthetic payload uses), $3 = acs_source (omitted when empty),
# $4 = plugin root (default PROJECT_ROOT; the lib-missing cells point it at a
# copy of the plugin tree). The hook under test is always the real one.
_run_completion() {
    jq -n --arg tp "$_TPATH" --arg name "$1" --arg key "${2:-name}" --arg src "${3:-}" \
      '{"transcript_path":$tp,"tool_response":{"is_error":false},"tool_input":{($key):$name}}
       | if $src == "" then . else . + {"acs_source":$src} end' \
    | ( cd "${PROJECT_ROOT}" && CLAUDE_PLUGIN_ROOT="${4:-${PROJECT_ROOT}}" bash "${HOOK}" ) >/dev/null 2>&1
}

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"

# (a) subagent-driven-development completion => REVIEW milestone recorded.
_run_completion "subagent-driven-development"
if branch_ledger_has "requesting-code-review" "${PROJECT_ROOT}"; then
    _record_pass "SDD completion records canonical REVIEW milestone"
else
    _record_fail "SDD completion records canonical REVIEW milestone" "ledger has no requesting-code-review"
fi

# (a2) the other two review-embedding skills credit the same milestone —
# behavioral, so a rename of either identifier can't silently break the bridge.
for _skill in agent-team-execution agent-team-review; do
    rm -rf "$(branch_ledger_dir "${PROJECT_ROOT}")" 2>/dev/null
    _run_completion "${_skill}"
    if branch_ledger_has "requesting-code-review" "${PROJECT_ROOT}"; then
        _record_pass "${_skill} completion records canonical REVIEW milestone"
    else
        _record_fail "${_skill} completion records canonical REVIEW milestone" \
            "ledger has no requesting-code-review"
    fi
done

# (b) executing-plans completion => NO REVIEW milestone.
rm -rf "$(branch_ledger_dir "${PROJECT_ROOT}")" 2>/dev/null
_run_completion "executing-plans"
if branch_ledger_has "requesting-code-review" "${PROJECT_ROOT}"; then
    _record_fail "executing-plans does NOT count as REVIEW" "ledger unexpectedly has requesting-code-review"
else
    _record_pass "executing-plans does NOT count as REVIEW"
fi

_clear_ledger() {
    local _d; _d="$(branch_ledger_dir "${PROJECT_ROOT}")" || return 0
    [ -n "${_d}" ] && rm -rf "${_d}" 2>/dev/null
    return 0
}
# _expect_review <label> <yes|no> — asserts the canonical REVIEW milestone's
# presence after the preceding _run_completion.
_expect_review() {
    if branch_ledger_has "requesting-code-review" "${PROJECT_ROOT}"; then
        if [ "$2" = "yes" ]; then _record_pass "$1"
        else _record_fail "$1" "ledger unexpectedly has requesting-code-review"; fi
    else
        if [ "$2" = "yes" ]; then _record_fail "$1" "ledger has no requesting-code-review"
        else _record_pass "$1"; fi
    fi
}

# (c) the equivalent review skills (credited-skills.sh) credit the canonical
# milestone, bare or plugin-prefixed, under either tool_input key.
for _skill in code-review review-pr security-review pr-review-toolkit:review-pr code-review:code-review; do
    _clear_ledger; _run_completion "${_skill}"
    _expect_review "(c) ${_skill} completion records canonical REVIEW milestone" yes
done
_clear_ledger; _run_completion "security-review" skill
_expect_review "(c) security-review via tool_input.skill records REVIEW milestone" yes

# (d) near-misses: an uncredited review-ish name, a name merely CONTAINING a
# credited one, and a multi-token name spanning two credited entries.
for _skill in receiving-code-review code-reviewer simplify my-code-review security-review-x "code-review review-pr"; do
    _clear_ledger; _run_completion "${_skill}"
    _expect_review "(d) near-miss '${_skill}' records NO REVIEW milestone" no
done

# (e) credited-skills.sh unreadable => only today's four credit. Built from
# copies of the plugin's hooks/ in this test's own temp dir (the hook under test
# stays the real one; only CLAUDE_PLUGIN_ROOT moves). The with-lib copy is the
# positive control: without it, "records nothing" could mean a broken copy.
_PC_FULL="${_CLHOME}/plugin-full"; _PC_MISSING="${_CLHOME}/plugin-missing"; _PC_EMPTY="${_CLHOME}/plugin-empty"
for _d in "${_PC_FULL}" "${_PC_MISSING}" "${_PC_EMPTY}"; do
    mkdir -p "${_d}" && cp -R "${PROJECT_ROOT}/hooks" "${_d}/hooks"
done
rm -f "${_PC_MISSING}/hooks/lib/credited-skills.sh"
: > "${_PC_EMPTY}/hooks/lib/credited-skills.sh"   # sources cleanly, defines nothing
if [ -f "${_PC_FULL}/hooks/lib/credited-skills.sh" ] && [ ! -e "${_PC_MISSING}/hooks/lib/credited-skills.sh" ] \
   && [ ! -s "${_PC_EMPTY}/hooks/lib/credited-skills.sh" ]; then
    _record_pass "(e) plugin-tree copies built as intended"
else
    _record_fail "(e) plugin-tree copies built as intended" "copy setup wrong"
fi
_clear_ledger; _run_completion "code-review" name "" "${_PC_FULL}"
_expect_review "(e) control: copied tree WITH the lib credits code-review" yes
for _pc in "${_PC_MISSING}" "${_PC_EMPTY}"; do
    _lbl="missing"; [ "${_pc}" = "${_PC_EMPTY}" ] && _lbl="empty"
    _clear_ledger; _run_completion "code-review" name "" "${_pc}"
    _expect_review "(e) lib ${_lbl}: code-review records NOTHING" no
    _clear_ledger; _run_completion "review-pr" name "" "${_pc}"
    _expect_review "(e) lib ${_lbl}: review-pr records NOTHING" no
    for _skill in agent-team-review subagent-driven-development agent-team-execution requesting-code-review; do
        _clear_ledger; _run_completion "${_skill}" name "" "${_pc}"
        _expect_review "(e) lib ${_lbl}: fallback still credits ${_skill}" yes
    done
done

# (e2) a lib that FAILS A COMMAND while being sourced (#192 shape: `false` at
# its head or tail). The guarded one-line source covers only the source's own
# status; a command failing inside the lib trips the hook's `trap 'exit 0' ERR`
# unless the source is contained in a function. The fallback four and the
# literal gating milestones must still record. Tail shape: every function is
# defined but the source returns 1, so the lib counts as NOT loaded and
# code-review must not credit. (Head shape: the source returns 0 with every
# function defined, so the lib legitimately loads; no code-review assertion.)
_PC_TRAPH="${_CLHOME}/plugin-trap-head"; _PC_TRAPT="${_CLHOME}/plugin-trap-tail"
for _d in "${_PC_TRAPH}" "${_PC_TRAPT}"; do
    mkdir -p "${_d}" && cp -R "${PROJECT_ROOT}/hooks" "${_d}/hooks"
done
{ printf 'false\n'; cat "${PROJECT_ROOT}/hooks/lib/credited-skills.sh"; } > "${_PC_TRAPH}/hooks/lib/credited-skills.sh"
printf 'false\n' >> "${_PC_TRAPT}/hooks/lib/credited-skills.sh"
if [ "$(head -n 1 "${_PC_TRAPH}/hooks/lib/credited-skills.sh")" = "false" ] \
   && [ "$(tail -n 1 "${_PC_TRAPT}/hooks/lib/credited-skills.sh")" = "false" ]; then
    _record_pass "(e2) faulting-lib copies built as intended"
else
    _record_fail "(e2) faulting-lib copies built as intended" "copy setup wrong"
fi
for _pc in "${_PC_TRAPH}" "${_PC_TRAPT}"; do
    _lbl="false-at-head"; [ "${_pc}" = "${_PC_TRAPT}" ] && _lbl="false-at-tail"
    for _skill in agent-team-review subagent-driven-development agent-team-execution requesting-code-review; do
        _clear_ledger; _run_completion "${_skill}" name "" "${_pc}"
        _expect_review "(e2) lib ${_lbl}: ${_skill} still credits REVIEW" yes
    done
    _clear_ledger; _run_completion "verification-before-completion" name "" "${_pc}"
    if branch_ledger_has "verification-before-completion" "${PROJECT_ROOT}"; then
        _record_pass "(e2) lib ${_lbl}: verification-before-completion still records"
    else
        _record_fail "(e2) lib ${_lbl}: verification-before-completion still records" "ledger lacks it"
    fi
done
_clear_ledger; _run_completion "code-review" name "" "${_PC_TRAPT}"
_expect_review "(e2) lib false-at-tail: code-review records NOTHING (lib not loaded)" no

# (f) acs_source "typed-slash" skips ONLY the advisory-lens telemetry line;
# every evidence write (REVIEW ledger, invocation record, sha sidecar,
# .completed, per-chain-step ledger) equals a Skill return's. Run for
# requesting-code-review and for agent-team-review: the latter is a chain step
# whose own name is NOT a gating milestone, so only the per-chain-step ledger
# write can record `agent-team-review` — a typed-slash exit placed above that
# write turns its cell red.
_STATE_F="$HOME/.claude/.skill-composition-state-${_TOK}"
_INVOC_F="$HOME/.claude/.skill-invocation-evidence-${_TOK}"
_SHA_F="$HOME/.claude/.skill-invocation-evidence-sha-${_TOK}"
_TLOG="$HOME/.claude/.advisory-lens-log.jsonl"
_tlines() { if [ -f "${_TLOG}" ]; then wc -l < "${_TLOG}" | tr -d '[:space:]'; else echo 0; fi; }
# _typed_case <label> <acs_source> <expected telemetry delta> <subject skill>
_typed_case() {
    local _before _after _s="$4" _l="$1 [$4]"
    _clear_ledger; rm -f "${_INVOC_F}" "${_SHA_F}"
    jq -nc --arg s "${_s}" '{"chain":[$s],"current_index":0,"completed":[]}' > "${_STATE_F}"
    _before="$(_tlines)"
    _run_completion "${_s}" skill "$2"
    _after="$(_tlines)"
    _expect_review "(f) ${_l}: ledger records requesting-code-review" yes
    if branch_ledger_has "${_s}" "${PROJECT_ROOT}"; then
        _record_pass "(f) ${_l}: per-chain-step ledger records ${_s}"
    else
        _record_fail "(f) ${_l}: per-chain-step ledger records ${_s}" "ledger lacks ${_s}"
    fi
    if jq -e --arg s "${_s}" 'index($s) != null' "${_INVOC_F}" >/dev/null 2>&1; then
        _record_pass "(f) ${_l}: invocation evidence contains ${_s}"
    else
        _record_fail "(f) ${_l}: invocation evidence contains ${_s}" "missing from ${_INVOC_F}"
    fi
    if grep -q "^${_s} [0-9a-f]\{40\}\$" "${_SHA_F}" 2>/dev/null; then
        _record_pass "(f) ${_l}: sha sidecar records ${_s}"
    else
        _record_fail "(f) ${_l}: sha sidecar records ${_s}" "no sidecar line"
    fi
    if jq -e --arg s "${_s}" '(.completed // []) | index($s) != null' "${_STATE_F}" >/dev/null 2>&1; then
        _record_pass "(f) ${_l}: .completed gains ${_s}"
    else
        _record_fail "(f) ${_l}: .completed gains ${_s}" "not in .completed"
    fi
    if [ "$(( _after - _before ))" -eq "$3" ]; then
        _record_pass "(f) ${_l}: telemetry gains $3 line(s)"
    else
        _record_fail "(f) ${_l}: telemetry gains $3 line(s)" "gained $(( _after - _before ))"
    fi
}
for _subj in requesting-code-review agent-team-review; do
    _typed_case "typed-slash" "typed-slash" 0 "${_subj}"
    _typed_case "control, no acs_source" "" 1 "${_subj}"
    _typed_case "near-miss acs_source typed-slash-x" "typed-slash-x" 1 "${_subj}"
done
printf '%s' '{"chain":[],"current_index":0,"completed":[]}' > "${_STATE_F}"

# (g) verification-before-completion records its own milestone, never REVIEW.
_clear_ledger; _run_completion "verification-before-completion"
if branch_ledger_has "verification-before-completion" "${PROJECT_ROOT}"; then
    _record_pass "(g) verification-before-completion records its own milestone"
else
    _record_fail "(g) verification-before-completion records its own milestone" "ledger lacks it"
fi
_expect_review "(g) verification-before-completion records NO REVIEW milestone" no

export HOME="$_OLDHOME"
print_summary
exit $?

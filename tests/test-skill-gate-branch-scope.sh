#!/usr/bin/env bash
# tests/test-skill-gate-branch-scope.sh — #249
#
# Two `Skill(requesting-code-review)` denies were observed live that no on-disk
# replay reproduced. The replay controlled the hook FILE and not the SUBJECT.
#
# `phase_step_satisfied`'s second leg is `branch_ledger_has`, and
# `branch_ledger_key` hashes (origin remote URL, BRANCH NAME). So the gate's
# evidence is branch-keyed: a step recorded on one branch is invisible from
# another, and a deny is correct for the branch it was measured on while the
# same command allows from a sibling worktree. Reproduced under isolation with
# one variable moved — same token, payload, chain and hook file, two branches of
# the same repo, allow vs deny, with the allowing arm as the positive control.
#
# That mechanism is SUFFICIENT for the reported shape, not proven to be its
# cause: the branch at deny time was never recorded, so the original pair is not
# decidable after the fact. This file pins the fix for that — the gate now says
# which branch and root it consulted, so the NEXT occurrence is self-diagnosing.
#
# The note is message material only. Nothing gates on it, and a branch that
# cannot be resolved degrades to no note rather than to a different decision.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-skill-gate-branch-scope.sh ==="

GATE="${PROJECT_ROOT}/hooks/skill-gate.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq unavailable — this file drives the real gate and cannot degrade"; exit 1
fi

_OLDHOME="$HOME"
TMP="$(mktemp -d /tmp/sgbs-XXXXXX)"
export HOME="${TMP}/home"; mkdir -p "${HOME}/.claude"
_TPATH="${HOME}/p.jsonl"; touch "${_TPATH}"
TOK="session-p"
printf '%s' '{"chain":["brainstorming","writing-plans","executing-plans","requesting-code-review"],"current_index":3,"completed":[]}' \
    > "${HOME}/.claude/.skill-composition-state-${TOK}"

# Two repos, SAME origin URL, DIFFERENT branch — different ledger keys by
# construction, which is the whole point of the mechanism under test.
_mkrepo() {  # _mkrepo <dir> <branch>
    mkdir -p "$1"
    ( cd "$1"
      git init -q; git config user.email t@t; git config user.name t
      git remote add origin https://example.invalid/acs.git
      echo x > f; git add -A; git commit -qm c1
      git checkout -q -b "$2" )
}
_mkrepo "${TMP}/alpha" branch-alpha
_mkrepo "${TMP}/beta"  branch-beta

_run() {  # _run <proj-root> -> gate stdout
    printf '%s' "{\"tool_name\":\"Skill\",\"tool_input\":{\"skill\":\"superpowers:requesting-code-review\"},\"transcript_path\":\"${_TPATH}\"}" \
      | ( cd "$1" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="$1" \
            /bin/bash "${GATE}" 2>/dev/null )
}
_text() { printf '%s' "${1:-}" | jq -r '(.hookSpecificOutput.permissionDecisionReason // .systemMessage // "")' 2>/dev/null; }

test_preconditions() {
    if [ -r "${GATE}" ] && [ -d "${TMP}/alpha/.git" ] && [ -d "${TMP}/beta/.git" ]; then
        _record_pass "gate and both fixture repos are present"
    else
        _record_fail "gate and both fixture repos are present" "missing one — cells below vacuous"
    fi
}

test_the_gate_names_the_branch_it_consulted() {
    local t
    t="$(_text "$(_run "${TMP}/alpha")")"
    assert_contains "the message names the branch evidence was looked up for" \
        "branch-alpha" "${t:-<empty>}"
    assert_contains "...and the root it was looked up in" \
        "${TMP}/alpha" "${t:-<empty>}"
    assert_contains "...and says a different branch is not visible from here" \
        "different branch" "${t:-<empty>}"
}

test_the_named_branch_is_resolved_not_hardcoded() {
    # A note that always said the same thing would pass the cell above while
    # telling the next investigator nothing. The name has to track the subject.
    local a b
    a="$(_text "$(_run "${TMP}/alpha")")"
    b="$(_text "$(_run "${TMP}/beta")")"
    assert_contains     "the beta repo reports branch-beta"     "branch-beta"  "${b:-<empty>}"
    assert_not_contains "...and does not report the alpha branch" "branch-alpha" "${b:-}"
    assert_contains     "CONTROL: the alpha repo still reports branch-alpha" "branch-alpha" "${a:-<empty>}"
}

test_an_unresolvable_branch_degrades_to_no_note() {
    # Outside a repository the branch cannot be resolved. The gate must still
    # produce its decision and message, just without the locator — degrading to
    # silence, never to a different outcome or an empty/garbled sentence.
    local nonrepo t
    nonrepo="${TMP}/plain"; mkdir -p "${nonrepo}"
    t="$(_text "$(_run "${nonrepo}")")"
    assert_contains     "the gate still explains the missing step" "has no invocation evidence" "${t:-<empty>}"
    assert_not_contains "and adds no half-written locator"          "Evidence was looked up for branch ''" "${t:-}"
}

test_the_locator_never_gates() {
    # Nothing may branch on it. If the resolved branch ever reaches a decision,
    # an unresolvable branch becomes a different outcome rather than less text.
    if grep -nE '_SG_(BRANCH|WHERE)' "${GATE}" | grep -qE 'exit|permissionDecision|_MODE=|phase_gate_log'; then
        _record_fail "the branch locator never touches a decision" \
            "found _SG_BRANCH/_SG_WHERE on a line that also decides, exits or logs a gate outcome"
    else
        _record_pass "the branch locator never touches a decision"
    fi
}

assert_test_functions_wired "$0"

test_preconditions
test_the_gate_names_the_branch_it_consulted
test_the_named_branch_is_resolved_not_hardcoded
test_an_unresolvable_branch_degrades_to_no_note
test_the_locator_never_gates

export HOME="${_OLDHOME}"
rm -rf "${TMP}"
print_summary

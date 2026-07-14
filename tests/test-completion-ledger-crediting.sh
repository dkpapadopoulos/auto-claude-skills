#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-completion-ledger-crediting.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"

# Sandbox HOME; transcript basename "t" -> token "session-t".
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/cl-home-XXXXXX)"
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
_run_completion() {
    jq -n --arg tp "$_TPATH" --arg name "$1" \
      '{"transcript_path":$tp,"tool_response":{"is_error":false},"tool_input":{"name":$name}}' \
    | ( cd "${PROJECT_ROOT}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) >/dev/null 2>&1
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

export HOME="$_OLDHOME"
print_summary
exit $?

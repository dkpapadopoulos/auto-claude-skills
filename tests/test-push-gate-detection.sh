#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-detection.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pgd-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"
_TOK="session-t"
# REVIEW+VERIFY in chain, completed empty, no ledger, no verdict => a real push
# hits the fail-closed gate and DENIES. A non-write command must exit before that.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' \
    > "$HOME/.claude/.skill-composition-state-${_TOK}"

_run() {
    jq -n --arg tp "$_TPATH" --arg c "$1" \
      '{"transcript_path":$tp,"tool_input":{"command":$c}}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null
}

# (a) Read-only command that merely mentions the phrase -> NO deny.
out="$(_run 'grep -nE "git push|deny" hooks/openspec-guard.sh')"
assert_not_contains "grep with phrase is not gated" '"deny"' "${out:-}"

# (b) echo mentioning the phrase -> NO deny.
out="$(_run 'echo "reminder: git push later"')"
assert_not_contains "echo with phrase is not gated" '"deny"' "${out:-}"

# (c) A real push with no evidence -> DENY (gate still fires).
out="$(_run 'git push origin HEAD')"
assert_contains "real push is gated" '"deny"' "${out:-<empty>}"

# (d) A real push via -C global flag -> DENY.
out="$(_run 'git -C /tmp/x push -u origin feature/y')"
assert_contains "push with -C is gated" '"deny"' "${out:-<empty>}"

export HOME="$_OLDHOME"
print_summary
exit $?

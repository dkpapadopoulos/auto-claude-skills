#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-ledger.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

# Content assertions (wiring checks before behavioral tests)
g="$(cat "${GUARD}")"
assert_contains "gate sources branch-ledger"        "branch-ledger.sh"  "${g}"
assert_contains "gate consults ledger for review"   "branch_ledger_has" "${g}"
assert_contains "gate emits soft staleness warning" "stale"             "${g}"

# Behavioral setup
# Token resolution: transcript_path="$HOME/t.jsonl" -> basename without .jsonl
# -> "t" -> token "session-t". The payload-first resolver does NOT fall back to
# the singleton for a valid (even non-existent) path, so we control the token
# by controlling the transcript filename.
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pg-home-XXXXXX)"
mkdir -p "$HOME/.claude"

_TPATH="$HOME/t.jsonl"
touch "$_TPATH"               # real file; basename gives "t" -> token "session-t"
_TOK="session-t"
_COMP="$HOME/.claude/.skill-composition-state-${_TOK}"

# Composition state: REVIEW + VERIFY in chain; completed is EMPTY
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' \
    > "${_COMP}"

_mkinput() {
    # Use jq to build JSON safely so any path characters are properly escaped
    jq -n --arg tp "$_TPATH" \
        '{"transcript_path":$tp,"tool_input":{"command":"git push origin HEAD"}}'
}
# jq outputs pretty-printed JSON; deny appears as the quoted string "deny" in
# the permissionDecision field, so we use "deny" (with surrounding quotes) as
# the needle -- compact enough to be distinctive, works with pretty-printed output.
run_guard() { _mkinput | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null; }

# (a) No ledger entries, completed empty -> DENY (baseline preserved)
out="$(run_guard)"
assert_contains "no ledger + empty completed => deny" '"deny"' "${out:-<empty>}"

# (b) Ledger satisfies both gates -> ALLOW (no deny)
# Source ledger lib and record both milestones under the sandbox HOME so the
# guard (which inherits HOME) can find the markers.
# Explicit proj_root ensures both record and lookup use the same key.
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
branch_ledger_record "requesting-code-review"         "${PROJECT_ROOT}"
branch_ledger_record "verification-before-completion"  "${PROJECT_ROOT}"
out="$(run_guard)"
assert_not_contains "ledger satisfies => no deny" '"deny"' "${out:-}"

# (c) Ledger satisfies but stale SHA -> WARNING (stale) + no deny
# Overwrite ledger files with a fake SHA to simulate stale entries.
_LEDGER_DIR="$(branch_ledger_dir "${PROJECT_ROOT}")"
printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2000-01-01T00:00:00Z\n' \
    > "${_LEDGER_DIR}/requesting-code-review"
printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2000-01-01T00:00:00Z\n' \
    > "${_LEDGER_DIR}/verification-before-completion"
out="$(run_guard)"
assert_contains     "stale ledger => staleness warning" "stale"   "${out:-<empty>}"
assert_not_contains "stale ledger => no deny"           '"deny"'   "${out:-}"

export HOME="$_OLDHOME"
print_summary
exit $?

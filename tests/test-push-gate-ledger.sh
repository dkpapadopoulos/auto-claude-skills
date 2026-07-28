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

# This repo IS a skill-routing repo (has config/default-triggers.json), so the
# routing-governance gate would independently deny a routing-touching push that
# lacks a clean verdict. Provide one covering HEAD so these assertions isolate the
# STATUS-layer ledger behavior (the routing gate is exercised in test-push-gate-verdict.sh).
_PVHEAD="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null)"
jq -nc --arg s "${_PVHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' \
    > "$HOME/.claude/.skill-project-verified-${_TOK}"

_mkinput() {
    # Use jq to build JSON safely so any path characters are properly escaped.
    # Optional $1 overrides the command; empty/unset keeps the historic default
    # so every existing bare `run_guard` call site is unaffected.
    jq -n --arg tp "$_TPATH" --arg c "${1:-git push origin HEAD}" \
        '{"transcript_path":$tp,"tool_input":{"command":$c}}'
}
# jq outputs pretty-printed JSON; deny appears as the quoted string "deny" in
# the permissionDecision field, so we use "deny" (with surrounding quotes) as
# the needle -- compact enough to be distinctive, works with pretty-printed output.
run_guard() { _mkinput "${1:-}" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null; }

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

# (c) Ledger satisfies but stale SHA -> staleness advisory (no deny, no auto-approve).
# Staleness is folded into the SHIP-phase _WARNINGS (additionalContext), NOT a standalone
# permissionDecision:allow, so the session must be in SHIP phase for it to surface.
_LEDGER_DIR="$(branch_ledger_dir "${PROJECT_ROOT}")"
printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2000-01-01T00:00:00Z\n' \
    > "${_LEDGER_DIR}/requesting-code-review"
printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 2000-01-01T00:00:00Z\n' \
    > "${_LEDGER_DIR}/verification-before-completion"
printf '%s' '{"skill":"verification-before-completion","phase":"SHIP"}' \
    > "$HOME/.claude/.skill-last-invoked-${_TOK}"
out="$(run_guard)"
assert_contains     "stale ledger => staleness advisory" "stale"        "${out:-<empty>}"
assert_contains     "staleness emitted as additionalContext" "additionalContext" "${out:-<empty>}"
assert_not_contains "stale ledger => no deny"            '"deny"'        "${out:-}"
assert_not_contains "stale path no longer auto-approves" '"permissionDecision"' "${out:-}"

# (c2) issue #166 — the SAME stale fixture, but a MERGE. The staleness text above
# is computed from the LOCAL branch HEAD, which for `gh pr merge <other-PR>` is
# unrelated to what is being merged. #161 fixed the non-SHIP flush
# (_flush_push_advisories) to emit only the IMPLEMENT subset on a resolved
# merge, but the SHIP-phase _WARNINGS fold-in is a DIFFERENT mechanism and was
# left ungated — so during SHIP a merge still surfaced branch-local text as
# though it described the merged PR. The push case above is the control: it
# MUST keep showing staleness.
out="$(run_guard 'gh pr merge 7 --squash')"
assert_not_contains "SHIP merge does not leak branch-local staleness" "stale" "${out:-}"
assert_not_contains "SHIP merge stays advisory (no deny)" '"deny"' "${out:-}"
out="$(run_guard)"
assert_contains "control: SHIP push still shows staleness" "stale" "${out:-<empty>}"

export HOME="$_OLDHOME"
print_summary
exit $?

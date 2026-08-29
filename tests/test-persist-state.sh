#!/usr/bin/env bash
# test-persist-state.sh — replaces test-openspec-state-token-symmetry.sh.
# The old test pinned that ~7 copies of the token incantation stayed identical.
# The incantation now lives in exactly one place (scripts/persist-state.sh), so
# the coverage that matters is: (1) the script resolves the token the same way
# the readers do, (2) each op writes the state the old inline call produced, and
# (3) no writer surface still re-derives the incantation (call-site assertion).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-persist-state.sh ==="

SCRIPT="${PROJECT_ROOT}/scripts/persist-state.sh"
assert_file_exists "persist-state.sh exists" "${SCRIPT}"

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/ps-home-XXXXXX)"; mkdir -p "$HOME/.claude"
_run() { CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${SCRIPT}" "$@"; }
_state() { cat "$HOME/.claude/.skill-openspec-state-${1}" 2>/dev/null; }
# Force the token in this synthetic HOME: resolve_own_session_token rejects a
# CLAUDE_CODE_SESSION_ID with no matching ~/.claude/projects/*/<id>.jsonl and
# falls to the singleton, so writing the singleton pins the token — the SAME
# path a real reader takes when the resolver can't validate an id.
_force_token() { printf '%s' "$1" > "$HOME/.claude/.skill-session-token"; }

# --- token resolution --------------------------------------------------------
# 1. SKILL_SESSION_TOKEN is DELIBERATELY NOT honored (openspec-state readers do
#    not honor it — #157). A set override must NOT redirect the write; the
#    singleton token governs instead.
_force_token "session-govern"
SKILL_SESSION_TOKEN="session-override" _run set-intent "A :: out-of-scope: B" >/dev/null 2>&1
assert_file_exists   "override IGNORED: write lands under the real token" "$HOME/.claude/.skill-confirmed-intent-session-govern"
[ -f "$HOME/.claude/.skill-confirmed-intent-session-override" ] && _record_fail "SKILL_SESSION_TOKEN must not be honored" "wrote under the override token" || _record_pass "SKILL_SESSION_TOKEN not honored"

# 2. resolver validates CLAUDE_CODE_SESSION_ID against a real transcript.
mkdir -p "$HOME/.claude/projects/p"; touch "$HOME/.claude/projects/p/abc123.jsonl"
rm -f "$HOME/.claude/.skill-session-token"
CLAUDE_CODE_SESSION_ID="abc123" _run set-intent "C :: out-of-scope: D" >/dev/null 2>&1
assert_file_exists "resolver token: intent under session-abc123" "$HOME/.claude/.skill-confirmed-intent-session-abc123"

# 3. Bad root -> lib not found -> exit 1, no write.
CLAUDE_PLUGIN_ROOT="/no-such-root-xyz" bash "${SCRIPT}" set-intent "E :: out-of-scope: F" >/dev/null 2>&1
assert_equals "bad root: exits 1 (lib not found)" "1" "$?"

# 3b. Double degrade: resolver returns empty (synthetic HOME, no matching
#     transcript) AND no singleton file -> empty token -> helpers no-op. MUST
#     NOT write a literal "default" file (that was the verify-and-record.sh
#     posture; openspec-state has no "default" reader, so it would be a dead,
#     collidable write).
rm -f "$HOME/.claude/.skill-session-token"
env -u CLAUDE_CODE_SESSION_ID _run set-intent "G :: out-of-scope: H" >/dev/null 2>&1
[ -f "$HOME/.claude/.skill-confirmed-intent-default" ] && _record_fail "no literal-default write on double degrade" "wrote .skill-confirmed-intent-default" || _record_pass "double degrade: no literal-default write"

# --- each op writes the expected state --------------------------------------
T="session-ops"
_force_token "$T"
_run set-intent "cache layer :: out-of-scope: eviction" >/dev/null 2>&1
assert_equals "set-intent content" "cache layer :: out-of-scope: eviction" \
    "$(cat "$HOME/.claude/.skill-confirmed-intent-${T}" 2>/dev/null)"

_run upsert-change "feat-x" "" "" "caching" "" >/dev/null 2>&1
assert_contains "upsert-change records slug"       'feat-x'  "$(_state "$T")"
assert_contains "upsert-change records capability" 'caching' "$(_state "$T")"

_run set-discovery-path "feat-x" "docs/plans/x-discovery.md" >/dev/null 2>&1
assert_contains "set-discovery-path records path" 'x-discovery.md' "$(_state "$T")"

_run set-hypotheses "feat-x" '["h1","h2"]' >/dev/null 2>&1
assert_contains "set-hypotheses records array" 'h1' "$(_state "$T")"

# --- error handling ----------------------------------------------------------
_run bogus-op >/dev/null 2>&1; assert_equals "unknown op exits 2" "2" "$?"
_run >/dev/null 2>&1;         assert_equals "missing op exits 2"  "2" "$?"

# --- call-site assertion: the incantation is GONE, the script is CALLED -------
# Structural replacement for the old 7-copy symmetry test. The injected/config
# surfaces and product-discovery now call persist-state.sh with NO retyped
# incantation. agent-team-review resolves via record-review-verdict.sh (which
# self-resolves the token), so its incantation is simply gone. openspec-ship is
# a DEFERRED follow-up (it also reads state and marks-archived — a larger flow
# rewrite); it is deliberately excluded here, see the proposal.
INCANT='resolve_own_session_token || cat'
_persist_surfaces="config/default-triggers.json config/fallback-registry.json hooks/skill-activation-hook.sh hooks/session-start-hook.sh skills/product-discovery/SKILL.md"
for _s in ${_persist_surfaces}; do
    _c="$(cat "${PROJECT_ROOT}/${_s}" 2>/dev/null)"
    assert_not_contains "${_s}: incantation removed" "${INCANT}" "${_c}"
    assert_contains     "${_s}: calls persist-state.sh" "persist-state.sh" "${_c}"
done
# agent-team-review: incantation gone, delegates token resolution to the script.
_atr="$(cat "${PROJECT_ROOT}/skills/agent-team-review/SKILL.md" 2>/dev/null)"
assert_not_contains "agent-team-review: incantation removed" "${INCANT}" "${_atr}"
assert_contains     "agent-team-review: calls record-review-verdict.sh" "record-review-verdict.sh" "${_atr}"

export HOME="$_OLDHOME"
print_summary
exit $?

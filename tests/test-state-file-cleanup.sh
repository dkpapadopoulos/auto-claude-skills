#!/usr/bin/env bash
# test-state-file-cleanup.sh — session-start-hook prunes STALE per-session state
# files (composition + openspec) so they don't accumulate unbounded, while never
# deleting the current session's state or recently-active state.
#
# Context: the hook prunes `.skill-prompt-count-*` and `.skill-zero-match-count`
# at session start but never pruned `.skill-composition-state-*` /
# `.skill-openspec-state-*`, so they accumulated (hundreds observed in the wild).
# Fix: age-based prune (older than SKILL_STATE_RETENTION seconds, default 7 days),
# with an explicit skip for the current session token.
#
# Bash 3.2 compatible. Sources test-helpers.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-state-file-cleanup.sh ==="

run_hook() {
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" </dev/null >/dev/null 2>&1 || true
}
backdate() {
    # Backdate $1's mtime well outside any retention window (BSD then GNU touch).
    touch -t 200001010000 "$1" 2>/dev/null || touch -d "2000-01-01 00:00:00" "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# C1/C2 — stale composition + openspec state files ARE pruned
# ---------------------------------------------------------------------------
echo "--- C1/C2: stale state files are pruned ---"
setup_test_env
mkdir -p "${HOME}/.claude"
STALE_COMP="${HOME}/.claude/.skill-composition-state-session-deadbeef-old"
STALE_OPSX="${HOME}/.claude/.skill-openspec-state-session-deadbeef-old"
printf '{}' > "${STALE_COMP}"
printf '{}' > "${STALE_OPSX}"
backdate "${STALE_COMP}"
backdate "${STALE_OPSX}"
run_hook
if [ -f "${STALE_COMP}" ]; then
    _record_fail "C1: stale composition-state pruned" "still present"
else
    _record_pass "C1: stale composition-state pruned"
fi
if [ -f "${STALE_OPSX}" ]; then
    _record_fail "C2: stale openspec-state pruned" "still present"
else
    _record_pass "C2: stale openspec-state pruned"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# C3 — recently-active state file is PRESERVED (not over-eager)
# ---------------------------------------------------------------------------
echo "--- C3: recent state file is preserved ---"
setup_test_env
mkdir -p "${HOME}/.claude"
FRESH_COMP="${HOME}/.claude/.skill-composition-state-session-fresh-recent"
printf '{}' > "${FRESH_COMP}"   # mtime = now
run_hook
if [ -f "${FRESH_COMP}" ]; then
    _record_pass "C3: recent state file preserved"
else
    _record_fail "C3: recent state file preserved" "was deleted"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# C4 — the CURRENT session's state is never pruned, even if its mtime is stale
# ---------------------------------------------------------------------------
echo "--- C4: current session's state is never pruned ---"
setup_test_env
mkdir -p "${HOME}/.claude"
run_hook   # establishes the current token (fallback path; written to token file)
TOK="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
assert_not_empty "C4: token established" "${TOK}"
CUR_COMP="${HOME}/.claude/.skill-composition-state-${TOK}"
printf '{}' > "${CUR_COMP}"
backdate "${CUR_COMP}"        # stale mtime, but it's the ACTIVE token
run_hook                      # reuse window keeps the same token; must NOT delete it
if [ -f "${CUR_COMP}" ]; then
    _record_pass "C4: current-session state preserved despite stale mtime"
else
    _record_fail "C4: current-session state preserved despite stale mtime" "deleted"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# C5 — invocation-evidence SHA sidecar (issue #133): stale dead-token sidecars
# are pruned with the family; the CURRENT session's sidecar is preserved.
# ---------------------------------------------------------------------------
echo "--- C5: invocation-evidence-sha sidecar GC ---"
setup_test_env
mkdir -p "${HOME}/.claude"
STALE_SIDE="${HOME}/.claude/.skill-invocation-evidence-sha-session-deadbeef-old"
printf 'requesting-code-review 0000\n' > "${STALE_SIDE}"
backdate "${STALE_SIDE}"
run_hook
TOK="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
if [ -f "${STALE_SIDE}" ]; then
    _record_fail "C5a: stale dead-token sidecar pruned" "still present"
else
    _record_pass "C5a: stale dead-token sidecar pruned"
fi
CUR_SIDE="${HOME}/.claude/.skill-invocation-evidence-sha-${TOK}"
printf 'requesting-code-review 0000\n' > "${CUR_SIDE}"
backdate "${CUR_SIDE}"        # stale mtime, but it's the ACTIVE token
run_hook
if [ -f "${CUR_SIDE}" ]; then
    _record_pass "C5b: current-session sidecar preserved despite stale mtime"
else
    _record_fail "C5b: current-session sidecar preserved despite stale mtime" "deleted"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# C6 — reviewer-dispatch pairing file (openspec/changes/reviewer-completion-
# evidence/): stale dead-token pairings are pruned with the family; the CURRENT
# session's pairing is preserved. A pairing GC'd mid-session would silently
# demote every later general-purpose reviewer completion to "not a reviewer".
# ---------------------------------------------------------------------------
echo "--- C6: reviewer-dispatch pairing GC ---"
setup_test_env
mkdir -p "${HOME}/.claude"
STALE_PAIR="${HOME}/.claude/.skill-reviewer-dispatch-session-deadbeef-old"
STALE_DONE="${HOME}/.claude/.skill-reviewer-complete-session-deadbeef-old"
printf 'a1b2c3 deadkey\n' > "${STALE_PAIR}"
printf 'a1b2c3\n' > "${STALE_DONE}"
backdate "${STALE_PAIR}"; backdate "${STALE_DONE}"
run_hook
TOK="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
if [ -f "${STALE_PAIR}" ] || [ -f "${STALE_DONE}" ]; then
    _record_fail "C6a: stale dead-token pairing halves pruned" "still present"
else
    _record_pass "C6a: stale dead-token pairing halves pruned"
fi
# Both halves must survive: pruning EITHER one mid-session silently breaks
# every later join, and the join needs both sides present.
CUR_PAIR="${HOME}/.claude/.skill-reviewer-dispatch-${TOK}"
CUR_DONE="${HOME}/.claude/.skill-reviewer-complete-${TOK}"
printf 'a1b2c3 curkey\n' > "${CUR_PAIR}"
printf 'a1b2c3\n' > "${CUR_DONE}"
backdate "${CUR_PAIR}"; backdate "${CUR_DONE}"   # stale mtime, but it's the ACTIVE token
run_hook
if [ -f "${CUR_PAIR}" ] && [ -f "${CUR_DONE}" ]; then
    _record_pass "C6b: current-session pairing halves preserved despite stale mtime"
else
    _record_fail "C6b: current-session pairing halves preserved despite stale mtime" "deleted"
fi
teardown_test_env

print_summary

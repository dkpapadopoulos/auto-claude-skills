#!/usr/bin/env bash
# test-session-token-reuse.sh — Regression test for the session-start hook's
# token-reuse logic.
#
# Root cause: when ScheduleWakeup (or any harness-side re-invocation) fires
# SessionStart without a `session_id` field in stdin (or with a TTY stdin),
# the hook used to fall through to `<epoch>-<pid>-<rand>` and rotate the token
# unconditionally. That orphaned every composition-state file keyed off the
# token and broke the openspec-guard push gate's REVIEW/VERIFY/SHIP checks.
#
# Fix: in the fallback path, if `~/.claude/.skill-session-token` exists and was
# modified recently (within REUSE_WINDOW_SECONDS, default 14400 = 4 hours),
# reuse it instead of generating a new one. Long-stale tokens still rotate to
# preserve the original collision-defense guarantees.
#
# Bash 3.2 compatible. Sources test-helpers.sh.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-session-token-reuse.sh ==="

run_hook() {
    # Invoke with empty stdin (no session_id) to exercise the fallback path.
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" </dev/null 2>/dev/null >/dev/null || true
}

read_token() {
    cat "${HOME}/.claude/.skill-session-token" 2>/dev/null
}

# ---------------------------------------------------------------------------
# T1 — Recent existing token is reused (the rotation-bug fix)
# ---------------------------------------------------------------------------
echo "--- T1: recent existing token is reused on fallback re-fire ---"
setup_test_env
mkdir -p "${HOME}/.claude"
# Seed a token with the canonical fallback format and a "young" mtime (now).
SEEDED="1700000000-99999-1234567890"
printf '%s' "${SEEDED}" > "${HOME}/.claude/.skill-session-token"
run_hook
T1_AFTER="$(read_token)"
assert_equals "T1: recent token is reused, not rotated" "${SEEDED}" "${T1_AFTER}"
teardown_test_env

# ---------------------------------------------------------------------------
# T2 — Stale token (older than reuse window) IS rotated
# ---------------------------------------------------------------------------
echo "--- T2: stale token is rotated, preserving collision defense ---"
setup_test_env
mkdir -p "${HOME}/.claude"
SEEDED="1500000000-11111-0987654321"
printf '%s' "${SEEDED}" > "${HOME}/.claude/.skill-session-token"
# Backdate the mtime well outside any reasonable reuse window.
touch -t 200001010000 "${HOME}/.claude/.skill-session-token" 2>/dev/null \
    || touch -d "2000-01-01 00:00:00" "${HOME}/.claude/.skill-session-token" 2>/dev/null \
    || true
run_hook
T2_AFTER="$(read_token)"
case "${T2_AFTER}" in
    "${SEEDED}")
        _record_fail "T2: stale token was NOT rotated" "still = '${SEEDED}'"
        ;;
    "")
        _record_fail "T2: token file is empty after rotation"
        ;;
    *)
        _record_pass "T2: stale token rotated to a fresh value"
        ;;
esac
teardown_test_env

# ---------------------------------------------------------------------------
# T3 — Absent token file leads to fresh generation (cold start)
# ---------------------------------------------------------------------------
echo "--- T3: absent token file generates fresh token ---"
setup_test_env
# No .skill-session-token file present.
run_hook
T3_AFTER="$(read_token)"
assert_not_empty "T3: cold-start generates a token" "${T3_AFTER}"
teardown_test_env

print_summary

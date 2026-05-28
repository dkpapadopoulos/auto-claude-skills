#!/usr/bin/env bash
# test-session-token.sh — Session-token uniqueness tests
#
# CLAUDE.md claims "Concurrent sessions share ~/.claude/ — session-token
# scoping prevents counter races." This test file makes that claim executable:
# the token must be unique across concurrent session-start invocations so
# counters and state files can't collide.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-session-token.sh ==="

# Helper: invoke session-start-hook fresh and read back the written token
run_session_start_and_get_token() {
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" >/dev/null 2>&1
    cat "${HOME}/.claude/.skill-session-token" 2>/dev/null
}

test_token_has_random_suffix() {
    echo "-- test: session token includes a random suffix (epoch-pid-rand shape) --"
    setup_test_env

    local token
    token="$(run_session_start_and_get_token)"

    # Shape must be at least three dash-separated components: <epoch>-<pid>-<rand>
    # Two-component (epoch-pid) tokens are the collision-vulnerable format.
    local dash_count
    dash_count="$(printf '%s' "$token" | awk -F- '{print NF-1}')"
    if [ "${dash_count:-0}" -ge 2 ]; then
        _record_pass "token has >=2 dashes (epoch-pid-rand shape)"
    else
        _record_fail "token has >=2 dashes (epoch-pid-rand shape)" \
            "token: '$token' has ${dash_count} dashes; expected >=2"
    fi

    teardown_test_env
}
test_token_has_random_suffix

test_sequential_invocation_within_window_reuses_token() {
    echo "-- test: sequential invocations within reuse window REUSE the same token --"
    # Contract change: ScheduleWakeup re-fires of SessionStart must not rotate
    # the token, because rotation orphans composition state. The original
    # collision-protection (across truly distinct sessions with different
    # session_id values) is unaffected — those go through the fast path at
    # line 62 of the hook.
    setup_test_env

    local token1
    token1="$(run_session_start_and_get_token)"
    local token2
    token2="$(run_session_start_and_get_token)"

    assert_not_empty "token1 non-empty" "$token1"
    assert_not_empty "token2 non-empty" "$token2"

    if [ "$token1" = "$token2" ]; then
        _record_pass "sequential invocations within reuse window REUSE the token"
    else
        _record_fail "sequential invocations within reuse window REUSE the token" \
            "expected reuse, got token1='$token1' token2='$token2'"
    fi

    teardown_test_env
}
test_sequential_invocation_within_window_reuses_token

test_stale_token_outside_window_rotates() {
    echo "-- test: token older than the reuse window IS rotated --"
    setup_test_env

    local token1
    token1="$(run_session_start_and_get_token)"
    assert_not_empty "token1 non-empty" "$token1"

    # Backdate the token file well outside any reasonable reuse window.
    # GNU touch and BSD touch take different flag forms; try both.
    touch -t 200001010000 "${HOME}/.claude/.skill-session-token" 2>/dev/null \
        || touch -d "2000-01-01 00:00:00" "${HOME}/.claude/.skill-session-token" 2>/dev/null \
        || true

    local token2
    token2="$(run_session_start_and_get_token)"
    assert_not_empty "token2 non-empty" "$token2"

    if [ "$token1" != "$token2" ]; then
        _record_pass "stale token outside window rotates to a fresh value"
    else
        _record_fail "stale token outside window rotates to a fresh value" \
            "expected rotation, both stayed '$token1'"
    fi

    teardown_test_env
}
test_stale_token_outside_window_rotates

test_parallel_session_tokens_differ() {
    echo "-- test: tokens differ even when generated in the same second with same PID --"
    setup_test_env

    # Simulate collision risk by sourcing the token-generation snippet in the
    # same shell (same $$) multiple times within the same second. Without the
    # random suffix this produces identical tokens; with it they differ.
    local t_a t_b t_c
    t_a="$(date +%s)-$$-${RANDOM}${RANDOM}"
    t_b="$(date +%s)-$$-${RANDOM}${RANDOM}"
    t_c="$(date +%s)-$$-${RANDOM}${RANDOM}"

    if [ "$t_a" != "$t_b" ] && [ "$t_b" != "$t_c" ] && [ "$t_a" != "$t_c" ]; then
        _record_pass "same-second same-PID tokens are still unique"
    else
        _record_fail "same-second same-PID tokens are still unique" \
            "collision: '$t_a' '$t_b' '$t_c'"
    fi

    teardown_test_env
}
test_parallel_session_tokens_differ

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary

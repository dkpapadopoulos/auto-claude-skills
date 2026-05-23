#!/usr/bin/env bash
# test-serena-autoregister.sh — Tests for hooks/lib/serena-autoregister.sh
# Bash 3.2 compatible. Uses mocked `serena` and `claude` binaries on PATH.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

LIB="${PROJECT_ROOT}/hooks/lib/serena-autoregister.sh"

# ---------------------------------------------------------------------------
# Mock helpers: create fake `serena` and `claude` binaries on a temp PATH.
# Each mock records its invocations to ${MOCK_LOG} so tests can assert calls.
# ---------------------------------------------------------------------------
_setup_mocks() {
    MOCK_BIN="${TEST_TMPDIR}/bin"
    MOCK_LOG="${TEST_TMPDIR}/mock-calls.log"
    mkdir -p "${MOCK_BIN}"
    : >"${MOCK_LOG}"

    cat >"${MOCK_BIN}/serena" <<'EOF'
#!/usr/bin/env bash
echo "serena $*" >>"${MOCK_LOG}"
exit 0
EOF
    chmod +x "${MOCK_BIN}/serena"

    cat >"${MOCK_BIN}/claude" <<'EOF'
#!/usr/bin/env bash
echo "claude $*" >>"${MOCK_LOG}"
if [ "$1" = "mcp" ] && [ "$2" = "list" ]; then
    if [ "${MOCK_CLAUDE_LIST_HAS_SERENA:-0}" = "1" ]; then
        echo "serena: serena start-mcp-server --context claude-code"
    fi
    echo "other-server: foo"
    exit 0
fi
if [ "$1" = "mcp" ] && [ "$2" = "add" ]; then
    if [ "${MOCK_CLAUDE_ADD_FAILS:-0}" = "1" ]; then
        echo "Error: failed to add" >&2
        exit 1
    fi
    exit 0
fi
exit 0
EOF
    chmod +x "${MOCK_BIN}/claude"

    export MOCK_LOG
    export PATH="${MOCK_BIN}:${PATH}"
}

_teardown_mocks() {
    unset MOCK_CLAUDE_LIST_HAS_SERENA MOCK_CLAUDE_ADD_FAILS
}

_marker_path() {
    printf '%s/.claude/.auto-claude-skills-serena-registered' "${HOME}"
}

_error_path() {
    printf '%s/.claude/.auto-claude-skills-serena-register-error' "${HOME}"
}

test_eligible_and_not_registered_runs_mcp_add_and_writes_marker() {
    echo "-- test: eligible + not registered → mcp add + marker written --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"

    . "${LIB}"
    serena_maybe_autoregister

    assert_file_exists "marker file written" "$(_marker_path)"
    if grep -qF 'claude mcp add --scope user serena' "${MOCK_LOG}"; then
        echo "  PASS: claude mcp add invoked with --scope user"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "  FAIL: expected 'claude mcp add --scope user serena' in mock log"
        echo "  log: $(cat "${MOCK_LOG}")"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    _teardown_mocks
    teardown_test_env
}

test_already_registered_skips_add_but_writes_marker() {
    echo "-- test: already registered → skip add, still write marker --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"
    export MOCK_CLAUDE_LIST_HAS_SERENA=1

    . "${LIB}"
    serena_maybe_autoregister

    assert_file_exists "marker file written" "$(_marker_path)"
    if grep -qF 'claude mcp add' "${MOCK_LOG}"; then
        echo "  FAIL: should NOT have invoked 'claude mcp add' (already registered)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "  PASS: 'claude mcp add' skipped because serena already in mcp list"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    _teardown_mocks
    teardown_test_env
}

test_marker_exists_is_noop() {
    echo "-- test: marker file already exists → fully no-op --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"
    : >"$(_marker_path)"

    . "${LIB}"
    serena_maybe_autoregister

    if [ -s "${MOCK_LOG}" ]; then
        echo "  FAIL: expected mock log to be empty when marker exists"
        echo "  log: $(cat "${MOCK_LOG}")"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "  PASS: no mock binaries invoked when marker present"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    _teardown_mocks
    teardown_test_env
}

test_no_serena_on_path_is_noop() {
    echo "-- test: serena not on PATH → no-op, no marker --"
    setup_test_env
    export PATH="/usr/bin:/bin"
    mkdir -p "${HOME}/.claude"

    . "${LIB}"
    serena_maybe_autoregister

    if [ -e "$(_marker_path)" ]; then
        echo "  FAIL: marker should NOT be written when serena absent"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "  PASS: no marker written when serena absent"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    teardown_test_env
}

test_no_claude_cli_is_noop() {
    echo "-- test: claude CLI missing → no-op, no marker --"
    setup_test_env
    MOCK_BIN="${TEST_TMPDIR}/bin"
    MOCK_LOG="${TEST_TMPDIR}/mock-calls.log"
    mkdir -p "${MOCK_BIN}"
    : >"${MOCK_LOG}"
    cat >"${MOCK_BIN}/serena" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "${MOCK_BIN}/serena"
    export PATH="${MOCK_BIN}:/usr/bin:/bin"
    export MOCK_LOG
    mkdir -p "${HOME}/.claude"

    . "${LIB}"
    serena_maybe_autoregister

    if [ -e "$(_marker_path)" ]; then
        echo "  FAIL: marker should NOT be written when claude CLI absent"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    else
        echo "  PASS: no marker written when claude CLI absent"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi

    teardown_test_env
}

test_mcp_add_failure_writes_marker_and_error_breadcrumb() {
    echo "-- test: mcp add fails → marker still written + error breadcrumb --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"
    export MOCK_CLAUDE_ADD_FAILS=1

    . "${LIB}"
    serena_maybe_autoregister

    assert_file_exists "marker written even on failure" "$(_marker_path)"
    assert_file_exists "error breadcrumb written" "$(_error_path)"

    _teardown_mocks
    teardown_test_env
}

test_function_exit_code_is_always_zero() {
    echo "-- test: function never propagates non-zero exit (fail-open) --"
    setup_test_env
    _setup_mocks
    mkdir -p "${HOME}/.claude"
    export MOCK_CLAUDE_ADD_FAILS=1

    . "${LIB}"
    set +e
    serena_maybe_autoregister
    local rc=$?
    set -e
    assert_equals "exit code is 0 on add failure" "0" "${rc}"

    _teardown_mocks
    teardown_test_env
}

echo "=== test-serena-autoregister.sh ==="
test_eligible_and_not_registered_runs_mcp_add_and_writes_marker
test_already_registered_skips_add_but_writes_marker
test_marker_exists_is_noop
test_no_serena_on_path_is_noop
test_no_claude_cli_is_noop
test_mcp_add_failure_writes_marker_and_error_breadcrumb
test_function_exit_code_is_always_zero

print_summary
exit $((TESTS_FAILED == 0 ? 0 : 1))

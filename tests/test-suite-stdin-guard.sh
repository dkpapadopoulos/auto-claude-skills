#!/usr/bin/env bash
# test-suite-stdin-guard.sh — Regression test for #142.
#
# The suite hangs indefinitely when its stdin is a live socket/FIFO instead of
# /dev/null. Root cause chain (traced 2026-07-31):
#   1. hooks/session-start-hook.sh reads its payload with `$(cat)` guarded only
#      by `[ ! -t 0 ]`. A TTY check is not an "input available" check: a socket
#      or FIFO is not a TTY, so `cat` runs and blocks forever waiting for an EOF
#      that never arrives.
#   2. Several tests (e.g. tests/test-context.sh:671) invoke that hook with no
#      stdin redirect, so it inherits the suite's fd 0.
#   3. tests/run-tests.sh had no stdin guard, so fd 0 was whatever the caller
#      had — a unix socket in agent sessions. One observed run sat idle ~2h at
#      near-zero CPU.
#
# The fix is a single `exec < /dev/null` in run-tests.sh, which covers every
# discovered test file at once. This test proves that guard is present AND
# effective, using the real run-tests.sh (copied verbatim) driven against a
# synthetic stdin-blocking test file over a never-EOF FIFO.
#
# Bash 3.2 compatible (macOS default). No `timeout(1)` on macOS — the watchdog
# is implemented inline.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER="${SCRIPT_DIR}/run-tests.sh"

# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-suite-stdin-guard.sh ==="
echo ""

WORK="$(mktemp -d "${TMPDIR:-/tmp}/acs-stdin-guard.XXXXXXXX")"
cleanup() {
    # Kill anything still holding the FIFOs before removing the tree, so a
    # watchdog-killed run cannot leave an orphaned `cat` behind.
    pkill -9 -f "${WORK}" 2>/dev/null
    rm -rf "${WORK}" 2>/dev/null
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Fixture: a miniature suite directory containing a copy of the REAL runner and
# one synthetic test that consumes stdin to EOF (what session-start-hook does).
# ---------------------------------------------------------------------------
# build_fixture <dir> <strip_guard: yes|no>
build_fixture() {
    local dir="$1"
    local strip="$2"

    mkdir -p "${dir}" || return 1

    if [ "${strip}" = "yes" ]; then
        # Red control: the same runner with the #142 guard removed. This proves
        # the harness can actually observe the hang — without it, a test that
        # silently stopped reproducing would still report PASS.
        grep -v '^exec < /dev/null' "${RUNNER}" > "${dir}/run-tests.sh" || return 1
    else
        cp "${RUNNER}" "${dir}/run-tests.sh" || return 1
    fi

    # The synthetic blocker. `cat` here stands in for session-start-hook.sh's
    # `_HOOK_STDIN="$(cat)"`: harmless on /dev/null, fatal on a live FIFO.
    cat > "${dir}/test-stdin-blocker.sh" <<'BLOCKER'
#!/usr/bin/env bash
cat > /dev/null
echo "blocker finished"
exit 0
BLOCKER

    return 0
}

# run_with_fifo_stdin <dir> <watchdog_secs>
# Runs <dir>/run-tests.sh with a never-EOF FIFO on fd 0.
# Echoes "terminated" if the runner exited on its own, "hung" if the watchdog
# had to kill it.
run_with_fifo_stdin() {
    local dir="$1"
    local budget="$2"
    local fifo="${dir}/stdin.fifo"
    local log="${dir}/run.log"
    local holder suite elapsed

    rm -f "${fifo}"
    mkfifo "${fifo}" 2>/dev/null || { echo "fifo-error"; return 0; }

    # Hold the write end open without ever writing: readers block and never see
    # EOF. This is the FIFO analogue of the unix-socket stdin seen in the wild.
    # The bounded sleep is a safety net so an orphan self-reaps.
    sleep 600 > "${fifo}" &
    holder=$!

    bash "${dir}/run-tests.sh" < "${fifo}" > "${log}" 2>&1 &
    suite=$!

    elapsed=0
    while kill -0 "${suite}" 2>/dev/null; do
        if [ "${elapsed}" -ge "${budget}" ]; then
            pkill -P "${suite}" 2>/dev/null
            kill -9 "${suite}" 2>/dev/null
            kill -9 "${holder}" 2>/dev/null
            wait "${suite}" 2>/dev/null
            echo "hung"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    kill -9 "${holder}" 2>/dev/null
    wait "${holder}" 2>/dev/null
    echo "terminated"
    return 0
}

# The fixture suite is a single trivial test — it completes in well under a
# second when stdin is not blocking, so this is a very wide margin.
WATCHDOG_SECS=10

# ---------------------------------------------------------------------------
# 1. The real runner terminates under a never-EOF FIFO stdin.
#    This is the assertion that goes red if the guard is removed.
# ---------------------------------------------------------------------------
GUARDED="${WORK}/guarded"
if build_fixture "${GUARDED}" "no"; then
    result="$(run_with_fifo_stdin "${GUARDED}" "${WATCHDOG_SECS}")"
    assert_equals "run-tests.sh terminates when stdin is a never-EOF FIFO (#142)" \
        "terminated" "${result}"

    # The guard must neutralise stdin, not skip the test: prove the fixture test
    # actually ran to completion rather than the runner bailing out early.
    assert_contains "the stdin-consuming test still runs to completion" \
        "blocker finished" "$(cat "${GUARDED}/run.log" 2>/dev/null)"
    assert_contains "runner reports the fixture test passed" \
        "All test files passed." "$(cat "${GUARDED}/run.log" 2>/dev/null)"
else
    _record_fail "guarded fixture builds" "could not build ${GUARDED}"
fi

# ---------------------------------------------------------------------------
# 2. Red control (mutation proof): with the guard stripped, the SAME harness
#    must observe the hang. If this ever reports "terminated", assertion 1 has
#    become vacuous and is no longer gating anything.
# ---------------------------------------------------------------------------
STRIPPED="${WORK}/stripped"
if build_fixture "${STRIPPED}" "yes"; then
    # Guard against the strip silently no-opping (e.g. after a reformat) — that
    # would make the control pass for the wrong reason.
    if grep -q '^exec < /dev/null' "${STRIPPED}/run-tests.sh" 2>/dev/null; then
        _record_fail "red control actually removes the guard" \
            "guard line still present in stripped copy — control is vacuous"
    else
        _record_pass "red control actually removes the guard"
    fi

    result="$(run_with_fifo_stdin "${STRIPPED}" "${WATCHDOG_SECS}")"
    assert_equals "without the guard the same runner hangs (harness detects the bug)" \
        "hung" "${result}"
else
    _record_fail "stripped fixture builds" "could not build ${STRIPPED}"
fi

# ---------------------------------------------------------------------------
# 3. The guard must sit above the test-execution loop — a redirect placed after
#    the loop would satisfy a naive grep but fix nothing.
# ---------------------------------------------------------------------------
guard_line="$(grep -n '^exec < /dev/null' "${RUNNER}" 2>/dev/null | head -1 | cut -d: -f1)"
loop_line="$(grep -n '^for test_file in' "${RUNNER}" 2>/dev/null | head -1 | cut -d: -f1)"
if [ -n "${guard_line}" ] && [ -n "${loop_line}" ] && [ "${guard_line}" -lt "${loop_line}" ]; then
    _record_pass "stdin guard precedes the test-execution loop"
else
    _record_fail "stdin guard precedes the test-execution loop" \
        "guard at line '${guard_line:-none}', loop at line '${loop_line:-none}'"
fi

print_summary

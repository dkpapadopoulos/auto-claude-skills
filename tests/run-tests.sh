#!/usr/bin/env bash
# run-tests.sh — Discovers and runs all test-*.sh files in the tests/ directory.
# Bash 3.2 compatible (macOS default). CI-ready: exits 1 on any failure.

set -u

# Self-guard stdin (#142). No test in this suite reads the runner's stdin, but
# several invoke hooks that do — hooks/session-start-hook.sh reads its payload
# with `$(cat)` behind a `[ ! -t 0 ]` check, and a TTY check is not an "input
# available" check. When the caller's fd 0 is a socket or FIFO (routine in agent
# sessions) that `cat` blocks forever waiting for an EOF that never arrives, and
# the suite parks mid-run at near-zero CPU with no error — one observed run sat
# idle roughly two hours. Relying on callers to pass `< /dev/null` failed: a
# fresh session or CI path that forgets it re-hangs. Redirecting here is
# inherited by every discovered test file at once.
# Regression: tests/test-suite-stdin-guard.sh
exec < /dev/null

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Completion sentinel (#263). The summary block below is shape-identical to the
# one tests/test-helpers.sh::print_summary emits at the end of EVERY individual
# test file — same frame, same four-space padding, one word apart. So a reader
# that lands on a per-file block, tailing a running log or reading one that was
# reaped partway, cannot tell it from this runner's own terminal block.
#
# That made suite completion assertable only by ABSENCE, and nothing asserted
# it: on a real reaped run (2026-08-27) 91 of 122 files had executed, with
# thousands of PASS assertions and not one `FAIL:` line. Every signal a normal
# check inspects said green.
#
# This line is the one thing a per-file block cannot produce. Consumers must
# gate a pass claim on its PRESENCE, never on the absence of `FAIL:` lines —
# see scripts/assert-suite-complete.sh, which is the supported reader.
# Regression: tests/test-suite-completion.sh
emit_completion_sentinel() {
    printf 'ACS-RUN-TESTS-COMPLETE files=%d passed=%d failed=%d status=%s\n' \
        "${TOTAL_FILES}" "${PASSED_FILES}" "${FAILED_FILES}" "$1"
}

TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
FAILED_NAMES=""

# Discover test files (excluding test-helpers.sh itself)
test_files=""
for f in "${SCRIPT_DIR}"/test-*.sh; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
        test-helpers.sh) continue ;;
    esac
    test_files="${test_files} ${f}"
done

if [ -z "${test_files}" ]; then
    echo "No test files found in ${SCRIPT_DIR}/test-*.sh"
    emit_completion_sentinel none
    exit 0
fi

echo "============================================"
echo "  auto-claude-skills test runner"
echo "============================================"
echo ""

for test_file in ${test_files}; do
    name="$(basename "${test_file}")"
    echo "--- Running: ${name} ---"
    TOTAL_FILES=$((TOTAL_FILES + 1))

    if bash "${test_file}"; then
        PASSED_FILES=$((PASSED_FILES + 1))
    else
        FAILED_FILES=$((FAILED_FILES + 1))
        if [ -n "${FAILED_NAMES}" ]; then
            FAILED_NAMES="${FAILED_NAMES}, ${name}"
        else
            FAILED_NAMES="${name}"
        fi
    fi
    echo ""
done

echo "============================================"
printf "  Files run:    %d\n" "${TOTAL_FILES}"
printf "  Files passed: %d\n" "${PASSED_FILES}"
printf "  Files failed: %d\n" "${FAILED_FILES}"
echo "============================================"

if [ "${FAILED_FILES}" -gt 0 ]; then
    echo ""
    echo "Failed: ${FAILED_NAMES}"
    emit_completion_sentinel fail
    exit 1
fi

echo "All test files passed."
emit_completion_sentinel pass
exit 0

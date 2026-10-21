#!/usr/bin/env bash
# tests/test-hook-stdin-bounded-cleanup.sh — #369 follow-up
#
# tests/test-hook-stdin-bounded.sh made its stub and FIFO dirs under a
# hard-coded /tmp and removed them only on its last line. A run that was killed
# partway (a watchdog, a ^C, a reaped background job) therefore left them
# behind, and no caller could contain them by setting TMPDIR, which is how
# tests/test-suite-stdin-guard.sh keeps a killed runner's leftovers inside its
# own work dir.
#
# This cell runs that file with a private TMPDIR, kills it once its stub dir
# exists, and requires the dir to have been made THERE and to be gone after.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

W="$(mktemp -d "${TMPDIR:-/tmp}/acs-stdin-cleanup.XXXXXX")"
trap 'rm -rf "${W}"' EXIT

test_killed_run_leaves_nothing_in_tmpdir() {
    local pid i=0 made
    mkdir -p "${W}/tmp"
    TMPDIR="${W}/tmp" bash "${SCRIPT_DIR}/test-hook-stdin-bounded.sh" < /dev/null > "${W}/log" 2>&1 &
    pid=$!
    # The stub dir is the file's first act; the control cell after it runs 8 s.
    while [ "${i}" -lt 50 ]; do
        made="$(find "${W}/tmp" -mindepth 2 -maxdepth 2 -name fast 2>/dev/null)"
        [ -n "${made}" ] && break
        sleep 0.1; i=$(( i + 1 ))
    done
    sleep 1
    kill -TERM "${pid}" 2>/dev/null
    wait "${pid}" 2>/dev/null
    if [ -z "${made}" ]; then
        _record_fail "the stub dir is made under the caller's TMPDIR" \
            "none appeared in ${W}/tmp within 5 s (a hard-coded /tmp, or the file never started)"
        return
    fi
    _record_pass "the stub dir is made under the caller's TMPDIR"
    assert_equals "a killed run leaves nothing in its TMPDIR" "" "$(ls -A "${W}/tmp")"
}

test_killed_run_leaves_nothing_in_tmpdir

assert_test_functions_wired "${BASH_SOURCE[0]}"
print_summary

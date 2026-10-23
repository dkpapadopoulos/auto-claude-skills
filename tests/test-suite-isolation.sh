#!/usr/bin/env bash
# test-suite-isolation.sh — the suite must not reach outside the HOME and
# TMPDIR it gives itself (#372).
#
# Measured 2026-10-23 on one full green run: session-start ran against the real
# HOME (tests/test-mcp-connection-probe.sh twice, tests/test-security-scanner.sh
# once), rewriting the real ~/.claude/.skill-registry-cache.json from the
# checkout; the installed `claude` CLI ran 119 times from 16 files; and six
# acs-test.* dirs were left in TMPDIR. On 2026-10-22, 781 of those had
# accumulated since 2026-10-08. Every run was green.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-suite-isolation.sh ==="

W="$(mktemp -d "${TMPDIR:-/tmp}/acs-isolation.XXXXXX")"
trap 'rm -rf "${W}"' EXIT

test_files_leave_the_starting_home_untouched() {
    # Each file is started with a stand-in for the user's HOME, run on its own
    # (the runner's private HOME does not cover that); a stub `claude` that
    # prints nothing keeps the probe's end-to-end cell on the announced skip.
    # These two are the ones measured writing there, by hand and in review.
    local f h b="${W}/probe-bin" rc left
    mkdir -p "${b}"
    printf '#!/bin/sh\nexit 0\n' > "${b}/claude"
    chmod +x "${b}/claude"
    for f in test-mcp-connection-probe.sh test-security-scanner.sh; do
        h="${W}/home-${f%.sh}"; mkdir -p "${h}"
        HOME="${h}" PATH="${b}:${PATH}" bash "${SCRIPT_DIR}/${f}" < /dev/null > "${W}/${f}.home.log" 2>&1
        rc=$?
        assert_equals "${f} passes under a stand-in HOME" "0" "${rc}"
        left="$(cd "${h}" && find . -mindepth 1 2>/dev/null | head -5 | tr '\n' ' ')"
        assert_equals "${f} writes nothing into the HOME it was started with" "" "${left}"
    done
}

# An "installed" claude that records each call, and a serena, so session-start's
# Serena registration (which runs only when both are on PATH) reaches claude on
# any machine, CI included.
mkdir -p "${W}/real-bin"
CALLS="${W}/claude-calls"
printf '#!/bin/sh\necho "${ACS_ARM:-?} $*" >> "%s"\nexit 0\n' "${CALLS}" > "${W}/real-bin/claude"
printf '#!/bin/sh\nexit 0\n' > "${W}/real-bin/serena"
chmod +x "${W}/real-bin/claude" "${W}/real-bin/serena"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

test_setup_env_shadows_an_installed_claude() {
    local got
    got="$(
        PATH="${W}/real-bin:${PATH}"
        setup_test_env
        command -v claude
        teardown_test_env
    )"
    case "${got}" in
        */acs-test.*/stub-bin/claude) _record_pass "after setup_test_env, claude resolves to the test's stub" ;;
        *) _record_fail "after setup_test_env, claude resolves to the test's stub" "got '${got}'" ;;
    esac
}

test_session_start_under_setup_env_never_runs_the_installed_claude() {
    # Not in test mode, so the Serena registration runs. The control gives the
    # hook a fresh HOME without setup_test_env and must be seen calling claude.
    (
        PATH="${W}/real-bin:${PATH}"
        setup_test_env
        ACS_ARM=stubbed CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${HOOK}" < /dev/null > /dev/null 2>&1
        teardown_test_env
    )
    (
        _h="${W}/control-home"; mkdir -p "${_h}"
        ACS_ARM=control HOME="${_h}" PATH="${W}/real-bin:${PATH}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            /bin/bash "${HOOK}" < /dev/null > /dev/null 2>&1
    )
    if grep -q '^control mcp ' "${CALLS}" 2>/dev/null; then
        _record_pass "the recorder sees session-start's claude call without setup_test_env (control)"
    else
        _record_fail "the recorder sees session-start's claude call without setup_test_env (control)" \
            "no control call recorded — the next cell is vacuous"
    fi
    if grep -q '^stubbed ' "${CALLS}" 2>/dev/null; then
        _record_fail "session-start under setup_test_env never runs the installed claude" \
            "recorded: $(grep '^stubbed ' "${CALLS}" | tr '\n' ';')"
    else
        _record_pass "session-start under setup_test_env never runs the installed claude"
    fi
}

test_runner_shadows_claude_for_every_file() {
    # Files that run hooks without setup_test_env (or after a teardown took its
    # stub off PATH) are covered by the runner. Driven through a copy of the
    # real runner; the control runs the same test file directly.
    local d="${W}/runner"
    mkdir -p "${d}/tests"
    cp "${SCRIPT_DIR}/run-tests.sh" "${d}/tests/run-tests.sh"
    printf '#!/usr/bin/env bash\nACS_ARM="$1" claude mcp list\nexit 0\n' > "${d}/tests/test-calls.sh"
    PATH="${W}/real-bin:${PATH}" GIT_CEILING_DIRECTORIES="${W}" \
        bash "${d}/tests/run-tests.sh" > "${W}/runner.log" 2>&1
    PATH="${W}/real-bin:${PATH}" bash "${d}/tests/test-calls.sh" direct
    if grep -q '^direct mcp list' "${CALLS}" 2>/dev/null; then
        _record_pass "the recorder sees a test file's claude call when run directly (control)"
    else
        _record_fail "the recorder sees a test file's claude call when run directly (control)" \
            "no call recorded — the next cell is vacuous"
    fi
    if grep -q '^? mcp list' "${CALLS}" 2>/dev/null; then
        _record_fail "under run-tests.sh no test file reaches the installed claude" \
            "recorded: $(grep '^? ' "${CALLS}" | tr '\n' ';')"
    else
        _record_pass "under run-tests.sh no test file reaches the installed claude"
    fi
}

test_probe_files_leave_nothing_in_tmpdir() {
    # Each called setup_test_env once at the top and never tore it down.
    local f t left
    for f in test-verb-attribution-probe.sh test-compliance-census-probe.sh; do
        t="${W}/tmp-${f%.sh}"; mkdir -p "${t}"
        TMPDIR="${t}" bash "${SCRIPT_DIR}/${f}" < /dev/null > "${W}/${f}.log" 2>&1
        assert_equals "${f} passes with a private TMPDIR" "0" "$?"
        left="$(ls -A "${t}" | tr '\n' ' ')"
        assert_equals "${f} leaves nothing in TMPDIR" "" "${left}"
    done
}

test_runner_names_a_file_that_leaves_tmpdir_entries() {
    # A copy of the real runner over two files: the first leaves a scratch dir,
    # the second cleans up after itself and must not be blamed.
    local d="${W}/leak-runner" outer="${W}/outer-tmp"
    mkdir -p "${d}/tests" "${outer}"
    cp "${SCRIPT_DIR}/run-tests.sh" "${d}/tests/run-tests.sh"
    printf '#!/usr/bin/env bash\nmktemp -d "${TMPDIR:-/tmp}/acs-test.XXXXXXXX" > /dev/null\nexit 0\n' \
        > "${d}/tests/test-a-leaks.sh"
    printf '#!/usr/bin/env bash\nt="$(mktemp -d "${TMPDIR:-/tmp}/acs-test.XXXXXXXX")"\nrm -rf "${t}"\nexit 0\n' \
        > "${d}/tests/test-b-cleans.sh"
    TMPDIR="${outer}" GIT_CEILING_DIRECTORIES="${W}" \
        bash "${d}/tests/run-tests.sh" > "${W}/leak-runner.log" 2>&1
    local rc=$?
    assert_equals "a file that leaves a TMPDIR entry fails the run" "1" "${rc}"
    # The sentinel is the log's last line; test files never name it (#263).
    assert_contains "the sentinel counts one failed file" "files=2 passed=1 failed=1 status=fail" \
        "$(tail -1 "${W}/leak-runner.log")"
    assert_contains "the leaking file is named, with what it left" \
        "FAIL (runner): test-a-leaks.sh left these in TMPDIR" "$(cat "${W}/leak-runner.log")"
    assert_contains "the leftover entry is listed" "    acs-test." "$(cat "${W}/leak-runner.log")"
    assert_not_contains "the file that cleans up is not blamed" "test-b-cleans.sh left" \
        "$(cat "${W}/leak-runner.log")"
    assert_equals "the run leaves nothing in the TMPDIR it was started with" "" \
        "$(ls -A "${outer}" | tr '\n' ' ')"
}

test_runner_gives_each_file_a_home_of_its_own() {
    # A copy of the real runner started with a stand-in for the user's HOME:
    # the first file writes into HOME, the second fails if it can see that.
    local d="${W}/home-runner" h="${W}/runner-home"
    mkdir -p "${d}/tests" "${h}" "${W}/home-runner-tmp"
    cp "${SCRIPT_DIR}/run-tests.sh" "${d}/tests/run-tests.sh"
    printf '#!/usr/bin/env bash\nmkdir -p "${HOME}/.claude" && echo x > "${HOME}/.claude/written"\nexit 0\n' \
        > "${d}/tests/test-a-writes-home.sh"
    printf '#!/usr/bin/env bash\n[ ! -e "${HOME}/.claude/written" ]\n' > "${d}/tests/test-b-sees-fresh-home.sh"
    HOME="${h}" TMPDIR="${W}/home-runner-tmp" GIT_CEILING_DIRECTORIES="${W}" \
        bash "${d}/tests/run-tests.sh" > "${W}/home-runner.log" 2>&1
    assert_equals "the runner's files write nothing into the HOME it was started with" "" \
        "$(cd "${h}" && find . -mindepth 1 | tr '\n' ' ')"
    assert_contains "each file gets a fresh HOME (the second file passes)" "files=2 passed=2 failed=0 status=pass" \
        "$(tail -1 "${W}/home-runner.log")"
}

test_runner_survives_a_leftover_it_cannot_remove() {
    # The first file leaves a dir it made unreadable; the second leaks a plain
    # one and must still be named, and nothing may outlive the run.
    local d="${W}/locked-runner" outer="${W}/locked-tmp"
    mkdir -p "${d}/tests" "${outer}"
    cp "${SCRIPT_DIR}/run-tests.sh" "${d}/tests/run-tests.sh"
    printf '#!/usr/bin/env bash\nt="$(mktemp -d "${TMPDIR:-/tmp}/locked.XXXXXX")"\nmkdir "${t}/in"\nchmod 000 "${t}/in" "${t}"\nexit 0\n' \
        > "${d}/tests/test-a-locks.sh"
    printf '#!/usr/bin/env bash\nmktemp -d "${TMPDIR:-/tmp}/acs-test.XXXXXXXX" > /dev/null\nexit 0\n' \
        > "${d}/tests/test-b-leaks.sh"
    TMPDIR="${outer}" GIT_CEILING_DIRECTORIES="${W}" \
        bash "${d}/tests/run-tests.sh" > "${W}/locked-runner.log" 2>&1
    assert_contains "the file that locked its leftover is named" \
        "FAIL (runner): test-a-locks.sh left these in TMPDIR" "$(cat "${W}/locked-runner.log")"
    assert_contains "a later file is still checked" \
        "FAIL (runner): test-b-leaks.sh left these in TMPDIR" "$(cat "${W}/locked-runner.log")"
    chmod -R u+rwx "${outer}" 2>/dev/null
    assert_equals "nothing outlives the run, the locked dir included" "" \
        "$(ls -A "${outer}" | tr '\n' ' ')"
}

test_tmp_leakers_use_tmpdir_and_clean_up() {
    # Found in review: these two made dirs under a hard-coded /tmp, which the
    # runner's TMPDIR check cannot see, and never removed them (five a run).
    # Snapshotting /tmp here would race other sessions' runs, so the cell pins
    # the templates and requires an empty private TMPDIR afterwards.
    local f t
    for f in test-branch-ledger.sh test-completion-ledger-crediting.sh; do
        assert_equals "${f} has no mktemp template under a hard-coded /tmp" "0" \
            "$(grep -c -E 'mktemp[^"]*"?/tmp/' "${SCRIPT_DIR}/${f}" | tr -d ' ')"
        t="${W}/tmp-${f%.sh}"; mkdir -p "${t}"
        TMPDIR="${t}" bash "${SCRIPT_DIR}/${f}" < /dev/null > "${W}/${f}.tmp.log" 2>&1
        assert_equals "${f} passes with a private TMPDIR" "0" "$?"
        assert_equals "${f} leaves nothing in TMPDIR" "" "$(ls -A "${t}" | tr '\n' ' ')"
    done
}

test_mcp_probe_names_a_stub_claude_in_its_skip() {
    # Under the runner, `claude` is the runner's stub, so the end-to-end cell
    # always skips; its message must say why rather than blame serena.
    local b="${W}/acs-run-stubs.fake"
    mkdir -p "${b}"
    printf '#!/bin/sh\nexit 0\n' > "${b}/claude"; chmod +x "${b}/claude"
    PATH="${b}:${PATH}" bash "${SCRIPT_DIR}/test-mcp-connection-probe.sh" < /dev/null > "${W}/stub-skip.log" 2>&1
    assert_contains "the skip names the test stub" "is a test stub" "$(grep -F 'SKIP' "${W}/stub-skip.log")"
}

test_files_leave_the_starting_home_untouched
test_mcp_probe_names_a_stub_claude_in_its_skip
test_tmp_leakers_use_tmpdir_and_clean_up
test_runner_gives_each_file_a_home_of_its_own
test_runner_survives_a_leftover_it_cannot_remove
test_runner_names_a_file_that_leaves_tmpdir_entries
test_probe_files_leave_nothing_in_tmpdir
test_setup_env_shadows_an_installed_claude
test_session_start_under_setup_env_never_runs_the_installed_claude
test_runner_shadows_claude_for_every_file

print_summary

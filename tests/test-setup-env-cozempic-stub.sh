#!/usr/bin/env bash
# tests/test-setup-env-cozempic-stub.sh — #369 follow-up
#
# session-start-hook.sh starts `cozempic init` detached whenever cozempic is on
# PATH. Every test that runs the hook after setup_test_env gives it a fresh HOME,
# where a real cozempic's first-run update check measured 23 s, so on a machine
# with cozempic installed each such test left an init running well past its own
# end. CI has no cozempic, so nothing there ever showed it.
#
# setup_test_env now puts a stub `cozempic` (exit 0, no output) first on PATH.
# The recorder below stands in for a real install: it writes one line per call,
# tagged with the arm that started it, so a call that escapes the stub is seen.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

W="$(mktemp -d "${TMPDIR:-/tmp}/acs-cozstub.XXXXXX")"
trap 'rm -rf "${W}"' EXIT
mkdir -p "${W}/real-bin"
MARK="${W}/calls"
printf '#!/bin/sh\necho "${ACS_ARM:-?} $*" >> "%s"\n' "${MARK}" > "${W}/real-bin/cozempic"
chmod +x "${W}/real-bin/cozempic"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

test_setup_env_shadows_an_installed_cozempic() {
    local got
    got="$(
        PATH="${W}/real-bin:${PATH}"
        setup_test_env
        command -v cozempic
        teardown_test_env
    )"
    case "${got}" in
        "${W}/real-bin/"*|'') _record_fail "after setup_test_env, cozempic resolves to the test's stub" "got '${got}'" ;;
        */acs-test.*) _record_pass "after setup_test_env, cozempic resolves to the test's stub" ;;
        *) _record_fail "after setup_test_env, cozempic resolves to the test's stub" "got '${got}'" ;;
    esac
}

test_session_start_under_setup_env_never_runs_the_installed_cozempic() {
    # The stubbed arm runs first and the control second; once the control's
    # detached init has written, the stubbed arm's (if any) has had longer.
    (
        PATH="${W}/real-bin:${PATH}"
        setup_test_env
        ACS_ARM=stubbed _SKILL_TEST_MODE=1 CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${HOOK}" < /dev/null > /dev/null 2>&1
        teardown_test_env
    )
    (
        _h="${W}/control-home"; mkdir -p "${_h}"
        ACS_ARM=control _SKILL_TEST_MODE=1 HOME="${_h}" PATH="${W}/real-bin:${PATH}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            /bin/bash "${HOOK}" < /dev/null > /dev/null 2>&1
    )
    local i=0
    while [ "${i}" -lt 50 ] && ! grep -q '^control ' "${MARK}" 2>/dev/null; do
        sleep 0.2; i=$((i + 1))
    done
    sleep 1
    if ! grep -q '^control init' "${MARK}" 2>/dev/null; then
        _record_fail "the recorder sees session-start's init without setup_test_env (control)" \
            "no control call recorded — the harness cannot see an escaped call, so the next cell is vacuous"
    else
        _record_pass "the recorder sees session-start's init without setup_test_env (control)"
    fi
    if grep -q '^stubbed ' "${MARK}" 2>/dev/null; then
        _record_fail "session-start under setup_test_env never runs the installed cozempic" \
            "recorded: $(grep '^stubbed ' "${MARK}" | tr '\n' ';')"
    else
        _record_pass "session-start under setup_test_env never runs the installed cozempic"
    fi
}

test_repeated_setup_keeps_one_stub_dir_on_path() {
    # Several files call setup_test_env once per cell, some without a teardown
    # in between; PATH must not collect one dead stub directory per call.
    local n
    n="$(
        _n() { printf '%s\n' "${PATH}" | tr ':' '\n' | grep -c '/acs-test\.'; }
        setup_test_env; _d1="${TEST_TMPDIR}"
        setup_test_env; _d2="${TEST_TMPDIR}"
        setup_test_env
        printf '%s ' "$(_n)"
        teardown_test_env
        printf '%s' "$(_n)"
        rm -rf "${_d1}" "${_d2}"
    )"
    assert_equals "three setups leave one stub directory on PATH, and teardown removes it" "1 0" "${n}"
}

test_runner_shadows_cozempic_for_every_file() {
    # Several files run session-start on a fresh HOME of their own without
    # setup_test_env (found in review), so the runner stubs cozempic for every
    # file it runs. Driven through a COPY of the real runner; the control runs
    # the same test file directly, proving the recorder sees the call.
    local d="${W}/runner"
    mkdir -p "${d}/tests"
    cp "${SCRIPT_DIR}/run-tests.sh" "${d}/tests/run-tests.sh"
    printf '#!/usr/bin/env bash\nACS_ARM="$1" cozempic init\nexit 0\n' > "${d}/tests/test-calls.sh"
    PATH="${W}/real-bin:${PATH}" GIT_CEILING_DIRECTORIES="${W}" \
        bash "${d}/tests/run-tests.sh" > "${W}/runner.log" 2>&1
    PATH="${W}/real-bin:${PATH}" bash "${d}/tests/test-calls.sh" direct
    if grep -q '^direct init' "${MARK}" 2>/dev/null; then
        _record_pass "the recorder sees a test file's cozempic call when run directly (control)"
    else
        _record_fail "the recorder sees a test file's cozempic call when run directly (control)" \
            "no call recorded — the next cell is vacuous"
    fi
    if grep -q '^? init' "${MARK}" 2>/dev/null; then
        _record_fail "under run-tests.sh no test file reaches the installed cozempic" \
            "recorded: $(grep '^? ' "${MARK}" | tr '\n' ';')"
    else
        _record_pass "under run-tests.sh no test file reaches the installed cozempic"
    fi
}

test_setup_env_shadows_an_installed_cozempic
test_session_start_under_setup_env_never_runs_the_installed_cozempic
test_runner_shadows_cozempic_for_every_file
test_repeated_setup_keeps_one_stub_dir_on_path

assert_test_functions_wired "${BASH_SOURCE[0]}"
print_summary

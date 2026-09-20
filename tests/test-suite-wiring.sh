#!/usr/bin/env bash
# tests/test-suite-wiring.sh — #271
#
# Two whole-suite invariants that nothing else checks, both of which fail
# SILENTLY and both of which were live when this file was written:
#
#   1. A test file's call list is unchecked in both directions. A name invoked
#      but not defined makes bash print `command not found` and carry on, with
#      print_summary still reporting success; a name defined but not invoked
#      simply never runs and nothing says so. The live instance was
#      test_no_stderr_without_explain in tests/test-routing.sh.
#
#   2. A file that bumps TESTS_PASSED or TESTS_FAILED directly, without also
#      bumping TESTS_RUN, reports more passes than runs. Measured before the
#      fix: test-routing.sh 500/496, test-registry.sh 187/160,
#      test-serena-autoregister.sh 31/18. A counter that can exceed its own
#      denominator is not a counter, and that exact string has already been
#      misread as a whole-suite result and copied into a pre-registration.
#
# This is a SWEEP rather than one call added to each file, deliberately: a
# per-file line covers the 20 files that exist today and silently fails to
# cover the 21st. The sweep's own floors are what keep it from going vacuous.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

FIXTURES="${SCRIPT_DIR}/fixtures/suite-wiring"

# ---------------------------------------------------------------------------
# The guard must agree with hand-checked fixtures before it is trusted on the
# real tree. Two authorities: these fixtures, and the sweep below.
# ---------------------------------------------------------------------------
# _probe_guard <expected:fail|pass> <label> <file>
#
# Runs the guard against a fixture and restores EVERY counter it touched before
# recording one verdict of our own. Restoring only TESTS_FAILED leaves the
# guard's own TESTS_RUN bump in place, and this file then reports more runs than
# verdicts — which is defect #2 of this very issue, reproduced inside the file
# fixing it. It was, on the first draft.
_probe_guard() {
    local _expect="$1" _label="$2" _file="$3"
    local _r="${TESTS_RUN}" _p="${TESTS_PASSED}" _f="${TESTS_FAILED}" _m="${FAIL_MESSAGES}"
    # Silence the inner guard: its own PASS/FAIL lines are probe internals, and a
    # green run that prints "FAIL:" is the log-misreading hazard this repo already
    # has a rule about. The counters it mutates are still read below.
    assert_test_functions_wired "${_file}" >/dev/null 2>&1
    local _fired=0
    [ "${TESTS_FAILED}" -gt "${_f}" ] && _fired=1
    TESTS_RUN="${_r}"; TESTS_PASSED="${_p}"; TESTS_FAILED="${_f}"; FAIL_MESSAGES="${_m}"
    if [ "${_expect}" = "fail" ]; then
        if [ "${_fired}" -eq 1 ]; then
            _record_pass "${_label}"
        else
            _record_fail "${_label}" "the red fixture PASSED — the guard would not catch the real instance"
        fi
    else
        if [ "${_fired}" -eq 0 ]; then
            _record_pass "${_label}"
        else
            _record_fail "${_label}" "the green fixture FAILED — the guard is rejecting a correct file"
        fi
    fi
}

test_guard_flags_defined_but_never_invoked() {
    _probe_guard fail "guard flags a defined-but-never-invoked test" "${FIXTURES}/red-uncalled.sh"
}

test_guard_flags_function_keyword_definition() {
    _probe_guard fail "guard sees a function-keyword definition that is never invoked" \
        "${FIXTURES}/red-function-keyword.sh"
}

test_guard_flags_invoked_but_never_defined() {
    _probe_guard fail "guard flags an invoked-but-never-defined test" "${FIXTURES}/red-undefined.sh"
}

test_guard_passes_a_legitimately_small_file() {
    # Pins the floor change. Under the previous `< 5` floor this fixture failed
    # for having no defect; six real files are this shape.
    _probe_guard pass "guard passes a correctly-wired file with fewer than five tests" "${FIXTURES}/green-small.sh"
}

test_guard_reports_an_unreadable_file() {
    _probe_guard fail "guard reports an unreadable file rather than passing vacuously" "${FIXTURES}/does-not-exist.sh"
}

# ---------------------------------------------------------------------------
# Sweep 1: every file carrying the bare-call idiom is wired in both directions.
#
# The loop runs in the CURRENT shell (a `for` over a glob, never a pipe) — a
# piped loop puts _record_pass/_record_fail in a subshell, where a mutation
# prints one FAIL and the summary still reports everything green.
# ---------------------------------------------------------------------------
test_every_test_file_is_wired() {
    echo "-- test: every test file's call list is wired both ways --"
    local f swept=0 defined
    for f in "${SCRIPT_DIR}"/test-*.sh; do
        defined="$(grep -cE '^test_[A-Za-z0-9_]+\(\)' "${f}")"
        [ "${defined}" -eq 0 ] && continue
        swept=$((swept + 1))
        assert_test_functions_wired "${f}"
    done
    # FLOOR: the sweep must actually have found files. A glob that resolves to
    # nothing, or a renamed idiom, would otherwise report a clean pass having
    # checked nothing at all.
    if [ "${swept}" -ge 15 ]; then
        _record_pass "wiring sweep covered ${swept} test files (floor 15)"
    else
        _record_fail "wiring sweep covered ${swept} test files (floor 15)" \
            "the sweep is not seeing the suite — every result above is vacuous"
    fi
}

# ---------------------------------------------------------------------------
# Sweep 2: TESTS_RUN is bumped wherever TESTS_PASSED/TESTS_FAILED is bumped.
# ---------------------------------------------------------------------------
test_counters_cannot_exceed_their_denominator() {
    echo "-- test: no file bumps a verdict counter without bumping TESTS_RUN --"
    local f base n_verdict n_run offenders="" checked=0
    for f in "${SCRIPT_DIR}"/test-*.sh "${SCRIPT_DIR}"/test-helpers.sh; do
        base="$(basename "${f}")"
        n_verdict="$(grep -oE 'TESTS_(PASSED|FAILED)=\$\(\(' "${f}" | wc -l | tr -d ' ')"
        [ "${n_verdict}" -eq 0 ] && continue
        checked=$((checked + 1))
        n_run="$(grep -oE 'TESTS_RUN=\$\(\(' "${f}" | wc -l | tr -d ' ')"
        if [ "${n_run}" -lt "${n_verdict}" ]; then
            offenders="${offenders} ${base}(verdict=${n_verdict},run=${n_run})"
        fi
    done
    if [ "${checked}" -eq 0 ]; then
        _record_fail "verdict counters are paired with TESTS_RUN" \
            "found no file bumping a verdict counter — the matcher is not seeing the suite"
    elif [ -n "${offenders}" ]; then
        _record_fail "verdict counters are paired with TESTS_RUN" \
            "files reporting more verdicts than runs:${offenders}"
    else
        _record_pass "every direct verdict bump is paired with TESTS_RUN (${checked} files)"
    fi
}

test_guard_flags_defined_but_never_invoked
test_guard_flags_invoked_but_never_defined
test_guard_flags_function_keyword_definition
test_guard_passes_a_legitimately_small_file
test_guard_reports_an_unreadable_file
test_every_test_file_is_wired
test_counters_cannot_exceed_their_denominator

print_summary

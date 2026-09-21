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
    local _expect="$1" _label="$2" _file="$3" _needle="${4:-}"
    local _r="${TESTS_RUN}" _p="${TESTS_PASSED}" _f="${TESTS_FAILED}" _m="${FAIL_MESSAGES}"
    # Silence the inner guard: its own PASS/FAIL lines are probe internals, and a
    # green run that prints "FAIL:" is the log-misreading hazard this repo already
    # has a rule about. The counters it mutates are still read below.
    # Output goes to a FILE, not through `$( )`. A command substitution runs the
    # guard in a subshell, where its counter mutations are lost and every
    # assertion below reads the pre-call values — the same subshell trap this
    # repo has hit in assertion loops. FAIL_MESSAGES holds only the label, so
    # the detail naming the offending function is on stdout and nowhere else.
    local _out
    _out="$(mktemp /tmp/acs-probe-guard-XXXXXX)"
    assert_test_functions_wired "${_file}" > "${_out}" 2>&1
    local _fired=0 _detail
    _detail="$(cat "${_out}")"
    rm -f "${_out}"
    [ "${TESTS_FAILED}" -gt "${_f}" ] && _fired=1
    TESTS_RUN="${_r}"; TESTS_PASSED="${_p}"; TESTS_FAILED="${_f}"; FAIL_MESSAGES="${_m}"
    if [ "${_expect}" = "fail" ]; then
        if [ "${_fired}" -ne 1 ]; then
            _record_fail "${_label}" "the red fixture PASSED — the guard would not catch the real instance"
        elif [ -n "${_needle}" ] && ! printf '%s' "${_detail}" | grep -qF "${_needle}"; then
            # A red cell that only checks "something failed" certifies that the
            # guard detects SOMETHING, not that it detects the defect the cell
            # is named for. Measured: mutating the floor to reject every file
            # left all four red cells reporting PASS. The reason is the thing
            # under test, so the reason is what is asserted.
            _record_fail "${_label}" \
                "the guard failed, but not for the named reason (expected to see '${_needle}')"
        else
            _record_pass "${_label}"
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
    _probe_guard fail "guard flags a defined-but-never-invoked test" \
        "${FIXTURES}/red-uncalled.sh" "test_delta_never_invoked"
}

test_guard_flags_function_keyword_definition() {
    _probe_guard fail "guard sees a function-keyword definition that is never invoked" \
        "${FIXTURES}/red-function-keyword.sh" "test_delta_never_invoked"
}

test_guard_flags_space_before_parens_definition() {
    _probe_guard fail "guard sees a space-before-parens definition that is never invoked" \
        "${FIXTURES}/red-space-before-parens.sh" "test_gamma"
}

test_guard_flags_invoked_but_never_defined() {
    _probe_guard fail "guard flags an invoked-but-never-defined test" \
        "${FIXTURES}/red-undefined.sh" "test_never_defined"
}

test_guard_passes_a_legitimately_small_file() {
    # Pins the floor change. Under the previous `< 5` floor this fixture failed
    # for having no defect; six real files are this shape.
    _probe_guard pass "guard passes a correctly-wired file with fewer than five tests" "${FIXTURES}/green-small.sh"
}

test_guard_reports_an_unreadable_file() {
    _probe_guard fail "guard reports an unreadable file rather than passing vacuously" \
        "${FIXTURES}/does-not-exist.sh" "cannot read the file"
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
# Coverage limit, checked as a SET rather than hidden or proxied.
#
# This sweep can only see assertions inside a `test_*` function the file
# invokes. Four files run their assertions at top level instead; the sweep's
# verdict on them means much less, and folding that into a clean pass hides the
# limit.
#
# It is NOT a defect check. A top-level assertion cannot have the
# defined-but-never-invoked defect — it runs as the script runs. What the old
# hardcoded floor of 5 accidentally provided was a shape SIGNAL, which this
# reproduces exactly instead of by proxy, and with none of that floor's false
# alarms on files that are simply small.
#
# The list is the gate. A FIFTH mixed-shape file must be loud, because that is
# the one nobody has read; and an entry that stops qualifying must also be
# loud, so a converted file cannot leave a stale exemption behind. Keyed by
# name — the classifier, not a line number, decides membership.
# ---------------------------------------------------------------------------
_EXPECTED_MIXED_SHAPE="test-consultation-routing.sh
test-routing-interactions.sh
test-second-opinion-content.sh
test-skill-content.sh"

test_mixed_shape_file_set_is_unchanged() {
    echo "-- test: the set of files this sweep barely covers is the known set --"
    local _scan _actual _new _gone
    _scan="${PROJECT_ROOT}/scripts/test-shape-scan.py"
    if ! command -v python3 >/dev/null 2>&1 || [ ! -r "${_scan}" ]; then
        _record_fail "mixed-shape scan is runnable" \
            "python3 or ${_scan} unavailable — this cell would pass having checked nothing"
        return
    fi
    _actual="$(python3 "${_scan}" "${SCRIPT_DIR}" | awk '{print $1}' | sort)"
    if [ -z "${_actual}" ]; then
        _record_fail "mixed-shape scan found the known files" \
            "the classifier reported nothing at all — it is not seeing the suite, so this cell is vacuous"
        return
    fi
    _new="$(comm -13 <(printf '%s\n' "${_EXPECTED_MIXED_SHAPE}" | sort) <(printf '%s\n' "${_actual}"))"
    _gone="$(comm -23 <(printf '%s\n' "${_EXPECTED_MIXED_SHAPE}" | sort) <(printf '%s\n' "${_actual}"))"
    if [ -n "${_new}" ]; then
        _record_fail "no NEW file escapes the wiring sweep" \
            "these run most assertions outside any test function, so the sweep says little about them — read them, then add them to _EXPECTED_MIXED_SHAPE: $(printf '%s' "${_new}" | tr '\n' ' ')"
    elif [ -n "${_gone}" ]; then
        _record_fail "the mixed-shape list has no stale entries" \
            "these no longer qualify and must be removed from _EXPECTED_MIXED_SHAPE: $(printf '%s' "${_gone}" | tr '\n' ' ')"
    else
        _record_pass "mixed-shape file set unchanged (4 known, none added or stale)"
    fi
}

# ---------------------------------------------------------------------------
# Sweep 2: TESTS_RUN is bumped wherever TESTS_PASSED/TESTS_FAILED is bumped.
# ---------------------------------------------------------------------------
test_counters_cannot_exceed_their_denominator() {
    echo "-- test: no file bumps a verdict counter without bumping TESTS_RUN --"
    local f base n_verdict n_run offenders="" checked=0
    # `test-*.sh` already matches test-helpers.sh; naming it again counted it
    # twice and the cell reported one more file than it had examined.
    for f in "${SCRIPT_DIR}"/test-*.sh; do
        base="$(basename "${f}")"
        # All three increment idioms, not just the assignment form. `(( X++ ))`
        # and `let X+=1` are invisible to an assignment-only matcher, so a file
        # adopting either scores zero verdict bumps, hits the `continue` below,
        # and leaves the population entirely — after which it can carry any
        # number of unpaired bumps while this cell still reports that every one
        # is paired. That is the #271 defect returning under a new idiom, and
        # the same reasoning already accepted for the `function` keyword form:
        # no file uses it today; the point is the day one does.
        #
        # The increment OPERATOR is required, not merely the name after `((`.
        # The first cut matched any `((` followed by the name, which caught
        # `exit $((TESTS_FAILED == 0 ? 0 : 1))` — a READ — and reported
        # test-serena-autoregister.sh as carrying an unpaired bump. A counter
        # matcher must not count reads.
        n_verdict="$(grep -oE 'TESTS_(PASSED|FAILED)=\$\(\(|\(\([[:space:]]*TESTS_(PASSED|FAILED)[[:space:]]*(\+\+|\+=|=[^=])|let[[:space:]]+TESTS_(PASSED|FAILED)[[:space:]]*(\+\+|\+=|=[^=])' "${f}" | wc -l | tr -d ' ')"
        [ "${n_verdict}" -eq 0 ] && continue
        checked=$((checked + 1))
        n_run="$(grep -oE 'TESTS_RUN=\$\(\(|\(\([[:space:]]*TESTS_RUN[[:space:]]*(\+\+|\+=|=[^=])|let[[:space:]]+TESTS_RUN[[:space:]]*(\+\+|\+=|=[^=])' "${f}" | wc -l | tr -d ' ')"
        if [ "${n_run}" -lt "${n_verdict}" ]; then
            offenders="${offenders} ${base}(verdict=${n_verdict},run=${n_run})"
        fi
    done
    # Floored at the CURRENT population, not at zero. A drop from five files to
    # one is exactly what a file silently leaving the population looks like, and
    # a floor of zero cannot see it — the same reasoning as the per-tree floors
    # in tests/test-hook-string-lint.sh.
    if [ "${checked}" -lt 5 ]; then
        _record_fail "verdict counters are paired with TESTS_RUN" \
            "only ${checked} files carry a verdict bump (expected at least 5) — a file has left the population, or the matcher is not seeing the suite"
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
test_guard_flags_space_before_parens_definition
test_guard_passes_a_legitimately_small_file
test_guard_reports_an_unreadable_file
test_every_test_file_is_wired
test_mixed_shape_file_set_is_unchanged
test_counters_cannot_exceed_their_denominator

print_summary

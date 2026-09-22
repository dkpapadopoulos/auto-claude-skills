#!/usr/bin/env bash
# tests/test-precondition-lint.sh — #275
#
# Three defects were found in ONE change's tests (2026-09-19), all the same
# shape: the cell ran, every assertion held, and the branch it advertised never
# executed because the environment sent it somewhere else. PATH handed a cell
# the very tool it was proving absent; a mutation control pointed the plugin
# root at a copy, which changes the gate's MODE rather than its code; and
# `jq empty` accepted a JSON stream, so a second concatenated object's empty
# fields satisfied every assertion below it.
#
# This is NOT [[prove-the-mutation-applied]]: there the mutation failed to
# apply and `cmp` catches it. Here it applied perfectly. A diff proves the
# artifact changed; it says nothing about which branch ran.
#
# TWO AUTHORITIES, per the repo's fixture-gate rule: the fixtures below are
# harvested VERBATIM from the real suite files at 3596f56^ (red) and 3596f56
# (green) — never hand-written, which would only prove the checker agrees with
# its author — and the expected rule name for each is hardcoded HERE. A fixture
# that fires the wrong rule is a fault, not a pass.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-precondition-lint.sh ==="

LINT="${PROJECT_ROOT}/scripts/precondition-lint.py"
FIX="${SCRIPT_DIR}/fixtures/precondition-lint"

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 unavailable — this file asserts a python checker and cannot degrade"; exit 1
fi
[ -r "${LINT}" ] || { echo "missing ${LINT}"; exit 1; }

_rules() { python3 "${LINT}" "$1" 2>/dev/null | sed -n 's/.*\[\([a-z-]*\)\].*/\1/p' | sort -u | paste -sd, - ; }

# _red <fixture> <expected-rule>
# "Something fired" is not the claim. An early cut detected red-01 only through
# the loose-json rule, so the arranged-absent-tool rule it exists for had zero
# coverage while the fixture reported caught.
_red() {
    local got; got="$(_rules "${FIX}/$1")"
    case ",${got}," in
        *",$2,"*) _record_pass "red $1 fires $2" ;;
        *) _record_fail "red $1 fires $2" "rules fired: ${got:-<none>}" ;;
    esac
}

# --- RED: each measured instance must fire, and fire its OWN rule ------------
test_red_fixtures_fire_their_own_rule() {
    _red red-01-arranged-absent-tool.sh.txt         arranged-absent-tool
    _red red-02-mutation-control-moved-roots.sh.txt mutation-control-moved-roots
    _red red-03-loose-json-oracle.sh.txt            loose-json-oracle
}

# --- GREEN: the repaired versions of the same three cells --------------------
test_green_fixtures_are_clean() {
    local _g
    for _g in green-01-asserted-absent-tool green-02-mutation-control-one-file green-03-exact-object-count; do
        if python3 "${LINT}" "${FIX}/${_g}.sh.txt" >/dev/null 2>&1; then
            _record_pass "green ${_g} is clean"
        else
            _record_fail "green ${_g} is clean" "fired: $(_rules "${FIX}/${_g}.sh.txt")"
        fi
    done
}

# --- the fixture set may not shrink -----------------------------------------
# A gate driven by fixtures needs a floor equal to the needle count, or deleting
# a fixture silently narrows the gate while every cell above still passes.
test_fixture_set_does_not_shrink() {
    local _nred _ngreen
    _nred="$(ls -1 "${FIX}"/red-*.sh.txt 2>/dev/null | wc -l | tr -d ' ')"
    _ngreen="$(ls -1 "${FIX}"/green-*.sh.txt 2>/dev/null | wc -l | tr -d ' ')"
    assert_equals "the pinned red set still has 3 cases"   "3" "${_nred}"
    assert_equals "the pinned green set still has 3 cases" "3" "${_ngreen}"
    # Named apart on purpose: the harvested claim, and the floors above that
    # enforce it, must not be diluted by fixtures this repo authored.
    assert_equals "the synthetic regression set still has 2 cases" "2" \
        "$(ls -1 "${FIX}"/regress-*.sh.txt 2>/dev/null | wc -l | tr -d ' ')"
}

# --- two independent sections each report -----------------------------------
# The dedup exists so a function nested in a section is not reported twice. The
# first cut keyed it on (file, rule), so a SECOND independent section arranging
# its own precondition was swallowed — the checker would under-report exactly
# the file that needs it most (found in review).
test_two_independent_sections_both_report() {
    local _n
    _n="$(python3 "${LINT}" "${FIX}/regress-two-sections.sh.txt" 2>/dev/null | grep -c 'arranged-absent-tool')"
    assert_equals "two independent sections each report" "2" "${_n}"
}

# --- an escaped quote does not end the string -------------------------------
# `_strip_comment` walked with `for ... enumerate` and `continue`, which
# advances to the escaped character and then PROCESSES it — so a `\"` inside a
# double-quoted string closed it early and everything after was read as
# unquoted code. A `#` beyond that point would truncate the cell.
test_escaped_quote_does_not_end_the_string() {
    local _out
    _out="$(python3 "${LINT}" "${FIX}/regress-escaped-quote.sh.txt" 2>/dev/null)"
    case "${_out}" in
        *arranged-absent-tool*) _record_pass "an escaped quote does not truncate the cell" ;;
        *) _record_fail "an escaped quote does not truncate the cell" "got: ${_out:-<none>}" ;;
    esac
}

# --- THE GATE: the live suite must be clean ---------------------------------
test_live_suite_is_clean() {
    local _live
    _live="$(python3 "${LINT}" "${PROJECT_ROOT}"/tests/*.sh 2>&1)"
    if [ -z "${_live}" ]; then
        _record_pass "no test cell in tests/*.sh arranges a precondition it claims to test"
    else
        _record_fail "no test cell arranges a precondition it claims to test" \
            "$(printf '%s' "${_live}" | head -20)"
    fi
}

# --- the checker reports CANNOT-CHECK rather than clean ----------------------
# An unreadable input returning 0 would report every future file as clean.
test_unreadable_input_is_cannot_check() {
    python3 "${LINT}" "${FIX}/definitely-not-here.sh.txt" >/dev/null 2>&1
    assert_equals "an unreadable input exits 3, never 0" "3" "$?"
    python3 "${LINT}" >/dev/null 2>&1
    assert_equals "no arguments exits 2" "2" "$?"
}

# Every test_ function defined here must be invoked below (PR review).
assert_test_functions_wired "$0"

test_red_fixtures_fire_their_own_rule
test_green_fixtures_are_clean
test_fixture_set_does_not_shrink
test_two_independent_sections_both_report
test_escaped_quote_does_not_end_the_string
test_live_suite_is_clean
test_unreadable_input_is_cannot_check

print_summary

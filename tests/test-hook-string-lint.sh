#!/usr/bin/env bash
# tests/test-hook-string-lint.sh — #143
#
# A backticked word written as markdown quoting inside a DOUBLE-quoted hook
# string is executed as a command substitution at assignment time: stderr gets a
# command-not-found and the word silently disappears from the rendered text.
# `bash -n` stays clean because the substitution is syntactically valid, and the
# suite stays green unless something asserts that string's rendered content.
# That shipped once already (PR #38, a DISCOVER RED_FLAGS string).
#
# TWO AUTHORITIES, deliberately. The lint is one. The other is bash itself:
# every fixture is EXECUTED, and a red fixture must produce a command-not-found
# while the green one must not. Without that second authority the fixtures only
# ever prove the scanner agrees with the fixture author — and on the first draft
# it did not: a shape written as "green" genuinely executed `the docs`, which
# only running it revealed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

LINT="${PROJECT_ROOT}/scripts/hook-string-lint.py"
FIXTURES="${SCRIPT_DIR}/fixtures/hook-string-lint"

_have_python() { command -v python3 >/dev/null 2>&1; }

test_lint_is_runnable() {
    # Assert the precondition, do not arrange it: a missing interpreter must
    # FAIL loudly here rather than let every cell below pass having run nothing.
    if ! _have_python; then
        _record_fail "python3 is available to run the lint" \
            "python3 not on PATH — every assertion in this file would be vacuous"
        return
    fi
    if [ -r "${LINT}" ]; then
        _record_pass "python3 is available and the lint script is readable"
    else
        _record_fail "lint script is readable" "missing ${LINT}"
    fi
}

test_red_double_quoted_is_flagged() {
    _have_python || return
    local out
    out="$(python3 "${LINT}" "${FIXTURES}/red-backtick-in-double-quotes.sh" 2>&1)"
    if printf '%s' "${out}" | grep -q 'double-quoted string'; then
        _record_pass "lint flags a live backtick in a double-quoted assignment"
    else
        _record_fail "lint flags a live backtick in a double-quoted assignment" \
            "no finding reported; output: [${out}]"
    fi
}

test_red_unquoted_heredoc_is_flagged() {
    _have_python || return
    local out
    out="$(python3 "${LINT}" "${FIXTURES}/red-unquoted-heredoc.sh" 2>&1)"
    if printf '%s' "${out}" | grep -q 'unquoted heredoc'; then
        _record_pass "lint flags a live backtick in an unquoted heredoc"
    else
        _record_fail "lint flags a live backtick in an unquoted heredoc" \
            "no finding reported; output: [${out}]"
    fi
}

test_green_safe_backticks_are_not_flagged() {
    _have_python || return
    local out rc
    out="$(python3 "${LINT}" "${FIXTURES}/green-safe-backticks.sh" 2>&1)"; rc=$?
    if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then
        _record_pass "lint passes comments, single quotes, quoted heredocs and nested \$( )"
    else
        _record_fail "lint passes safe backticks" "false positives: [${out}]"
    fi
}

# ---------------------------------------------------------------------------
# Second authority: bash. The fixtures must actually behave as labelled.
# ---------------------------------------------------------------------------
_fires_substitution() {
    # 0 = a substitution fired (command-not-found on stderr), 1 = none did.
    local err
    err="$(/bin/bash "$1" 2>&1 >/dev/null)"
    printf '%s' "${err}" | grep -qi 'command not found'
}

test_red_fixtures_really_execute_the_backtick() {
    local f ok=1 checked=0
    for f in "${FIXTURES}"/red-*.sh; do
        checked=$((checked + 1))
        _fires_substitution "${f}" || ok=0
    done
    if [ "${checked}" -eq 0 ]; then
        _record_fail "red fixtures really execute the backtick" \
            "no red fixtures found — the glob matched nothing and this cell is vacuous"
    elif [ "${ok}" -eq 1 ]; then
        _record_pass "every red fixture really executes its backtick under bash (${checked})"
    else
        _record_fail "red fixtures really execute the backtick" \
            "a red fixture ran clean — it does not reproduce the defect it is named for"
    fi
}

test_green_fixture_really_executes_nothing() {
    if _fires_substitution "${FIXTURES}/green-safe-backticks.sh"; then
        _record_fail "green fixture executes no substitution" \
            "the green fixture DID run a command — it is a red case mislabelled"
    else
        _record_pass "green fixture executes no substitution under bash"
    fi
}

# ---------------------------------------------------------------------------
# The real tree must be clean. This is what keeps a newly-mishandled shell
# construct loud: it shows up as a false positive on a known-good file.
# ---------------------------------------------------------------------------
test_hooks_tree_is_clean() {
    _have_python || return
    local out rc n
    n="$(ls -1 "${PROJECT_ROOT}"/hooks/*.sh "${PROJECT_ROOT}"/hooks/lib/*.sh 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n}" -lt 10 ]; then
        _record_fail "hooks tree is clean of live backticks" \
            "only ${n} hook files found — the glob is not seeing the tree, so a pass would be vacuous"
        return
    fi
    out="$(python3 "${LINT}" "${PROJECT_ROOT}"/hooks/*.sh "${PROJECT_ROOT}"/hooks/lib/*.sh 2>&1)"; rc=$?
    if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then
        _record_pass "hooks tree (${n} files) carries no live backtick substitution"
    else
        _record_fail "hooks tree is clean of live backticks" "${out}"
    fi
}

test_lint_is_runnable
test_red_double_quoted_is_flagged
test_red_unquoted_heredoc_is_flagged
test_green_safe_backticks_are_not_flagged
test_red_fixtures_really_execute_the_backtick
test_green_fixture_really_executes_nothing
test_hooks_tree_is_clean

print_summary

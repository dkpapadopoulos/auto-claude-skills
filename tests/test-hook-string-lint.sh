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
# every fixture is EXECUTED, and the oracle is whether the backticked word
# SURVIVES into the rendered output — gone in a red fixture, intact in a green
# one. That is the defect as users meet it, and unlike the text of a failed PATH
# lookup it does not vary with shell, locale or sandbox. Without that second authority the fixtures only
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
# DESYNC CELLS. Each of these made the scanner lose track of its own quoting
# state and report a file CLEAN while bash really did execute the backtick —
# the silent direction, found by a reviewer after the first version shipped.
#
# They are red fixtures, not "cannot-check" fixtures: once the construct is
# modelled the defect inside it must be FOUND, so a cell that merely stopped
# claiming clean would not pin the fix.
# ---------------------------------------------------------------------------
_flags_defect() { python3 "${LINT}" "$1" 2>/dev/null | grep -q 'live backtick'; }

test_desync_heredoc_opener_with_trailing_comment() {
    _have_python || return
    # `cat <<EOF   # note` — the comment branch consumed the newline that ends
    # the opener without popping the pending heredoc, so body mode never began.
    if _flags_defect "${FIXTURES}/red-heredoc-trailing-comment.sh"; then
        _record_pass "a heredoc opener with a trailing comment still enters body mode"
    else
        _record_fail "heredoc opener with a trailing comment" "scanner missed the live backtick in the body"
    fi
}

test_desync_ansi_c_quoting() {
    _have_python || return
    # $'don\'t' — a backslash DOES escape inside ANSI-C quoting, unlike an
    # ordinary single-quoted string, so treating them alike desynced the state.
    if _flags_defect "${FIXTURES}/red-ansi-c-quoting.sh"; then
        _record_pass "ANSI-C quoting does not desynchronise the scan"
    else
        _record_fail "ANSI-C quoting" "scanner missed the live backtick after a \$'...' string"
    fi
}

test_desync_backslash_heredoc_delimiter() {
    _have_python || return
    # `<<\EOF` quotes the delimiter exactly as `<<'EOF'` does.
    if _flags_defect "${FIXTURES}/red-backslash-heredoc-delim.sh"; then
        _record_pass "a backslash-quoted heredoc delimiter is recognised"
    else
        _record_fail "backslash-quoted heredoc delimiter" "scanner missed the live backtick after the body"
    fi
}

test_herestring_is_not_a_heredoc() {
    _have_python || return
    # `<<<` re-matched as `<<` registered a heredoc named after the operand,
    # whose terminator never arrives — the rest of the file went unscanned and
    # therefore reported clean. This is the green direction: no defect, and the
    # scan must remain COHERENT (exit 0, not the cannot-check exit 3).
    local rc
    python3 "${LINT}" "${FIXTURES}/green-herestring.sh" >/dev/null 2>&1; rc=$?
    if [ "${rc}" -eq 0 ]; then
        _record_pass "a here-string is not read as a heredoc opener"
    else
        _record_fail "here-string handling" "expected a clean coherent scan, got exit ${rc}"
    fi
}

test_incoherent_scan_reports_cannot_check() {
    # THE compensating control. A scan that ends with an unclosed quote must say
    # it could not check, never that the file is clean — a blind spot in a
    # scanner like this one goes silent, it does not announce itself.
    _have_python || return
    local f rc
    f="$(mktemp /tmp/acs-lint-incoherent-XXXXXX.sh)"
    printf '%s\n' '#!/bin/bash' 'echo "unterminated' > "${f}"
    python3 "${LINT}" "${f}" >/dev/null 2>&1; rc=$?
    rm -f "${f}"
    if [ "${rc}" -eq 3 ]; then
        _record_pass "an incoherent scan reports cannot-check, not clean"
    else
        _record_fail "incoherent scan reports cannot-check" "expected exit 3, got ${rc}"
    fi
}

# ---------------------------------------------------------------------------
# Second authority: bash. The fixtures must actually behave as labelled.
# ---------------------------------------------------------------------------
# _word_is_eaten <fixture> <word>
#   0 when <word> does NOT survive into the fixture's rendered stdout, i.e. the
#   backtick was executed and the word silently vanished — which IS the defect.
#
#   The oracle is the DISAPPEARANCE, not the error message. The first version
#   grepped stderr for "command not found": that passed here and FAILED under a
#   reviewer's sandbox, because the text of a failed PATH lookup depends on the
#   shell, the locale and the sandbox, while the word going missing is the thing
#   the issue is actually about. Asserting on runtime message text is this
#   repo's own documented trap.
_word_is_eaten() {
    local out
    out="$(/bin/bash "$1" 2>/dev/null)"
    ! printf '%s' "${out}" | grep -qF "$2"
}

test_desync_heredoc_opener_with_trailing_comment
test_desync_ansi_c_quoting
test_desync_backslash_heredoc_delimiter
test_herestring_is_not_a_heredoc
test_incoherent_scan_reports_cannot_check
test_red_fixtures_really_lose_the_word() {
    # Each red fixture is paired with the word its backtick swallows.
    local ok=1
    _word_is_eaten "${FIXTURES}/red-backtick-in-double-quotes.sh" "verification-before-completion" || ok=0
    _word_is_eaten "${FIXTURES}/red-unquoted-heredoc.sh" "project-verification" || ok=0
    if [ "${ok}" -eq 1 ]; then
        _record_pass "every red fixture really loses its backticked word when run (2)"
    else
        _record_fail "red fixtures really lose the backticked word" \
            "a red fixture rendered its word intact — it does not reproduce the defect it is named for"
    fi
}

test_green_fixture_really_keeps_its_words() {
    # The mirror assertion: in the green fixture the same shapes are literal, so
    # the words must SURVIVE. Without this direction, a fixture that rendered
    # nothing at all would satisfy the red cells above.
    local ok=1
    _word_is_eaten "${FIXTURES}/green-safe-backticks.sh" "verification-before-completion" && ok=0
    _word_is_eaten "${FIXTURES}/green-safe-backticks.sh" "openspec/changes" && ok=0
    _word_is_eaten "${FIXTURES}/green-safe-backticks.sh" "project-verification" && ok=0
    if [ "${ok}" -eq 1 ]; then
        _record_pass "green fixture renders every backticked word intact (3)"
    else
        _record_fail "green fixture renders its words intact" \
            "a word went missing — a green shape is executing, so it is a red case mislabelled"
    fi
}

# ---------------------------------------------------------------------------
# The real tree must be clean. This is what keeps a newly-mishandled shell
# construct loud: it shows up as a false positive on a known-good file.
# ---------------------------------------------------------------------------
test_shell_tree_is_clean() {
    # Scope is hooks/ AND tests/ AND scripts/, not hooks/ alone. The issue asked
    # only for hooks, but both other trees measured clean when this was written,
    # so the coverage is free — and it is not hypothetical: a label written as
    # "a `function`-keyword definition" in tests/test-suite-wiring.sh executed
    # `function` and silently rendered as "a -keyword definition", which is this
    # exact defect, in the change that adds the lint for it.
    _have_python || return
    local out rc n
    n="$(ls -1 "${PROJECT_ROOT}"/hooks/*.sh "${PROJECT_ROOT}"/hooks/lib/*.sh \
                "${PROJECT_ROOT}"/tests/*.sh "${PROJECT_ROOT}"/scripts/*.sh 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n}" -lt 60 ]; then
        _record_fail "shell tree is clean of live backticks" \
            "only ${n} files found — the glob is not seeing the tree, so a pass would be vacuous"
        return
    fi
    out="$(python3 "${LINT}" "${PROJECT_ROOT}"/hooks/*.sh "${PROJECT_ROOT}"/hooks/lib/*.sh \
                              "${PROJECT_ROOT}"/tests/*.sh "${PROJECT_ROOT}"/scripts/*.sh 2>&1)"; rc=$?
    if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then
        _record_pass "hooks, tests and scripts (${n} files) carry no live backtick substitution"
    else
        _record_fail "shell tree is clean of live backticks" "${out}"
    fi
}

test_lint_is_runnable
test_red_double_quoted_is_flagged
test_red_unquoted_heredoc_is_flagged
test_green_safe_backticks_are_not_flagged
test_red_fixtures_really_lose_the_word
test_green_fixture_really_keeps_its_words
test_shell_tree_is_clean

print_summary

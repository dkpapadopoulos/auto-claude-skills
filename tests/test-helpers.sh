#!/usr/bin/env bash
# test-helpers.sh — Source-able test helper library for auto-claude-skills
# Bash 3.2 compatible (macOS default). No external deps beyond bash and jq.

# ---------------------------------------------------------------------------
# Counters
# ---------------------------------------------------------------------------
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAIL_MESSAGES=""

# ---------------------------------------------------------------------------
# Environment setup / teardown
# ---------------------------------------------------------------------------
setup_test_env() {
    TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/acs-test.XXXXXXXX")"

    TEST_HOME="${TEST_TMPDIR}/home"
    TEST_PLUGIN_CACHE="${TEST_HOME}/.claude/plugin-cache"
    TEST_USER_SKILLS="${TEST_HOME}/.claude/user-skills"
    TEST_REGISTRY_CACHE="${TEST_HOME}/.claude/registry-cache"
    TEST_USER_CONFIG="${TEST_HOME}/.claude/config.json"

    mkdir -p "${TEST_PLUGIN_CACHE}"
    mkdir -p "${TEST_USER_SKILLS}"
    mkdir -p "${TEST_REGISTRY_CACHE}"
    mkdir -p "$(dirname "${TEST_USER_CONFIG}")"

    export HOME="${TEST_HOME}"
    export CLAUDE_PLUGIN_ROOT="${TEST_HOME}/.claude"

    export TEST_TMPDIR TEST_HOME TEST_PLUGIN_CACHE TEST_USER_SKILLS
    export TEST_REGISTRY_CACHE TEST_USER_CONFIG
}

teardown_test_env() {
    if [ -n "${TEST_TMPDIR:-}" ] && [ -d "${TEST_TMPDIR}" ]; then
        rm -rf "${TEST_TMPDIR}"
    fi
    unset TEST_TMPDIR TEST_HOME TEST_PLUGIN_CACHE TEST_USER_SKILLS
    unset TEST_REGISTRY_CACHE TEST_USER_CONFIG
}

# isolated_tool_path — echo a PATH that exposes ONLY jq (via a private symlink)
# plus the system dirs. Use this in "nothing installed" capability tests instead
# of prepending `dirname "$(command -v jq)"`: on a dev machine jq commonly shares
# a directory (e.g. /opt/homebrew/bin) with openspec/chub/other CLI tools, so
# exposing jq's whole directory LEAKS those siblings and the detection sees them
# as installed. Symlinking jq alone keeps jq available while masking the rest.
# Requires TEST_TMPDIR (set by setup_test_env).
isolated_tool_path() {
    local _bin="${TEST_TMPDIR}/isolated-bin"
    mkdir -p "${_bin}"
    local _jq
    _jq="$(command -v jq 2>/dev/null)"
    [ -n "${_jq}" ] && ln -sf "${_jq}" "${_bin}/jq" 2>/dev/null
    printf '%s' "${_bin}:/usr/bin:/bin:/usr/sbin:/sbin"
}

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

# _record_pass description
_record_pass() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "  PASS: %s\n" "$1"
}

# _record_fail description detail
_record_fail() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "  FAIL: %s\n" "$1"
    if [ -n "${2:-}" ]; then
        printf "        %s\n" "$2"
    fi
    if [ -n "${FAIL_MESSAGES}" ]; then
        FAIL_MESSAGES="${FAIL_MESSAGES}
"
    fi
    FAIL_MESSAGES="${FAIL_MESSAGES}FAIL: $1"
}

# assert_equals description expected actual
assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [ "${expected}" = "${actual}" ]; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "expected: '${expected}', got: '${actual}'"
    fi
}

# assert_contains description needle haystack
assert_contains() {
    local description="$1"
    local needle="$2"
    local haystack="$3"

    case "${haystack}" in
        *"${needle}"*)
            _record_pass "${description}"
            ;;
        *)
            _record_fail "${description}" "expected to contain: '${needle}'"
            ;;
    esac
}

# assert_not_contains description needle haystack
assert_not_contains() {
    local description="$1"
    local needle="$2"
    local haystack="$3"

    case "${haystack}" in
        *"${needle}"*)
            _record_fail "${description}" "expected NOT to contain: '${needle}'"
            ;;
        *)
            _record_pass "${description}"
            ;;
    esac
}

# assert_json_valid description file
assert_json_valid() {
    local description="$1"
    local file="$2"

    if [ ! -f "${file}" ]; then
        _record_fail "${description}" "file does not exist: ${file}"
        return
    fi

    if jq empty "${file}" >/dev/null 2>&1; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "invalid JSON in: ${file}"
    fi
}

# assert_not_empty description value
assert_not_empty() {
    local description="$1"
    local value="$2"

    if [ -n "${value}" ]; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "expected non-empty value"
    fi
}

# assert_file_exists description file
assert_file_exists() {
    local description="$1"
    local file="$2"

    if [ -f "${file}" ]; then
        _record_pass "${description}"
    else
        _record_fail "${description}" "file not found: ${file}"
    fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
# assert_test_functions_wired <file>
#
# Most test files in this repo end in a bare list of function calls. That list
# is unchecked in BOTH directions and each direction fails silently:
#
#   invoked but not defined -> bash prints `command not found`, the file keeps
#       going, and print_summary still reports "All tests passed" with exit 0.
#       Measured: four undefined names gave 123/123 green.
#   defined but not invoked -> the test simply never runs and nothing says so.
#       Live instance at the time of writing: test_no_stderr_without_explain
#       (tests/test-routing.sh) is defined and invoked nowhere.
#
# The first direction is the one people think of; the second is the one that
# quietly deletes coverage. Both are checked here.
#
# The FLOOR matters as much as the comparison: with no needles (an unresolvable
# path, a CRLF checkout, a changed idiom) the DEFINED set is empty, every
# comparison trivially holds, and the guard reports a pass having checked
# nothing — the repo's own "a gate anchor needs a floor equal to the needle
# count" rule.
#
# KNOWN GAP, deliberately left and stated rather than silently carried: a
# definition or a call that is INDENTED is not seen by either matcher, because
# both anchor at column 0. That is the repo's own bare-call idiom, and widening
# the invoked-set matcher to indented lines would match every conditional call
# inside a helper. An indented file trips the zero-needles floor instead.
#
# The floor is zero-needles, NOT an arbitrary minimum. It was `< 5`, and an
# earlier version of this comment defended the change by claiming a floor of 5
# "caught nothing a zero-check misses". A reviewer refuted that by measurement,
# and the correction matters more than the original point:
#
# Of the six files a floor of 5 flagged, only two (test-consol-marker.sh,
# test-session-token.sh) are genuinely small — every assertion they run sits
# inside an invoked test function. The other four are a DIFFERENT RUNNER SHAPE,
# and most of their assertions live outside any `test_` function at all:
# test-skill-content.sh 77 assertion lines against 3 definitions,
# test-second-opinion-content.sh 66 against 2, test-routing-interactions.sh 53
# against 3, and test-consultation-routing.sh runs top-level `for` loops with no
# assertion lines this matcher can see.
#
# So a floor of 5 was accidentally pointing at something real. It was still the
# wrong instrument — an arbitrary count is a proxy, and it failed the two files
# that are simply small — but "it caught nothing" was false. What those four
# files need is not a floor; it is the knowledge that THIS SWEEP BARELY COVERS
# THEM, which tests/test-suite-wiring.sh now reports by name rather than
# folding into a clean pass.
#
# An indented call list is not a vacuity case either — it leaves DEFINED
# populated and INVOKED empty, which the comparison below reports loudly.
assert_test_functions_wired() {
    local _f="${1:-}" _defined _invoked _undefined _uncalled _n
    if [ ! -r "${_f}" ]; then
        _record_fail "test functions are wired (${_f})" "cannot read the file — the guard checked nothing"
        return
    fi
    # All three bash definition forms. `function test_x { ... }` and
    # `test_x () { ... }` (note the space) each define a test exactly as
    # `test_x() { ... }` does, and matching only the last makes such a test
    # invisible to the DEFINED set — so one that is never invoked reads as
    # correctly wired. No file uses either form today; the point is that the day
    # one does, it must not open the gap this guard exists to close.
    #
    # The space form was missed on the first cut, which added only the `function`
    # form on exactly that reasoning and did not apply it to the sibling case —
    # a reviewer pointed out the inconsistency. Measured behaviour-preserving:
    # 537 definitions matched across tests/ before and after.
    _defined="$( { grep -oE '^test_[A-Za-z0-9_]+[[:space:]]*\(\)' "${_f}" | sed 's/[[:space:]]*()$//'
                   grep -oE '^function[[:space:]]+test_[A-Za-z0-9_]+' "${_f}" | sed 's/^function[[:space:]]*//'
                 } | sort -u)"
    _invoked="$(grep -oE '^test_[A-Za-z0-9_]+$'      "${_f}" | sort -u)"
    _n="$(printf '%s\n' "${_defined}" | grep -c '[^[:space:]]')"
    if [ "${_n}" -eq 0 ]; then
        _record_fail "test functions are wired (${_f})" \
            "found 0 test definitions — the matcher is not seeing this file (unresolvable path, CRLF, or a changed idiom), so every comparison below would hold vacuously"
        return
    fi
    _undefined="$(comm -13 <(printf '%s\n' "${_defined}") <(printf '%s\n' "${_invoked}") | grep '[^[:space:]]' || true)"
    _uncalled="$( comm -23 <(printf '%s\n' "${_defined}") <(printf '%s\n' "${_invoked}") | grep '[^[:space:]]' || true)"
    if [ -z "${_undefined}" ] && [ -z "${_uncalled}" ]; then
        _record_pass "every test function is both defined and invoked (${_n} in $(basename "${_f}"))"
    else
        _record_fail "every test function is both defined and invoked ($(basename "${_f}"))" \
            "invoked-but-undefined: [${_undefined}]; defined-but-never-invoked: [${_uncalled}]"
    fi
}

print_summary() {
    echo ""
    echo "=============================="
    printf "Tests run:    %d\n" "${TESTS_RUN}"
    printf "Tests passed: %d\n" "${TESTS_PASSED}"
    printf "Tests failed: %d\n" "${TESTS_FAILED}"
    echo "=============================="

    if [ "${TESTS_FAILED}" -gt 0 ]; then
        echo ""
        echo "Failures:"
        printf "%s\n" "${FAIL_MESSAGES}"
        return 1
    fi

    echo "All tests passed."
    return 0
}

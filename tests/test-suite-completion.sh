#!/usr/bin/env bash
# test-suite-completion.sh — Regression test for #263.
#
# THE DEFECT. tests/run-tests.sh finishes with a summary block:
#
#     ============================================
#       Files run:    153
#       Files passed: 153
#       Files failed: 0
#     ============================================
#
# and tests/test-helpers.sh::print_summary ends every INDIVIDUAL test file with
#
#     ==============================
#     Tests run:    42
#     Tests passed: 42
#     Tests failed: 0
#     ==============================
#
# Same frame, same four-space padding, one word apart. A reader who lands on a
# per-file block — tailing a still-running log, or reading one that was reaped
# partway — cannot tell it from the runner's own terminal block by shape.
#
# Nothing in the repo asserted the runner's block was present, so the only
# signals a normal check inspects (a large PASS count, no `FAIL:` lines) all
# read GREEN on a suite that never finished. Measured 2026-08-27 on a real
# reaped run: 91 of 122 files executed, thousands of PASS assertions, zero
# `FAIL:` lines. CI and agents alike go green on that.
#
# THE FIX under test: run-tests.sh emits a single completion sentinel that no
# per-file block can produce, and scripts/assert-suite-complete.sh classifies a
# log with FOUR outcomes, never two:
#
#     0  complete, suite passed        -> the only state that licenses a claim
#     1  incomplete / truncated / vacuous
#     2  complete, suite FAILED
#     3  cannot check (missing, unreadable, empty, no argument)
#
# The separation matters: "I could not look" must never present as success,
# and "it did not finish" must never be confused with "it failed".
#
# METHOD. Every fixture log in this file is produced by the REAL runner
# (copied verbatim, per tests/test-suite-stdin-guard.sh's precedent) driven
# over synthetic test files — never hand-written. A hand-written fixture only
# proves the checker agrees with this test's idea of the format, which is how
# an output classifier ships while misclassifying 100% of production input
# (see .claude/knowledge/classifier-fixtures-from-real-producer.md).
#
# Bash 3.2 compatible (macOS default).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER="${SCRIPT_DIR}/run-tests.sh"
CHECKER="${PROJECT_ROOT}/scripts/assert-suite-complete.sh"

# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-suite-completion.sh ==="
echo ""

WORK="$(mktemp -d "${TMPDIR:-/tmp}/acs-suite-completion.XXXXXXXX")" || WORK=""
if [ -z "${WORK}" ] || [ ! -d "${WORK}" ]; then
    echo "FATAL: could not create a temp dir; refusing to run" >&2
    exit 1
fi
cleanup() { chmod -R u+rwX "${WORK}" 2>/dev/null; rm -rf "${WORK}"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Build a miniature suite and drive the REAL runner over it.
# ---------------------------------------------------------------------------
# mk_suite <dir> <n_pass> <n_fail>  — synthetic test files that print the same
# per-file summary shape the real helpers print, so the truncation fixtures
# contain the very block that is confusable with the runner's own.
mk_suite() {
    local dir="$1" n_pass="$2" n_fail="$3" i=0
    mkdir -p "${dir}"
    cp "${RUNNER}" "${dir}/run-tests.sh"
    i=1
    while [ "${i}" -le "${n_pass}" ]; do
        cat > "${dir}/test-pass-${i}.sh" <<'INNER'
echo "  PASS: synthetic assertion"
echo ""
echo "=============================="
printf "Tests run:    %d\n" 3
printf "Tests passed: %d\n" 3
printf "Tests failed: %d\n" 0
echo "=============================="
echo "All tests passed."
exit 0
INNER
        i=$((i + 1))
    done
    i=1
    while [ "${i}" -le "${n_fail}" ]; do
        cat > "${dir}/test-fail-${i}.sh" <<'INNER'
echo "  FAIL: synthetic assertion"
exit 1
INNER
        i=$((i + 1))
    done
}

PASS_DIR="${WORK}/pass/tests"
FAIL_DIR="${WORK}/fail/tests"
EMPTY_DIR="${WORK}/empty/tests"
mk_suite "${PASS_DIR}" 5 0
mk_suite "${FAIL_DIR}" 4 1
mkdir -p "${EMPTY_DIR}" && cp "${RUNNER}" "${EMPTY_DIR}/run-tests.sh"

LOG_PASS="${WORK}/complete-pass.log"
LOG_FAIL="${WORK}/complete-fail.log"
LOG_EMPTY="${WORK}/complete-empty.log"
bash "${PASS_DIR}/run-tests.sh"  > "${LOG_PASS}"  2>&1; RC_PASS=$?
bash "${FAIL_DIR}/run-tests.sh"  > "${LOG_FAIL}"  2>&1; RC_FAIL=$?
bash "${EMPTY_DIR}/run-tests.sh" > "${LOG_EMPTY}" 2>&1; RC_EMPTY=$?

# ---------------------------------------------------------------------------
# Truncation fixtures, cut out of the REAL complete log.
# ---------------------------------------------------------------------------
TOTAL_LINES="$(wc -l < "${LOG_PASS}" | tr -d ' ')"

# (a) mid-file: inside the third test file's own output.
CUT_MID="$(grep -n -- '--- Running: test-pass-3.sh ---' "${LOG_PASS}" | head -1 | cut -d: -f1)"
CUT_MID=$((CUT_MID + 3))
head -n "${CUT_MID}" "${LOG_PASS}" > "${WORK}/trunc-midfile.log"

# (b) between files: immediately before the fourth file starts.
CUT_BETWEEN="$(grep -n -- '--- Running: test-pass-4.sh ---' "${LOG_PASS}" | head -1 | cut -d: -f1)"
CUT_BETWEEN=$((CUT_BETWEEN - 1))
head -n "${CUT_BETWEEN}" "${LOG_PASS}" > "${WORK}/trunc-between.log"

# (c) THE DANGEROUS ONE: every file ran, the summary block is present, only the
#     sentinel is missing. This is the log a `grep -q FAIL` check calls green.
head -n $((TOTAL_LINES - 1)) "${LOG_PASS}" > "${WORK}/trunc-before-sentinel.log"

# (d) truncated at the very first line.
head -n 1 "${LOG_PASS}" > "${WORK}/trunc-first-line.log"

: > "${WORK}/empty.log"
printf 'garbage with no structure at all\n' > "${WORK}/garbage.log"

UNREADABLE="${WORK}/unreadable.log"
cp "${LOG_PASS}" "${UNREADABLE}"
chmod 000 "${UNREADABLE}" 2>/dev/null

# sentinel duplicated, and sentinel not last
SENTINEL_LINE="$(tail -n 1 "${LOG_PASS}")"
cat "${LOG_PASS}" > "${WORK}/sentinel-twice.log"
printf '%s\n' "${SENTINEL_LINE}" >> "${WORK}/sentinel-twice.log"
cat "${LOG_PASS}" > "${WORK}/sentinel-not-last.log"
printf 'trailing output after the sentinel\n' >> "${WORK}/sentinel-not-last.log"

# counts that do not add up (files != passed + failed)
sed 's/files=5 passed=5 failed=0/files=9 passed=5 failed=0/' "${LOG_PASS}" \
    > "${WORK}/counts-inconsistent.log"

run_checker() {
    bash "${CHECKER}" "$@" >/dev/null 2>&1
    printf '%s' "$?"
}

# ---------------------------------------------------------------------------
# 1. The four outcomes
# ---------------------------------------------------------------------------
echo "--- outcomes ---"
assert_equals "complete + passing log exits 0" "0" "$(run_checker "${LOG_PASS}")"
assert_equals "complete + FAILING log exits 2 (complete, not incomplete)" \
    "2" "$(run_checker "${LOG_FAIL}")"
assert_equals "truncated mid-file exits 1" "1" "$(run_checker "${WORK}/trunc-midfile.log")"
assert_equals "truncated between files exits 1" "1" "$(run_checker "${WORK}/trunc-between.log")"
assert_equals "truncated before the sentinel exits 1" \
    "1" "$(run_checker "${WORK}/trunc-before-sentinel.log")"
assert_equals "truncated at the first line exits 1" \
    "1" "$(run_checker "${WORK}/trunc-first-line.log")"
assert_equals "unstructured garbage exits 1" "1" "$(run_checker "${WORK}/garbage.log")"

echo ""
echo "--- cannot-check is distinct from both clean and incomplete ---"
assert_equals "empty log exits 3" "3" "$(run_checker "${WORK}/empty.log")"
assert_equals "missing file exits 3" "3" "$(run_checker "${WORK}/no-such-file.log")"
assert_equals "no argument exits 3" "3" "$(run_checker)"
if [ -r "${UNREADABLE}" ]; then
    # running as root, or a filesystem that ignores the mode — skip loudly
    _record_pass "unreadable log exits 3 (SKIPPED: file still readable as this user)"
else
    assert_equals "unreadable log exits 3" "3" "$(run_checker "${UNREADABLE}")"
fi

# ---------------------------------------------------------------------------
# 2. A vacuous run is not a pass
# ---------------------------------------------------------------------------
echo ""
echo "--- vacuous and malformed completions ---"
assert_equals "a run over zero test files does not license a pass claim" \
    "1" "$(run_checker "${LOG_EMPTY}")"
assert_equals "sentinel appearing twice exits 1" \
    "1" "$(run_checker "${WORK}/sentinel-twice.log")"
assert_equals "sentinel not the last line exits 1" \
    "1" "$(run_checker "${WORK}/sentinel-not-last.log")"
assert_equals "internally inconsistent counts exit 1" \
    "1" "$(run_checker "${WORK}/counts-inconsistent.log")"

# ---------------------------------------------------------------------------
# 3. END TO END: the checker catches exactly what the naive check misses
# ---------------------------------------------------------------------------
# Asserting only "the checker says incomplete" would pass even if the naive
# check also caught it, which would make this whole change pointless. Both
# halves are asserted together.
echo ""
echo "--- the naive check's blind spot ---"
NAIVE_FAILS="$(grep -c 'FAIL:' "${WORK}/trunc-before-sentinel.log" | tr -d ' ')"
assert_equals "the truncated log has zero FAIL: lines (a naive check reads it green)" \
    "0" "${NAIVE_FAILS}"
assert_equals "...and the checker still reports it incomplete" \
    "1" "$(run_checker "${WORK}/trunc-before-sentinel.log")"

# ---------------------------------------------------------------------------
# 4. Mutation: the sentinel emit is load-bearing
# ---------------------------------------------------------------------------
echo ""
echo "--- mutation: strip the sentinel emit from the runner ---"
MUT_DIR="${WORK}/mutant/tests"
mk_suite "${MUT_DIR}" 5 0
grep -v 'ACS-RUN-TESTS-COMPLETE' "${RUNNER}" > "${MUT_DIR}/run-tests.sh"
if cmp -s "${RUNNER}" "${MUT_DIR}/run-tests.sh"; then
    _record_fail "mutation actually changed the runner" \
        "stripping ACS-RUN-TESTS-COMPLETE left the file identical — the sentinel is absent, so every cell above is vacuous"
else
    _record_pass "mutation actually changed the runner"
    bash "${MUT_DIR}/run-tests.sh" > "${WORK}/mutant.log" 2>&1
    assert_equals "a runner with no sentinel produces a log the checker calls incomplete" \
        "1" "$(run_checker "${WORK}/mutant.log")"
fi

# ---------------------------------------------------------------------------
# 5. The sentinel cannot be forged by a per-file block
# ---------------------------------------------------------------------------
echo ""
echo "--- sentinel uniqueness ---"
EMITTERS="$(grep -l 'ACS-RUN-TESTS-COMPLETE' "${SCRIPT_DIR}"/test-*.sh 2>/dev/null | wc -l | tr -d ' ')"
assert_equals "exactly one tests/test-*.sh mentions the sentinel (this file)" "1" "${EMITTERS}"
assert_equals "test-helpers.sh does not emit the sentinel" "" \
    "$(grep -c 'ACS-RUN-TESTS-COMPLETE' "${SCRIPT_DIR}/test-helpers.sh" 2>/dev/null | grep -v '^0$')"

# ---------------------------------------------------------------------------
# 6. No-regression: the runner's own exit codes are unchanged
# ---------------------------------------------------------------------------
echo ""
echo "--- runner exit codes unchanged ---"
assert_equals "all-pass run still exits 0" "0" "${RC_PASS}"
assert_equals "run with a failing file still exits 1" "1" "${RC_FAIL}"
assert_equals "run with no test files still exits 0" "0" "${RC_EMPTY}"
assert_contains "the failing run still names the failed file" \
    "test-fail-1.sh" "$(cat "${LOG_FAIL}")"

print_summary

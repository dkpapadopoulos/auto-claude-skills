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
# METHOD. Every fixture log that must LOOK LIKE runner output is produced by
# the REAL runner (copied verbatim, per tests/test-suite-stdin-guard.sh's
# precedent) driven over synthetic test files, then cut or field-edited. None
# is typed out by hand. A hand-written fixture only proves the checker agrees
# with this test's idea of the format, which is how an output classifier ships
# while misclassifying 100% of production input (see
# .claude/knowledge/classifier-fixtures-from-real-producer.md).
#
# The exceptions are the two fixtures whose whole point is that they are NOT
# runner output — an empty log and an unstructured one — which no producer can
# supply.
#
# This was almost untrue: the first cut of the count-validation cells typed out
# bare sentinel lines. Review caught it, and the cost was concrete rather than
# stylistic — a legitimate checker hardening (the frame cross-check below)
# breaks a hand-typed sentinel that real runner output satisfies, so the
# hand-written fixtures had begun constraining the checker's DESIGN.
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
CUT_MID="$(grep -n -F -- '--- Running: test-pass-3.sh ---' "${LOG_PASS}" | head -1 | cut -d: -f1)"
CUT_MID=$((CUT_MID + 3))
head -n "${CUT_MID}" "${LOG_PASS}" > "${WORK}/trunc-midfile.log"

# (b) between files: immediately before the fourth file starts.
CUT_BETWEEN="$(grep -n -F -- '--- Running: test-pass-4.sh ---' "${LOG_PASS}" | head -1 | cut -d: -f1)"
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
# The trailing line must itself PARSE as a sentinel-shaped line. With
# `trailing output after the sentinel` the cell passed even with the whole
# last-line check deleted — the malformed-fields branch caught it instead, so
# the assertion was satisfied by the fallback path and pinned nothing (the
# repo's own M9 lesson). Caught in review.
cat "${LOG_PASS}" > "${WORK}/sentinel-not-last.log"
printf 'summary files=5 passed=5 failed=0 status=pass\n' >> "${WORK}/sentinel-not-last.log"

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
# Self-describing rather than `status=pass`: a naive consumer grepping the
# status field would otherwise get the exact misleading signal this change
# exists to kill.
assert_contains "a zero-file run is labelled none, not pass" \
    "status=none" "$(tail -n 1 "${LOG_EMPTY}")"
assert_equals "sentinel appearing twice exits 1" \
    "1" "$(run_checker "${WORK}/sentinel-twice.log")"
assert_equals "sentinel not the last line exits 1" \
    "1" "$(run_checker "${WORK}/sentinel-not-last.log")"
assert_equals "internally inconsistent counts exit 1" \
    "1" "$(run_checker "${WORK}/counts-inconsistent.log")"

# --- counts the shell cannot EVALUATE. These are the regression for the one
# --- Critical this file missed: `case ''|*[!0-9]*` admitted them, `[ -ne ]`
# --- then failed, and with no `set -e` execution fell through to status=pass
# --- and exit 0 — a clean pass reported on input just proven unparseable.
# _sentinel_log <files> <passed> <failed> <status> -> path
# Takes the REAL complete log and rewrites the runner's frame and its sentinel
# TOGETHER, so the pair stays internally consistent the way the runner emits
# it. Rewriting only the sentinel would leave a frame that disagrees with it,
# which the cross-check below (correctly) rejects — and the cell would then be
# measuring the fixture's inconsistency rather than the field under test.
_sentinel_log() {
    awk -v f="$1" -v p="$2" -v x="$3" -v st="$4" '
        /^  Files run:    /        { printf "  Files run:    %s\n", f; next }
        /^  Files passed: /        { printf "  Files passed: %s\n", p; next }
        /^  Files failed: /        { printf "  Files failed: %s\n", x; next }
        /^ACS-RUN-TESTS-COMPLETE / { printf "ACS-RUN-TESTS-COMPLETE files=%s passed=%s failed=%s status=%s\n", f, p, x, st; next }
        { print }
    ' "${LOG_PASS}" > "${WORK}/synth.log"
    printf '%s' "${WORK}/synth.log"
}
assert_equals "a count past INT64_MAX is not a pass" \
    "1" "$(run_checker "$(_sentinel_log 9223372036854775808 1 0 pass)")"
assert_equals "a leading-zero (octal-trap) count is not a pass" \
    "1" "$(run_checker "$(_sentinel_log 08 08 0 pass)")"

# --- three checker branches that no cell reached: mutating any of them to
# --- exit 0 left this file 25/25 green (review I1).
assert_equals "status=pass contradicted by failed>0 is not a pass" \
    "1" "$(run_checker "$(_sentinel_log 5 3 2 pass)")"
assert_equals "an unrecognised status is not a pass" \
    "1" "$(run_checker "$(_sentinel_log 5 5 0 banana)")"
printf '   \n\t\n   \n' > "${WORK}/whitespace.log"
assert_equals "a whitespace-only log is cannot-check, not incomplete" \
    "3" "$(run_checker "${WORK}/whitespace.log")"

# --- I4: the sentinel proves the runner REACHED ITS END, not that its glob
# --- discovered everything. A partial checkout yields a smaller, well-formed,
# --- entirely green run.
assert_equals "a short run is a pass when no floor is demanded" \
    "0" "$(run_checker "$(_sentinel_log 1 1 0 pass)")"
assert_equals "...and is NOT a pass under --min-files" \
    "1" "$(bash "${CHECKER}" --min-files 5 "$(_sentinel_log 1 1 0 pass)" >/dev/null 2>&1; printf '%s' "$?")"
assert_equals "--min-files with a non-count argument is cannot-check" \
    "3" "$(bash "${CHECKER}" --min-files zzz "${LOG_PASS}" >/dev/null 2>&1; printf '%s' "$?")"

# A log whose NAME begins with `-` must still be read, not parsed as options.
# The obvious guard is wrong: `--` is not portable to BSD awk (macOS), where
# `awk '...' -- file` dies with "can't open file --", so every read goes
# through redirection instead. Pinned because that is easy to "tidy" back.
cp "${LOG_PASS}" "${WORK}/-dash.log"
# NOTE the `--`: passing `./-dash.log` proves nothing, because `./-dash.log`
# is not a flag to any tool and the cell stays green with the fix reverted.
# The bare name after `--` is what reaches the tools. (First cut used `./` and
# was vacuous; caught by mutation, not by reading it.)
#
# The tool that actually breaks is GREP, not awk — measured: awk reads
# `-dash.log` happily, while grep rejects it as `-d`. Mutate the grep line, not
# the awk one, if you want to see this cell fail.
assert_equals "a log whose name starts with a dash is read, not parsed as flags" \
    "0" "$(cd "${WORK}" && bash "${CHECKER}" -- -dash.log >/dev/null 2>&1; printf '%s' "$?")"

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
# Remove the FEATURE (function definition + every call site), not just the
# printf line — stripping the printf alone leaves an orphaned function body and
# the mutant is then a broken runner rather than a feature-free one.
awk '/^emit_completion_sentinel\(\) \{/ {skip=1}
     skip && /^\}/            {skip=0; next}
     skip                      {next}
     /emit_completion_sentinel / {next}
     {print}' "${RUNNER}" > "${MUT_DIR}/run-tests.sh"
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
echo "--- sentinel uniqueness, and its HONEST limit ---"
# The previous form asserted `grep -l ... | wc -l == 1`, which is still 1 with
# the feature deleted from the runner entirely — vacuous w.r.t. what it claimed
# (review I3). Anchor on the producer first.
assert_equals "the RUNNER emits the sentinel" "1" \
    "$(grep -c -F 'ACS-RUN-TESTS-COMPLETE' "${RUNNER}" | tr -d ' ')"
assert_equals "no tests/test-*.sh other than this one mentions the sentinel" "1" \
    "$(grep -l -F 'ACS-RUN-TESTS-COMPLETE' "${SCRIPT_DIR}"/test-*.sh 2>/dev/null | wc -l | tr -d ' ')"
assert_file_exists "test-helpers.sh is present (so the next assertion is not vacuous)" \
    "${SCRIPT_DIR}/test-helpers.sh"
assert_equals "test-helpers.sh does not emit the sentinel" "0" \
    "$(grep -c -F 'ACS-RUN-TESTS-COMPLETE' "${SCRIPT_DIR}/test-helpers.sh" 2>/dev/null | tr -d ' ')"

# KNOWN LIMIT, pinned rather than papered over. The sentinel is a CONVENTION
# enforced by a source grep, not a property: a test file that printed the
# literal string as its own last line, in a run reaped at exactly that instant,
# would be read as complete. Do not describe this checker as tamper-proof.
# What IS a property: if the suite runs to its end the forged line and the real
# one are both present, and two sentinels are rejected. That mitigation is what
# the cell below pins.
FORGE_DIR="${WORK}/forge/tests"
mk_suite "${FORGE_DIR}" 2 0
cat > "${FORGE_DIR}/test-forger.sh" <<'INNER'
echo "  PASS: synthetic"
echo "ACS-RUN-TESTS-COMPLETE files=3 passed=3 failed=0 status=pass"
exit 0
INNER
bash "${FORGE_DIR}/run-tests.sh" > "${WORK}/forged-complete.log" 2>&1
assert_equals "a forged sentinel in a FINISHED run is caught (two sentinels)" \
    "1" "$(run_checker "${WORK}/forged-complete.log")"
FORGE_CUT="$(grep -n -F 'ACS-RUN-TESTS-COMPLETE' "${WORK}/forged-complete.log" | head -1 | cut -d: -f1)"
head -n "${FORGE_CUT}" "${WORK}/forged-complete.log" > "${WORK}/forged-reaped.log"
# The frame cross-check narrows this: at the instant of the forged sentinel the
# runner has not yet printed its own "Files run:" frame, so the claim has
# nothing to corroborate it. The window is NOT closed — a test file that prints
# both lines deliberately still forges — so the source-grep cells above remain
# the primary control and this stays a documented limit, not a solved problem.
assert_equals "a forged sentinel reaped mid-run has no runner frame to back it" \
    "1" "$(run_checker "${WORK}/forged-reaped.log")"

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

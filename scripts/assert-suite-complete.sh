#!/usr/bin/env bash
# assert-suite-complete.sh — Decide whether a tests/run-tests.sh log represents
# a suite that actually FINISHED, and whether it passed. (#263)
#
# WHY THIS EXISTS. The runner's summary block is shape-identical to the block
# tests/test-helpers.sh::print_summary emits at the end of every individual test
# file — same frame, same padding, `Files run:` against `Tests run:`. So suite
# completion was assertable only by ABSENCE, and the absence of a thing is
# exactly what a reader does not notice. On a real reaped run (2026-08-27) 91 of
# 122 files had executed and the log carried thousands of PASS assertions and
# not one `FAIL:` line: every signal a normal check inspects said green.
#
# The rule this script enforces: gate a pass claim on the completion sentinel's
# PRESENCE, never on the absence of `FAIL:` lines.
#
# FOUR OUTCOMES, NEVER TWO:
#
#   0  complete, suite passed   — the only state that licenses "the suite passed"
#   1  complete-but-not-a-pass  — truncated, vacuous (0 files), or malformed
#   2  complete, suite FAILED   — it finished and it failed; a real red
#   3  CANNOT CHECK             — no argument, missing, unreadable, or empty log
#
# 3 is separate from 1 on purpose. A checker that reports clean when it could
# not parse its input is worse than no checker, because CI goes green on it; and
# "it did not finish" must never be confused with "it failed" or with "I could
# not look".
#
# Usage:  assert-suite-complete.sh <logfile>
#         bash tests/run-tests.sh > run.log 2>&1; assert-suite-complete.sh run.log
#
# Bash 3.2 compatible (macOS default). No jq, no external deps beyond coreutils.
# Regression: tests/test-suite-completion.sh

set -u

EX_PASS=0
EX_NOT_A_PASS=1
EX_FAILED=2
EX_CANNOT_CHECK=3

SENTINEL_TOKEN='ACS-RUN-TESTS-COMPLETE'

die_cannot_check() {
    printf 'CANNOT CHECK: %s\n' "$1" >&2
    exit "${EX_CANNOT_CHECK}"
}

LOG="${1:-}"

[ -n "${LOG}" ]     || die_cannot_check "no log file given (usage: $(basename "$0") <logfile>)"
[ -e "${LOG}" ]     || die_cannot_check "no such file: ${LOG}"
[ -f "${LOG}" ]     || die_cannot_check "not a regular file: ${LOG}"
[ -r "${LOG}" ]     || die_cannot_check "not readable: ${LOG}"
[ -s "${LOG}" ]     || die_cannot_check "empty log: ${LOG}"

# Whitespace-only is empty for our purposes, and `-s` does not catch it.
if ! grep -q '[^[:space:]]' "${LOG}" 2>/dev/null; then
    die_cannot_check "log contains only whitespace: ${LOG}"
fi

# --- how many sentinels, and is one of them last? -------------------------
# grep -c exits 1 on zero matches; capture the count without letting that
# status escape.
N_SENTINEL="$(grep -c "^${SENTINEL_TOKEN} " "${LOG}" 2>/dev/null)" || N_SENTINEL=0
case "${N_SENTINEL}" in
    ''|*[!0-9]*) N_SENTINEL=0 ;;
esac

if [ "${N_SENTINEL}" -eq 0 ]; then
    printf 'INCOMPLETE: no completion sentinel in %s — the suite did not finish.\n' "${LOG}"
    printf '            A large PASS count and zero FAIL: lines do NOT mean it passed;\n'
    printf '            a reaped or still-running suite produces exactly that.\n'
    exit "${EX_NOT_A_PASS}"
fi

if [ "${N_SENTINEL}" -gt 1 ]; then
    printf 'INCOMPLETE: %s completion sentinels in %s — expected exactly one.\n' \
        "${N_SENTINEL}" "${LOG}"
    exit "${EX_NOT_A_PASS}"
fi

LAST_LINE="$(awk 'NF { last = $0 } END { print last }' "${LOG}")"
case "${LAST_LINE}" in
    "${SENTINEL_TOKEN} "*) : ;;
    *)
        printf 'INCOMPLETE: the completion sentinel is not the last line of %s —\n' "${LOG}"
        printf '            output continued after the runner claimed to be done.\n'
        exit "${EX_NOT_A_PASS}"
        ;;
esac

# --- parse the counts -----------------------------------------------------
_field() {
    printf '%s\n' "${LAST_LINE}" \
        | sed -n "s/.*[[:space:]]$1=\([^[:space:]][^[:space:]]*\).*/\1/p" \
        | head -1
}

FILES="$(_field files)"
PASSED="$(_field passed)"
FAILED="$(_field failed)"
STATUS="$(_field status)"

for _v in "${FILES}" "${PASSED}" "${FAILED}"; do
    case "${_v}" in
        ''|*[!0-9]*)
            printf 'INCOMPLETE: malformed completion sentinel in %s:\n  %s\n' "${LOG}" "${LAST_LINE}"
            exit "${EX_NOT_A_PASS}"
            ;;
    esac
done

if [ "${FILES}" -ne $(( PASSED + FAILED )) ]; then
    printf 'INCOMPLETE: sentinel counts do not add up in %s (files=%s, passed=%s, failed=%s).\n' \
        "${LOG}" "${FILES}" "${PASSED}" "${FAILED}"
    exit "${EX_NOT_A_PASS}"
fi

if [ "${FILES}" -eq 0 ]; then
    printf 'NOT A PASS: the run completed over ZERO test files (%s).\n' "${LOG}"
    printf '            Nothing was verified — a vacuous run is not a green one.\n'
    exit "${EX_NOT_A_PASS}"
fi

case "${STATUS}" in
    pass)
        if [ "${FAILED}" -ne 0 ]; then
            printf 'INCOMPLETE: sentinel says status=pass with failed=%s in %s.\n' "${FAILED}" "${LOG}"
            exit "${EX_NOT_A_PASS}"
        fi
        printf 'COMPLETE: %s test files ran, all passed (%s).\n' "${FILES}" "${LOG}"
        exit "${EX_PASS}"
        ;;
    fail)
        printf 'COMPLETE BUT FAILED: %s test files ran, %s failed (%s).\n' \
            "${FILES}" "${FAILED}" "${LOG}"
        exit "${EX_FAILED}"
        ;;
    *)
        printf 'INCOMPLETE: unrecognised status in sentinel of %s:\n  %s\n' "${LOG}" "${LAST_LINE}"
        exit "${EX_NOT_A_PASS}"
        ;;
esac

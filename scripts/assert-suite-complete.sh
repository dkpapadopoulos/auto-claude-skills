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
# Every read of the log goes through REDIRECTION, never a filename argument.
# Measured, because the two tools fail in OPPOSITE directions:
#   grep FILENAME : `-dash.log` is parsed as options and the read fails
#                   (`invalid argument -d ...`; note grep may be ugrep here).
#   awk  --       : BSD awk (macOS) has no end-of-options marker and dies with
#                   `can't open file --`, though it reads `-dash.log` fine.
# So neither `--` nor a bare filename works for both, and per-tool special
# casing is a list that will be wrong later. Redirection is immune to a leading
# `-` and needs no special casing at all.
# Pinned by tests/test-suite-completion.sh; mutating the grep line back to a
# filename argument turns that cell red.
#
# Usage:  assert-suite-complete.sh [--min-files N] <logfile>
#         bash tests/run-tests.sh > run.log 2>&1; assert-suite-complete.sh run.log
#
# --min-files N guards the OTHER way a suite can fail to run in full: the
# sentinel proves the runner reached its end, not that its glob discovered
# everything. A partial checkout, an unreadable tests/ dir, or a file renamed
# off `test-*.sh` yields a smaller, entirely well-formed, entirely green run.
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

# _is_count — strict. The previous `case ''|*[!0-9]*` admitted values that
# `[ -ne ]` and `$(( ))` then FAILED to evaluate: anything past INT64_MAX, and
# leading-zero forms containing 8 or 9 (an octal error). With no `set -e` the
# failing comparison printed to stderr and execution fell THROUGH to the
# status=pass branch and exit 0 — the script reporting a clean pass on input it
# had just proven it could not parse, which is the one thing its header forbids.
# Measured: `files=9223372036854775808 passed=1` and `files=08 passed=08` both
# exited 0 with "all passed". Bounding the length makes the later arithmetic
# total, so no evaluation can fail and fall through.
_is_count() {
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
        0)           return 0 ;;
        0*)          return 1 ;;   # leading zeros: octal trap, and the runner never emits them
    esac
    [ "${#1}" -le 9 ]
}

MIN_FILES=0
while [ "$#" -gt 0 ]; do
    case "${1}" in
        --min-files)
            shift
            if ! _is_count "${1:-}"; then
                printf 'CANNOT CHECK: --min-files needs a plain count, got %s\n' "${1:-<nothing>}" >&2
                exit "${EX_CANNOT_CHECK}"
            fi
            MIN_FILES="${1}"; shift
            ;;
        --) shift; break ;;
        -*) printf 'CANNOT CHECK: unknown option %s\n' "${1}" >&2; exit "${EX_CANNOT_CHECK}" ;;
        *)  break ;;
    esac
done

LOG="${1:-}"

[ -n "${LOG}" ]     || die_cannot_check "no log file given (usage: $(basename "$0") <logfile>)"
[ -e "${LOG}" ]     || die_cannot_check "no such file: ${LOG}"
[ -f "${LOG}" ]     || die_cannot_check "not a regular file: ${LOG}"
[ -r "${LOG}" ]     || die_cannot_check "not readable: ${LOG}"
[ -s "${LOG}" ]     || die_cannot_check "empty log: ${LOG}"

# Whitespace-only is empty for our purposes, and `-s` does not catch it.
if ! grep -q -e '[^[:space:]]' < "${LOG}" 2>/dev/null; then
    die_cannot_check "log contains only whitespace: ${LOG}"
fi

# --- how many sentinels, and is one of them last? -------------------------
# grep -c exits 1 on zero matches; capture the count without letting that
# status escape.
N_SENTINEL="$(grep -c -e "^${SENTINEL_TOKEN} " < "${LOG}" 2>/dev/null)" || N_SENTINEL=0
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

LAST_LINE="$(awk 'NF { last = $0 } END { print last }' < "${LOG}")"
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
    if ! _is_count "${_v}"; then
        printf 'INCOMPLETE: malformed or unevaluatable count in the sentinel of %s:\n  %s\n' \
            "${LOG}" "${LAST_LINE}"
        exit "${EX_NOT_A_PASS}"
    fi
done

if [ "${FILES}" -ne $(( PASSED + FAILED )) ]; then
    printf 'INCOMPLETE: sentinel counts do not add up in %s (files=%s, passed=%s, failed=%s).\n' \
        "${LOG}" "${FILES}" "${PASSED}" "${FAILED}"
    exit "${EX_NOT_A_PASS}"
fi

# CROSS-CHECK against the runner's own frame. The sentinel alone is a
# convention a test file could print; the frame line immediately above it is
# emitted by the runner AFTER every file has run, so a log reaped at a forged
# sentinel has no matching frame yet. This narrows the forge window to a test
# file that prints BOTH lines deliberately — it does not close it, and the
# source-grep cell remains the primary control. `Tests run:` (per file) and
# `Files run:` (runner) do not collide.
if [ "${FILES}" -gt 0 ] && ! grep -q -e "^  Files run:    ${FILES}$" < "${LOG}" 2>/dev/null; then
    printf 'INCOMPLETE: the sentinel claims files=%s but %s carries no matching\n' "${FILES}" "${LOG}"
    printf '            "  Files run:    %s" frame from the runner — the run did not reach its summary.\n' "${FILES}"
    exit "${EX_NOT_A_PASS}"
fi

if [ "${FILES}" -eq 0 ]; then
    printf 'NOT A PASS: the run completed over ZERO test files (%s).\n' "${LOG}"
    printf '            Nothing was verified — a vacuous run is not a green one.\n'
    exit "${EX_NOT_A_PASS}"
fi

if [ "${MIN_FILES}" -gt 0 ] && [ "${FILES}" -lt "${MIN_FILES}" ]; then
    printf 'NOT A PASS: the run completed over only %s test files, fewer than the %s required (%s).\n' \
        "${FILES}" "${MIN_FILES}" "${LOG}"
    printf '            The runner reached its end, so this is a DISCOVERY shortfall, not a\n'
    printf '            truncation: a partial checkout or an unreadable tests/ dir produces a\n'
    printf '            smaller run that is well-formed and entirely green.\n'
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
    none)
        # The runner emits this when its glob found no test files at all. It is
        # self-describing on purpose: a naive consumer grepping `status=pass`
        # would otherwise get the exact misleading signal this script exists to
        # kill.
        printf 'NOT A PASS: the runner found no test files at all (%s).\n' "${LOG}"
        exit "${EX_NOT_A_PASS}"
        ;;
    *)
        printf 'INCOMPLETE: unrecognised status in sentinel of %s:\n  %s\n' "${LOG}" "${LAST_LINE}"
        exit "${EX_NOT_A_PASS}"
        ;;
esac

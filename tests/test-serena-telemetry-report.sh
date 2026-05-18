#!/usr/bin/env bash
# test-serena-telemetry-report.sh — Verify scripts/serena-telemetry-report.sh
# computes per-class follow-through % over a rolling window.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOL="${REPO_ROOT}/scripts/serena-telemetry-report.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env
mkdir -p "${HOME}/.claude"
TELEM="${HOME}/.claude/.serena-nudge-telemetry"

# Synthetic dataset within the last day:
#  10 grep_extension nudges, 5 followups → 50%
#   4 read_large_source observations, 1 followup → 25%
#   2 glob_definition_hunt observations, 0 followups → 0%
NOW="$(date +%s)"
i=1
while [ "${i}" -le 10 ]; do
    printf '%d\ttok-X\t%d\tnudge\tword_boundary\tgrep_extension\n' "$((NOW - i*60))" "${i}" >>"${TELEM}"
    if [ "${i}" -le 5 ]; then
        printf '%d\ttok-X\t%d\tfollowup\tword_boundary\tfind_symbol\n' "$((NOW - i*60 + 30))" "${i}" >>"${TELEM}"
    fi
    i=$((i+1))
done
i=1
while [ "${i}" -le 4 ]; do
    printf '%d\ttok-X\t%d\tobserve\tread_large_source\tsrc/big.ts\n' "$((NOW - i*30))" "$((100+i))" >>"${TELEM}"
    if [ "${i}" -eq 1 ]; then
        printf '%d\ttok-X\t%d\tfollowup\tread_large_source\tget_symbols_overview\n' "$((NOW - i*30 + 30))" "$((100+i))" >>"${TELEM}"
    fi
    i=$((i+1))
done
i=1
while [ "${i}" -le 2 ]; do
    printf '%d\ttok-X\t%d\tobserve\tglob_definition_hunt\t**/*Foo*\n' "$((NOW - i*45))" "$((200+i))" >>"${TELEM}"
    i=$((i+1))
done

out="$(bash "${TOOL}" 14 2>/dev/null)"

assert_contains "report includes word_boundary class" "word_boundary" "${out}"
assert_contains "word_boundary shows 50% follow-through" "50%" "${out}"
assert_contains "report includes read_large_source class" "read_large_source" "${out}"
assert_contains "read_large_source shows 25% follow-through" "25%" "${out}"
assert_contains "report includes glob_definition_hunt class" "glob_definition_hunt" "${out}"
assert_contains "glob_definition_hunt shows 0% follow-through" "0%" "${out}"

# --- v1.3.0 adoption section ---
# The synthetic dataset above contains 5 followups whose tool is find_symbol
# (legacy) and 1 followup whose tool is get_symbols_overview (legacy), with
# no v1.3.0 tool followups, so the v1.3.0 share is 0% and legacy total is 6.
assert_contains "report includes v1.3.0 adoption section heading" "v1.3.0 adoption" "${out}"
assert_contains "report lists find_declaration counter" "find_declaration:" "${out}"
assert_contains "report lists find_implementations counter" "find_implementations:" "${out}"
assert_contains "report lists get_diagnostics_for_file counter" "get_diagnostics_for_file:" "${out}"
assert_contains "report lists get_diagnostics_for_symbol counter" "get_diagnostics_for_symbol:" "${out}"
assert_contains "report emits v1.3.0 share metric" "v1.3.0 share:" "${out}"
assert_contains "report emits legacy total metric" "legacy total:" "${out}"

# Append v1.3.0-named followups to verify the share computes correctly.
# Three v1.3.0 followups (2 find_declaration + 1 find_implementations) vs
# the existing 6 legacy followups → share = 3 / (3 + 6) = 33%.
printf '%d\ttok-V\t300\tfollowup\tcamelcase\tfind_declaration\n' "$((NOW - 50))" >>"${TELEM}"
printf '%d\ttok-V\t301\tfollowup\tcamelcase\tfind_declaration\n' "$((NOW - 49))" >>"${TELEM}"
printf '%d\ttok-V\t302\tfollowup\tword_boundary\tfind_implementations\n' "$((NOW - 48))" >>"${TELEM}"
out_v13="$(bash "${TOOL}" 14 2>/dev/null)"
assert_contains "v1.3.0 share computes correctly with mixed v1.3.0 + legacy followups" "v1.3.0 share:               33%" "${out_v13}"
# The per-turn dedup section below already wipes & re-seeds telemetry, so
# leave the v1.3.0 appended rows in place — they'll be cleared there.

# --- Per-turn dedup: two nudges in the same turn count once ---
# Matches followthrough's (turn, matcher) idempotent dedup, so the rate is comparable.
rm -f "${TELEM}"
# Two grep_extension nudges in turn=42, one followup. Without dedup this would
# be 50% (1/2); with dedup it's 100% (1/1).
printf '%d\ttok-D\t42\tnudge\tword_boundary\tgrep_extension\n' "$((NOW - 100))" >>"${TELEM}"
printf '%d\ttok-D\t42\tnudge\tgrep_extension\tdotted_qualified\n' "$((NOW - 99))" >>"${TELEM}"
printf '%d\ttok-D\t42\tfollowup\tword_boundary\tfind_symbol\n' "$((NOW - 90))" >>"${TELEM}"
out_dedup="$(bash "${TOOL}" 14 2>/dev/null)"
assert_contains "per-turn dedup: 2 same-turn nudges count as 1 firing" "       1" "${out_dedup}"
assert_contains "per-turn dedup yields 100%" "100%" "${out_dedup}"

# --- Empty telemetry → graceful empty report ---
rm -f "${TELEM}"
out_empty="$(bash "${TOOL}" 14 2>/dev/null)"
assert_contains "empty telemetry produces a recognisable empty report" "no telemetry" "${out_empty}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0

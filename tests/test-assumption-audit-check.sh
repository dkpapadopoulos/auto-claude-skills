#!/usr/bin/env bash
# test-assumption-audit-check.sh — deterministic checks for the
# assumption-audit evidence-ceiling checker. Bash 3.2 compatible.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-assumption-audit-check.sh ==="

CHECKER="${SCRIPT_DIR}/../scripts/assumption-audit-check.sh"
FIX="${SCRIPT_DIR}/fixtures/assumption-audit"

assert_file_exists "checker script exists" "${CHECKER}"

/bin/bash "${CHECKER}" "${FIX}/compliant.md" >/dev/null 2>&1
assert_equals "compliant ledger must exit 0" "0" "$?"

out="$(/bin/bash "${CHECKER}" "${FIX}/grade-inflated.md" 2>&1)"
rc=$?
assert_equals "expert_judgment claiming grade A must exit 1" "1" "${rc}"
assert_contains "must print VIOLATION line" "VIOLATION" "${out}"
assert_contains "must name the ceiling rule" "ceiling" "${out}"

/bin/bash "${CHECKER}" "${FIX}/missing-threshold.md" >/dev/null 2>&1
assert_equals "fragile row without threshold must exit 1" "1" "$?"

/bin/bash "${CHECKER}" "${FIX}/no-ledger.md" >/dev/null 2>&1
assert_equals "doc without Assumption Ledger section must exit 1" "1" "$?"

/bin/bash "${CHECKER}" "${FIX}/bad-source-ref.md" >/dev/null 2>&1
assert_equals "A/B row citing non-grepping local literal must exit 1" "1" "$?"

/bin/bash "${CHECKER}" "${FIX}/does-not-exist.md" >/dev/null 2>&1
assert_equals "missing file must fail open (exit 0)" "0" "$?"

/bin/bash "${CHECKER}" "${FIX}/lowercase-importance.md" >/dev/null 2>&1
assert_equals "non-uppercase (high) fragile row without threshold must exit 1" "1" "$?"

print_summary
exit $?

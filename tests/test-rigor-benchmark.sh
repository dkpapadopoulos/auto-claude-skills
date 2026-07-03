#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-rigor-benchmark.sh ==="

RB="${PROJECT_ROOT}/scripts/rigor-benchmark.sh"
assert_file_exists "rigor-benchmark.sh exists" "${RB}"
assert_file_exists "dev manifest exists" "${PROJECT_ROOT}/tests/fixtures/rigor-benchmark/dev/manifest.jsonl"
assert_file_exists "held-out manifest exists" "${PROJECT_ROOT}/tests/fixtures/rigor-benchmark/held-out/manifest.jsonl"
assert_file_exists "benchmark README (integrity rules)" "${PROJECT_ROOT}/tests/fixtures/rigor-benchmark/README.md"

readme="$(cat "${PROJECT_ROOT}/tests/fixtures/rigor-benchmark/README.md" 2>/dev/null)"
assert_contains "README states never-delete rule" "deprecate" "${readme}"
assert_contains "README states independent held-out source" "different codebase" "${readme}"
assert_contains "README discloses limitations" "Limitations" "${readme}"
assert_contains "README discloses held-out is seeded-synthetic" "seeded-synthetic" "${readme}"

# Scorer runs the adequacy mechanism over the dev split and reports metrics.
out="$(bash "${RB}" --mechanism adequacy --split dev 2>/dev/null)"
assert_contains "reports recall" "recall=" "${out}"
assert_contains "reports control precision" "control_precision=" "${out}"
# The seeded untested-new-code case MUST be caught by the adequacy gate.
assert_contains "adequacy catches untested-new-code" "PASS untested-new-code-01" "${out}"
# The adequate-clean control MUST NOT be flagged (precision).
assert_contains "adequacy passes clean control" "PASS adequate-clean-01" "${out}"
# Spec requires four metrics: recall, control precision, incremental recall over the
# cheapest baseline, and cost per mechanism.
assert_contains "reports incremental recall" "incremental_recall=" "${out}"
assert_contains "reports cost seconds" "cost_seconds=" "${out}"
assert_contains "reports token cost" "tokens=0" "${out}"

# Held-out split honesty: no fabricated "external:" source labels remain.
held_manifest="$(cat "${PROJECT_ROOT}/tests/fixtures/rigor-benchmark/held-out/manifest.jsonl" 2>/dev/null)"
case "${held_manifest}" in
  *'"source":"external:'*) _record_fail "held-out manifest has no fabricated external source" "found external: label" ;;
  *) _record_pass "held-out manifest has no fabricated external source" ;;
esac
assert_contains "held-out manifest labels sources seeded-synthetic" '"source":"seeded-synthetic"' "${held_manifest}"

# Held-out split has a structurally-different partial-coverage boundary case (not
# another all-zero/all-covered clone) and the adequacy mechanism correctly flags it.
held_out="$(bash "${RB}" --mechanism adequacy --split held-out 2>/dev/null)"
assert_contains "held-out has partial-coverage boundary case" "partial-coverage-boundary-01" "${held_manifest}"
assert_contains "adequacy catches partial-coverage boundary case" "PASS partial-coverage-boundary-01" "${held_out}"

print_summary
exit $?

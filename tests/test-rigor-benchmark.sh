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

# Scorer runs the adequacy mechanism over the dev split and reports metrics.
out="$(bash "${RB}" --mechanism adequacy --split dev 2>/dev/null)"
assert_contains "reports recall" "recall=" "${out}"
assert_contains "reports control precision" "control_precision=" "${out}"
# The seeded untested-new-code case MUST be caught by the adequacy gate.
assert_contains "adequacy catches untested-new-code" "PASS untested-new-code-01" "${out}"
# The adequate-clean control MUST NOT be flagged (precision).
assert_contains "adequacy passes clean control" "PASS adequate-clean-01" "${out}"

print_summary
exit $?

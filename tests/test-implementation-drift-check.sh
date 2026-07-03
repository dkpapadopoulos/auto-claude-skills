#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-implementation-drift-check.sh ==="

SKILL="${PROJECT_ROOT}/skills/implementation-drift-check/SKILL.md"
assert_file_exists "drift-check SKILL.md exists" "${SKILL}"
skill="$(cat "${SKILL}" 2>/dev/null)"
assert_contains "references gate-gaming finding" "gate-gaming" "${skill}"
assert_contains "references coverage_adequacy_status finding" "coverage_adequacy_status" "${skill}"

print_summary
exit $?

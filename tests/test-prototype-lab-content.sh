#!/usr/bin/env bash
# test-prototype-lab-content.sh — guards prototype-lab's load-bearing contract: the
# three comparable variants and the MANDATORY Human Validation Plan (the safety element
# that keeps a prototype comparison from being mistaken for a validated decision).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-prototype-lab-content.sh ==="

SKILL="${PROJECT_ROOT}/skills/prototype-lab/SKILL.md"
assert_file_exists "prototype-lab SKILL.md exists" "${SKILL}"
skill="$(cat "${SKILL}" 2>/dev/null)"

assert_contains "frontmatter name field"          "name: prototype-lab"    "${skill}"
assert_contains "three-variant contract (A)"      "Variant A"              "${skill}"
assert_contains "three-variant contract (B)"      "Variant B"              "${skill}"
assert_contains "three-variant contract (C)"      "Variant C"              "${skill}"
assert_contains "comparison artifact present"     "Comparison"             "${skill}"
assert_contains "mandatory Human Validation Plan"  "Human Validation Plan" "${skill}"

print_summary

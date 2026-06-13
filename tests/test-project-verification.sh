#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-project-verification.sh ==="

SKILL="${PROJECT_ROOT}/skills/project-verification/SKILL.md"
REF="${PROJECT_ROOT}/skills/project-verification/references/discovery-ladder.md"

assert_file_exists "SKILL.md exists" "${SKILL}"
assert_file_exists "discovery-ladder ref exists" "${REF}"

skill="$(cat "${SKILL}" 2>/dev/null)"
assert_contains "frontmatter phase REVIEW"     "phase: REVIEW"            "${skill}"
assert_contains "frontmatter role domain"      "role: domain"             "${skill}"
assert_contains "substrate is local in v1"     "local"                    "${skill}"
assert_contains "evidence path documented"     ".skill-project-verified-" "${skill}"
assert_contains "deterministic-first ladder"   "deterministic"            "${skill}"
assert_contains "evidence is advisory only"    "not a trust boundary"     "${skill}"

ref="$(cat "${REF}" 2>/dev/null)"
assert_contains "ladder rung .verify.yml"      ".verify.yml"              "${ref}"
assert_contains "ladder rung manifests"        "pyproject.toml"           "${ref}"
assert_contains "ladder rung CLAUDE.md table"  "## Commands"              "${ref}"
assert_contains "ambiguity prompts user"       "prompt"                   "${ref}"

print_summary
exit $?

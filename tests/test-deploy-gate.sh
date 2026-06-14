#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

section() {
    echo ""
    echo "--- $1 ---"
}

SKILL="$PROJECT_ROOT/skills/deploy-gate/SKILL.md"

section "Deploy Gate Skill Content"

# Frontmatter checks
assert_file_exists "SKILL.md exists" "$SKILL"
content="$(cat "$SKILL")"

assert_contains "has name field" "name: deploy-gate" "$content"
assert_contains "has role domain" "role: domain" "$content"
assert_contains "has phase SHIP" "phase: SHIP" "$content"
assert_contains "has priority 19" "priority: 19" "$content"
assert_contains "precedes openspec-ship" "openspec-ship" "$content"
assert_contains "requires verification" "verification-before-completion" "$content"

# Content checks
assert_contains "has CI status check" "CI Status" "$content"
assert_contains "has WIP check" "WIP" "$content"
assert_contains "has deploy-checklist.yml override" ".deploy-checklist.yml" "$content"
assert_contains "has output table" "Deploy Gate Results" "$content"
assert_not_contains "no kubectl reference" "kubectl" "$content"

section "deploy-gate CI check fails closed on absent CI"
assert_contains "deploy-gate treats absent CI as non-pass" "absent" "$content"
assert_contains "deploy-gate has empty-result guard" 'GATE FAIL: no CI checks' "$content"
assert_contains "deploy-gate accepts local verification evidence" ".skill-project-verified-" "$content"

print_summary
exit $?

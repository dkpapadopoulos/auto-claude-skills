#!/usr/bin/env bash
# test-capture-knowledge-content.sh — guards capture-knowledge's load-bearing sections:
# the gated capture criteria, the when-NOT carve-out, and the Safety section (this skill
# writes to the committed .claude/knowledge/ base — a memory-poisoning surface, so its
# human-gating/safety guidance must not silently disappear).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-capture-knowledge-content.sh ==="

SKILL="${PROJECT_ROOT}/skills/capture-knowledge/SKILL.md"
assert_file_exists "capture-knowledge SKILL.md exists" "${SKILL}"
skill="$(cat "${SKILL}" 2>/dev/null)"

assert_contains "frontmatter name field"        "name: capture-knowledge" "${skill}"
assert_contains "gated capture criteria present" "Capture criteria"       "${skill}"
assert_contains "when-NOT carve-out present"     "When NOT to use"        "${skill}"
assert_contains "procedure present"              "## Procedure"           "${skill}"
assert_contains "safety section present"         "## Safety"              "${skill}"

print_summary

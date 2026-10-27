#!/usr/bin/env bash
# test-authorial-judgment-content.sh — guards the load-bearing SKILL.md content so a
# future edit can't silently gut the §1 hard gate, the six moves, or the scope carve-out.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-authorial-judgment-content.sh ==="

SKILL="${PROJECT_ROOT}/skills/authorial-judgment/SKILL.md"
assert_file_exists "authorial-judgment SKILL.md exists" "${SKILL}"
skill="$(cat "${SKILL}" 2>/dev/null)"

assert_contains "frontmatter name field"          "name: authorial-judgment"          "${skill}"

# The §1 hard gate is the anti-fabrication discipline — its removal would gut the skill.
assert_contains "hard gate present"               "real texture or clean prose"        "${skill}"
assert_contains "gate forbids fabrication"        "Never"                              "${skill}"
assert_contains "gate: keep prose clean when no real texture" "keep the prose clean"   "${skill}"

# The six distilled moves — anchor the first and last so reordering/trimming is caught.
assert_contains "move: authorial position not persona" "Authorial position, not persona" "${skill}"
assert_contains "move: AI-inversion refusal"           "AI-inversion refusal"            "${skill}"

# Scope carve-out — the skill must stay silent on reference/procedural/code writing.
assert_contains "when-NOT scope carve-out"        "When NOT to use"                    "${skill}"

# Merged taxonomy reference must remain reachable.
assert_contains "points to merged red-flag taxonomy" "references/red-flags.md"         "${skill}"
REF="${PROJECT_ROOT}/skills/authorial-judgment/references/red-flags.md"
assert_file_exists "red-flags.md reference exists"   "${REF}"

# 2026-10-27 revision: scope by use, minimum effective edit, genre conditional, conditional move 6.
assert_contains "description states triggers, not workflow" "Use when a draft a reader will judge the writer by" "${skill}"
assert_contains "minimum effective edit"                 "comes back near-unchanged"        "${skill}"
assert_contains "a requested change is licensed by the author, not the audience" "the author's request is a reason" "${skill}"
assert_contains "cover-letter conditional"              "If the draft is a cover letter"   "${skill}"
assert_contains "move 6 tie-break keeps the author"      "keep the author's version"        "${skill}"
assert_not_contains "canned blind-spot sentence removed" "half the problem"                 "${skill}"
assert_not_contains "procedural rationale softened"      "certain and literal"              "${skill}"

print_summary
exit $?

#!/usr/bin/env bash
# test-readme-inventory.sh — the README's skill inventory must be DERIVED, not written.
#
# Why this exists: README.md claimed "18 skills" while skills/ held 23, and the
# Bundled Skills table was missing 5 owned skills. A hand-maintained count buys
# about two skills of accuracy before it drifts again, and it had already drifted.
#
# PAIRED with the gate-anchor lesson: assert in BOTH directions and carry a count
# floor. A one-directional assertion ("every table row is a real skill") stays
# green when rows go missing, which is exactly how this drifted; the reverse
# alone stays green when a stale row survives a skill deletion.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-readme-inventory.sh ==="

README="${PROJECT_ROOT}/README.md"
assert_file_exists "README.md exists" "${README}"

# --- Authority 1: the filesystem -------------------------------------------
dir_count="$(find "${PROJECT_ROOT}/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"

# --- Authority 2: the README's own prose ------------------------------------
prose_count="$(grep -oE 'This plugin ships [0-9]+ skills' "${README}" 2>/dev/null | grep -oE '[0-9]+' | head -1)"
[ -n "${prose_count}" ] || prose_count="(absent)"

assert_equals "README prose count equals skills/ directory count" \
    "${dir_count}" "${prose_count}"

# Count floor — a derived assertion that both sides compute to zero would pass
# vacuously. This repo has had >=20 skills since 2026-06; anything under 15
# means the population query broke, not that skills were deleted.
if [ "${dir_count}" -ge 15 ] 2>/dev/null; then
    _record_pass "skills/ population is sane (${dir_count} >= 15)"
else
    _record_fail "skills/ population implausible (${dir_count})" \
        "The discovery query likely broke — a real deletion of that scale would be deliberate."
fi

# --- Direction 1: every skill directory appears in the README table ---------
missing=0
while IFS= read -r d; do
    [ -z "${d}" ] && continue
    name="$(basename "${d}")"
    if ! grep -qF "skills/${name}/SKILL.md" "${README}" 2>/dev/null; then
        _record_fail "README table is missing skill: ${name}" \
            "Add a row linking skills/${name}/SKILL.md, or remove the skill."
        missing=$((missing + 1))
    fi
done <<EOF
$(find "${PROJECT_ROOT}/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
EOF
[ "${missing}" -eq 0 ] && _record_pass "every skills/ directory has a README row"

# --- Direction 2: every README row points at a real skill directory ---------
# Guards the reverse drift: a skill is deleted or renamed and its row lingers.
stale=0
while IFS= read -r name; do
    [ -z "${name}" ] && continue
    if [ ! -d "${PROJECT_ROOT}/skills/${name}" ]; then
        _record_fail "README row references a non-existent skill: ${name}" \
            "Remove the stale row, or restore skills/${name}/."
        stale=$((stale + 1))
    fi
done <<EOF
$(grep -oE 'skills/[a-z0-9-]+/SKILL\.md' "${README}" 2>/dev/null | sed 's|skills/||; s|/SKILL\.md||' | sort -u)
EOF
[ "${stale}" -eq 0 ] && _record_pass "every README row points at a real skill directory"

print_summary
exit $?

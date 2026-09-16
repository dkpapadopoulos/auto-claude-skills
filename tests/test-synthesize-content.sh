#!/usr/bin/env bash
# test-synthesize-content.sh — pins the load-bearing sentences of skills/synthesize/SKILL.md.
# Change: cross-family-second-opinion. Each needle is a spec requirement, not style.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-synthesize-content.sh ==="
F="${PROJECT_ROOT}/skills/synthesize/SKILL.md"

if [ ! -f "${F}" ]; then
    _record_fail "skills/synthesize/SKILL.md exists" "missing ${F}"
    print_summary
    exit 1
fi
_record_pass "skills/synthesize/SKILL.md exists"

# needle|label pairs, heredoc-fed (never pipe — subshell would lose the counters)
while IFS='|' read -r needle label; do
    [ -n "${needle}" ] || continue
    if grep -qiF -- "${needle}" "${F}"; then
        _record_pass "synthesize: ${label}"
    else
        _record_fail "synthesize: ${label}" "needle not found: ${needle}"
    fi
done <<'NEEDLES'
without forcing consensus|no forced consensus
never vote|contradictions decided on evidence, never by vote
re-examine|unique-to-one claims re-examined against source
panel limitation|uncovered gaps flagged as panel limitation
unresolved disagreements|disagreements surfaced to the caller
data to flag|embedded instructions treated as data
never as instructions|embedded instructions never followed
exceeding the original prompt|violation flagging present
Adapted from patforna/core-skills (MIT)|attribution present
NEEDLES


# --- C4: the input-evidence contract -------------------------------------------
# The spec requires a merge only when inputs are complete, attributable to DISTINCT
# participants, associated with THIS request, and not superseded -- and is explicit
# that a marker asserting results exist, or the mere presence of files, satisfies none
# of them. Before this, Inputs accepted "panel scratch files or inline text", which is
# exactly the file-presence standard the spec rejects.
_sy="$(cat "${PROJECT_ROOT}/skills/synthesize/SKILL.md" 2>/dev/null || true)"
assert_contains "C4: names the completeness property"   "Complete"        "${_sy}"
assert_contains "C4: requires distinct participants"    "distinct participants" "${_sy}"
assert_contains "C4: requires association with this request" "Associated with this request" "${_sy}"
assert_contains "C4: requires inputs not superseded"    "Not superseded"  "${_sy}"
assert_contains "C4: rejects a marker as evidence"      "marker asserting that results exist" "${_sy}"
assert_contains "C4: rejects mere file presence"        "mere presence of files" "${_sy}"
# The refusal must be explicit, and must forbid filling the gap -- a synthesis of one
# real perspective and one invented one reads identically to a real one.
assert_contains "C4: refuses rather than improvising"   "Do not fill the gap" "${_sy}"
# Byte-identical perspectives are one perspective; distinctness is about content, not count.
assert_contains "C4: identical perspectives fail distinctness" "byte-identical" "${_sy}"

# The flag must be PRESERVED (spec) and must not be mistaken for provenance (design.md's
# rejected dissent: the flag blocks model invocation and nothing more).
# Assert on the FRONTMATTER, not the file. The needle is also a substring of the
# assurance-boundary prose added alongside it, so checking the whole file is satisfied
# by that prose: measured, deleting the real frontmatter key left this suite 20/20.
# The spec makes preserving the restriction a MUST, so the check has to look where the
# restriction actually lives.
_sy_fm="$(awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{exit} f' "${PROJECT_ROOT}/skills/synthesize/SKILL.md" 2>/dev/null || true)"
assert_contains "C4: disable-model-invocation preserved (frontmatter)" \
    "disable-model-invocation: true" "${_sy_fm}"
assert_contains "C4: states the flag is not provenance"  "NOT provenance"  "${_sy}"

print_summary

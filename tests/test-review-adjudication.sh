#!/usr/bin/env bash
# test-review-adjudication.sh — issue #205 deterministic leg.
#
# Asserts that skills/agent-team-review/SKILL.md carries a lead-side procedure
# for adjudicating an INDIVIDUAL finding: reproduce with exactly one fault
# injected, and require the paired configurations to disagree before either
# rejecting or accepting it.
#
# TWO authorities, deliberately, and a count floor. The fixture
# tests/fixtures/agent-team-review/adjudication/required-clauses.txt carries the
# needles; this file independently hardcodes the issue-#205 anchors and asserts
# the fixture still contains them, and pins the needle count. With only a
# fixture, deleting a needle silently deletes its own assertion — measured on
# the sibling dispatch-brief gate, which ran fully green with two needles
# removed and the matching clauses inverted.
#
# EVERY loop below is fed by a HEREDOC, never by a pipe. A piped `while` runs in
# a SUBSHELL, so _record_pass/_record_fail inside it mutate counters that die
# with the subshell: the run prints FAIL and still exits 0 reporting "All tests
# passed". Measured on the first cut of this file — mutating one clause out of
# SKILL.md printed one FAIL and the summary still read 9/9, exit 0.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-review-adjudication.sh ==="

SKILL="${PROJECT_ROOT}/skills/agent-team-review/SKILL.md"
FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/agent-team-review/adjudication"
CLAUSES_FILE="${FIXTURE_DIR}/required-clauses.txt"
SEEDED_FILE="${FIXTURE_DIR}/seeded-findings.md"

assert_file_exists "pinned eval set: required-clauses.txt present" "${CLAUSES_FILE}"
assert_file_exists "pinned eval set: seeded-findings.md present"   "${SEEDED_FILE}"

# --- Authority 2: the anchors this issue turns on, hardcoded here ------------
# If the fixture loses one of these, the gate fails rather than quietly
# shrinking. This is not a copy of the fixture — it is the subset without which
# the procedure is no longer the procedure.
ANCHORS="Change exactly one thing, and build a pair that COULD disagree
an upstream fail-closed gate masks a downstream fall-open one
you have not refuted the finding, you have only failed to trigger it
Never write to the shared working tree while adjudicating"

CLAUSES=""
if [ -f "${CLAUSES_FILE}" ]; then
    CLAUSES="$(grep -v '^[[:space:]]*#' "${CLAUSES_FILE}" | grep -v '^[[:space:]]*$')"
fi

SKILL_TEXT=""
[ -f "${SKILL}" ] && SKILL_TEXT="$(cat "${SKILL}")"
assert_not_empty "SKILL.md is readable" "${SKILL_TEXT}"

while IFS= read -r a; do
    [ -n "${a}" ] || continue
    if printf '%s\n' "${CLAUSES}" | grep -qF -- "${a}"; then
        _record_pass "fixture still carries anchor: ${a}"
    else
        _record_fail "fixture still carries anchor: ${a}" "needle missing from required-clauses.txt"
    fi
done <<EOF
${ANCHORS}
EOF

# --- Count floor: a deleted needle must not shrink the assertion set --------
CLAUSE_COUNT=0
if [ -n "${CLAUSES}" ]; then
    CLAUSE_COUNT="$(printf '%s\n' "${CLAUSES}" | wc -l | tr -d ' ')"
fi
# Floor equals the needle count at the time this gate landed. Adding needles is
# safe; removing one drops below the floor and fails.
assert_equals "needle count has not shrunk" "25" "${CLAUSE_COUNT}"

# --- The needles must actually appear in the skill --------------------------
while IFS= read -r c; do
    [ -n "${c}" ] || continue
    if printf '%s\n' "${SKILL_TEXT}" | grep -qF -- "${c}"; then
        _record_pass "skill states: ${c}"
    else
        _record_fail "skill states: ${c}" "clause absent from skills/agent-team-review/SKILL.md"
    fi
done <<EOF
${CLAUSES}
EOF

# --- The procedure must be REACHED from the synthesis step ------------------
# A section nobody is routed to is prose. Step 4 of Lead Synthesis must send the
# lead here before a finding is decided.
assert_contains "synthesis routes each finding through the adjudication step" \
    "Adjudicate per §4a every finding you are about to accept or reject" "${SKILL_TEXT}"

# --- The seeded set must keep both populations ------------------------------
# Recall bought by accepting everything is the failure mode the FALSE cells
# exist to catch, so the set must not quietly lose them.
SEEDED=""
[ -f "${SEEDED_FILE}" ] && SEEDED="$(cat "${SEEDED_FILE}")"
_real_n="$(printf '%s\n' "${SEEDED}" | grep -c '^## REAL-' || true)"
_false_n="$(printf '%s\n' "${SEEDED}" | grep -c '^## FALSE-' || true)"
assert_equals "seeded set keeps 3 real-but-confounded findings" "3" "${_real_n}"
assert_equals "seeded set keeps 3 genuinely false findings"     "3" "${_false_n}"
assert_contains "seeded set states its measured provenance" \
    "MEASURED against the real" "${SEEDED}"
assert_contains "seeded set names the REAL-1 clause in its bar" \
    "REAL-1 classified REAL" "${SEEDED}"

print_summary
exit $?

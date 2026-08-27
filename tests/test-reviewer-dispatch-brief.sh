#!/usr/bin/env bash
# test-reviewer-dispatch-brief.sh — issue #204 deterministic leg.
#
# Asserts that skills/agent-team-review/SKILL.md's dispatch brief carries the
# clauses the observed failures require, and that the lead-side collection
# protocol exists as a MECHANISM rather than as an asserted outcome.
#
# Why per-lens-block and not whole-file: a reviewer subagent sees ONLY its own
# prompt. A clause present once in the protocol prose reaches no reviewer, and a
# whole-file needle cannot tell "in all four prompts" from "in one of them".
# Needles come from tests/fixtures/agent-team-review/dispatch-brief/ (pinned eval
# set, never delete) rather than being inlined here, so the fixture stays the
# single authority for the A/B contract.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-reviewer-dispatch-brief.sh ==="

SKILL="${PROJECT_ROOT}/skills/agent-team-review/SKILL.md"
FIXTURE_DIR="${PROJECT_ROOT}/tests/fixtures/agent-team-review/dispatch-brief"
CLAUSES_FILE="${FIXTURE_DIR}/required-clauses.txt"
RANGE_FILE="${FIXTURE_DIR}/pinned-range.txt"

assert_file_exists "pinned eval set: required-clauses.txt present" "${CLAUSES_FILE}"
assert_file_exists "pinned eval set: pinned-range.txt present" "${RANGE_FILE}"

# The behavioral leg is only comparable across runs if the subject is pinned.
if [ -f "${RANGE_FILE}" ]; then
    RANGE_CONTENT="$(cat "${RANGE_FILE}")"
    assert_contains "pinned range: base sha recorded" "base=" "${RANGE_CONTENT}"
    assert_contains "pinned range: head sha recorded" "head=" "${RANGE_CONTENT}"
    assert_contains "pinned range: unprompted delivery metric named" \
        "unprompted delivery rate" "${RANGE_CONTENT}"
fi

# --- Load the needles -------------------------------------------------------
# Read into a newline-delimited string, iterated with `while IFS= read -r`.
# NEVER `for c in $CLAUSES`: under zsh an unquoted scalar does not word-split
# (CLAUDE.md), and every needle here contains spaces anyway.
CLAUSES=""
if [ -f "${CLAUSES_FILE}" ]; then
    CLAUSES="$(grep -v '^[[:space:]]*#' "${CLAUSES_FILE}" | grep -v '^[[:space:]]*$')"
fi

CLAUSE_COUNT=0
if [ -n "${CLAUSES}" ]; then
    CLAUSE_COUNT="$(printf '%s\n' "${CLAUSES}" | wc -l | tr -d ' ')"
fi

# Red control: an empty or unreadable fixture would make every per-lens
# assertion below vacuously pass, which is exactly the shape this test exists to
# prevent. Floor is the 4 issue-#204 clauses + the 3 safety clauses = 7 lines.
if [ "${CLAUSE_COUNT}" -ge 7 ]; then
    _record_pass "clause fixture non-vacuous (${CLAUSE_COUNT} needles)"
else
    _record_fail "clause fixture non-vacuous" \
        "expected >= 7 needles, got ${CLAUSE_COUNT} — assertions below prove nothing"
fi

# --- Per-lens prompt blocks -------------------------------------------------
# Range starts at this lens's `name:` line and STOPS at the next `name: "` line
# or the next top-level `## ` heading (the last lens block would otherwise run to
# EOF and absorb the Red Flags / Verification prose, so a clause misplaced there
# would false-pass). Anchored on `^\s*name:` so the sibling `team_name:` line
# cannot terminate the range early.
_lens_block() {
    awk -v lens="$1" '
        $0 ~ "^[[:space:]]*name: \"" lens "\"" { f=1; next }
        f && /^[[:space:]]*name: "/ { exit }
        f && /^## / { exit }
        f
    ' "${SKILL}"
}

# Literal (not regex) containment: needles carry backticks and hyphens.
_block_has() {
    printf '%s\n' "$2" | grep -qF -- "$1"
}

for lens in security-reviewer quality-reviewer spec-reviewer adversarial-reviewer; do
    BLOCK="$(_lens_block "${lens}")"
    if [ -z "${BLOCK}" ]; then
        _record_fail "${lens}: prompt block extracted" \
            "non-empty block — anchors moved, clause assertions for this lens prove nothing"
        continue
    fi
    _record_pass "${lens}: prompt block extracted"

    while IFS= read -r needle; do
        [ -n "${needle}" ] || continue
        if _block_has "${needle}" "${BLOCK}"; then
            _record_pass "${lens}: carries clause [${needle}]"
        else
            _record_fail "${lens}: carries clause [${needle}]" \
                "needle absent from this lens prompt"
        fi
    done <<EOF
${CLAUSES}
EOF
done

# --- Lead-side collection protocol -----------------------------------------
# The Verification section already asserted the OUTCOME ("every spawned reviewer
# returned a finding set"). Issue #204's point is that no mechanism produced it.
SKILL_CONTENT="$(cat "${SKILL}")"

assert_contains "lead: idle is not a report" "Idle is not a report" "${SKILL_CONTENT}"
assert_contains "lead: a timeout is not a pass" "A timeout is not a pass" "${SKILL_CONTENT}"
assert_contains "lead: errored reviewer is re-dispatched, not counted" \
    "never count it toward coverage" "${SKILL_CONTENT}"
assert_contains "lead: check the tree before re-dispatching" \
    "git status" "${SKILL_CONTENT}"
assert_contains "lead: chase twice before writing a reviewer off" \
    "at least twice" "${SKILL_CONTENT}"
assert_contains "lead: undelivered reviewer downgrades the verdict" \
    "could-not-review" "${SKILL_CONTENT}"

# --- Hard no-regression clauses (issue #204 safety section) -----------------
assert_contains "lead: silent-drop red flag" \
    "**Silent drop:**" "${SKILL_CONTENT}"
assert_contains "lead: coverage counts reports, not spawns" \
    "Coverage counts reports delivered, not agents spawned" "${SKILL_CONTENT}"

assert_contains "no-regression: doubt-theater red flag retained" \
    "doubt theater" "${SKILL_CONTENT}"
assert_contains "no-regression: APPROVE verdict contract retained" \
    "Before emitting an APPROVE verdict" "${SKILL_CONTENT}"
assert_contains "no-regression: reviewers stay read-only in the shared tree" \
    "Never write to the shared working tree" "${SKILL_CONTENT}"

print_summary

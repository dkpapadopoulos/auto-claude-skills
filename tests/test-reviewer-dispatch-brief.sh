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
#
# TWO authorities, deliberately. The fixture
# tests/fixtures/agent-team-review/dispatch-brief/required-clauses.txt carries the
# needles; this file independently hardcodes the issue-#204 clause anchors and
# asserts the fixture still contains them. A single authority was the first cut
# and it leaked: with only a count floor, deleting two needles from the fixture
# AND inverting the matching clauses in all four prompts ran fully green (49/49),
# because a deleted needle silently deletes its own assertion.
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
    # The metric must be able to SEE the capability the change grants. `git status
    # --porcelain` cannot observe a worktree registered under .git/worktrees/, so a
    # main-tree-only metric is blind to reviewer worktree leaks.
    assert_contains "pinned range: metric covers worktree registration, not just the main tree" \
        "git worktree list" "${RANGE_CONTENT}"
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

_fixture_has() {
    printf '%s\n' "${CLAUSES}" | grep -qFx -- "$1"
}

# --- Control 1: the fixture still carries every issue-#204 clause anchor ----
# Hardcoded HERE, not read from the fixture: a floor computed from the fixture's
# own contents cannot notice the fixture shrinking. Matched with `grep -Fx` so a
# needle must be present verbatim as a whole line, not merely as a substring of
# some other needle.
#
# Keep this list in step with THE FIXTURE, not with issue #204. Tracking the issue
# is what opened the second leak: the anchors covered #204's own clauses while the
# fixture grew past them, so the three post-#204 needles (`mktemp -d`, the
# subject-confirmation rule, the VERIFIED/INFERRED rule) were unanchored — and with
# the floor set to the ANCHOR count rather than the fixture count, deleting exactly
# those three landed on the floor and ran 82/82 green. That green run reinstated the
# fixed-path worktree collision in all four prompts. Every needle is anchored now,
# and the floor below equals the fixture size, so Control 2 backstops rather than
# duplicating Control 1.
_require_needle() {
    if _fixture_has "$1"; then
        _record_pass "fixture carries required anchor [$1]"
    else
        _record_fail "fixture carries required anchor [$1]" \
            "needle missing from required-clauses.txt — deleting a needle deletes its per-lens assertion"
    fi
}
_require_needle "Time-box yourself to 15 minutes"
_require_needle "REPORT EVEN IF INCOMPLETE"
_require_needle "Silence is not a pass"
_require_needle "Deliver unprompted"
_require_needle "SendMessage to \`main\`"
_require_needle "git worktree add --detach"
_require_needle "Never write to the shared working tree"
_require_needle "Read-only in the shared tree"
_require_needle "do NOT modify any files"
_require_needle "do not manufacture findings"
_require_needle "VERIFIED by running from what you INFERRED by reading"
_require_needle "mktemp -d"
_require_needle "Confirm your worktree matches the subject"
_require_needle "Review range: {base_sha}..{head_sha}"

# --- Control 2: non-vacuity floor ------------------------------------------
# Secondary to Control 1 (which a shrinking fixture trips first), but it also
# catches an unreadable or wholly-commented fixture, where the per-lens loop
# would iterate zero needles and every clause assertion would silently vanish.
# The floor MUST equal the fixture's needle count, never the anchor count. Any
# headroom between them is a set of needles that can be deleted without tripping
# either control — which is exactly how the second leak opened. Raise both together
# when adding a needle.
if [ "${CLAUSE_COUNT}" -ge 14 ]; then
    _record_pass "clause fixture non-vacuous (${CLAUSE_COUNT} needles)"
else
    _record_fail "clause fixture non-vacuous" \
        "expected >= 14 needles, got ${CLAUSE_COUNT} — assertions below prove nothing"
fi

# --- Discover the lens population -------------------------------------------
# Derived from SKILL.md, NEVER hardcoded: a hardcoded list silently exempts a
# fifth lens added later, which is the population-enumeration vacuity this repo's
# fixture/content-coverage gates exist to prevent. Scoped to the spawn-template
# section so an unrelated `name:` elsewhere cannot enter the population.
LENSES="$(awk '
    /^## Reviewer Spawn Templates/ { in_s=1; next }
    in_s && /^## / { exit }
    in_s && match($0, /^[[:space:]]*name: "[^"]+"/) {
        line=$0; sub(/^[[:space:]]*name: "/, "", line); sub(/".*$/, "", line); print line
    }
' "${SKILL}")"

LENS_COUNT=0
if [ -n "${LENSES}" ]; then
    LENS_COUNT="$(printf '%s\n' "${LENSES}" | wc -l | tr -d ' ')"
fi

# Floor matches the four lenses the skill's Reviewer Composition table defines.
if [ "${LENS_COUNT}" -ge 4 ]; then
    _record_pass "lens population discovered (${LENS_COUNT} lenses)"
else
    _record_fail "lens population discovered" \
        "expected >= 4 lens prompts under '## Reviewer Spawn Templates', found ${LENS_COUNT}"
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

CONTRACT_REF=""
while IFS= read -r lens; do
    [ -n "${lens}" ] || continue
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

    # --- Control 3: the four Delivery Contract blocks must be IDENTICAL ------
    # Duplication into every prompt is the deliberate design (a subagent reads
    # only its own prompt), and its one cost is drift. Without this, a lens whose
    # contract was reworded still passes as long as it retains every needle.
    CONTRACT="$(printf '%s\n' "${BLOCK}" | awk '
        /^[[:space:]]*## Delivery Contract/ { f=1; next }
        f && /^[[:space:]]*## / { exit }
        f
    ')"
    if [ -z "${CONTRACT}" ]; then
        _record_fail "${lens}: Delivery Contract block extracted" "empty"
    elif [ -z "${CONTRACT_REF}" ]; then
        CONTRACT_REF="${CONTRACT}"
        _record_pass "${lens}: Delivery Contract block extracted (reference copy)"
    elif [ "${CONTRACT}" = "${CONTRACT_REF}" ]; then
        _record_pass "${lens}: Delivery Contract identical to the other lenses"
    else
        _record_fail "${lens}: Delivery Contract identical to the other lenses" \
            "this lens's contract has drifted from the reference copy"
    fi
done <<EOF
${LENSES}
EOF

# --- Lead-side collection protocol -----------------------------------------
# The Verification section already asserted the OUTCOME ("every spawned reviewer
# returned a finding set"). Issue #204's point is that no mechanism produced it.
#
# SCOPED to Protocol §3, not whole-file: these needles are generic enough that
# unrelated prose elsewhere in the skill would satisfy them, which would let the
# mechanism be relocated out of the protocol and still pass.
LEAD_BLOCK="$(awk '/^### 3\. Parallel Review/{f=1;next} f && /^### /{exit} f' "${SKILL}")"
if [ -z "${LEAD_BLOCK}" ]; then
    _record_fail "lead: Protocol §3 block extracted" \
        "non-empty block — heading moved, lead-side assertions below prove nothing"
else
    _record_pass "lead: Protocol §3 block extracted"
fi

assert_contains "lead: idle is not a report" "Idle is not a report" "${LEAD_BLOCK}"
assert_contains "lead: a timeout is not a pass" "A timeout is not a pass" "${LEAD_BLOCK}"
assert_contains "lead: errored reviewer is re-dispatched, not counted" \
    "never count it toward coverage" "${LEAD_BLOCK}"
# Both halves: spec requires `git status` AND `git log` before re-dispatch, and
# the anchor is the full sentence — a bare "git status" needle is satisfied by any
# unrelated future mention.
assert_contains "lead: check the tree before re-dispatching" \
    "Before re-dispatching anything, run \`git status\` and \`git log\`" "${LEAD_BLOCK}"
assert_contains "lead: chase twice before writing a reviewer off" \
    "at least twice" "${LEAD_BLOCK}"
# Anchored on the NEW sentence. `could-not-review` alone pre-existed this change
# in "## Record the Review Verdict", so a bare-token needle was satisfied by that
# fallback and pinned nothing — deleting this entire paragraph ran green.
assert_contains "lead: undelivered lens downgrades the verdict" \
    "Coverage is what was delivered, not what was spawned" "${LEAD_BLOCK}"
assert_contains "lead: undelivered lens routes to could-not-review" \
    "record \`--verdict could-not-review\`" "${LEAD_BLOCK}"
# The worktree capability this change grants leaks into the shared repo's
# .git/worktrees/, which the main-tree cleanliness check cannot see.
assert_contains "lead: reviewer worktrees are reaped" \
    "git worktree prune" "${LEAD_BLOCK}"

# --- Verification cites the mechanism --------------------------------------
# spec.md requires the outcome assertion to reference Protocol §3 rather than
# stand alone. That is the diff's headline claim, and nothing asserted it —
# deleting these lines ran fully green.
VERIF_BLOCK="$(awk '/^## Verification/{f=1;next} f && /^## /{exit} f' "${SKILL}")"
if [ -z "${VERIF_BLOCK}" ]; then
    _record_fail "verification block extracted" "non-empty block"
else
    _record_pass "verification block extracted"
fi
assert_contains "verification: outcome names its mechanism" \
    "Protocol §3 is the mechanism" "${VERIF_BLOCK}"
assert_contains "verification: undelivered lens is not APPROVE" \
    "\`could-not-review\`, not APPROVE" "${VERIF_BLOCK}"

# --- Hard no-regression clauses (issue #204 safety section) -----------------
SKILL_CONTENT="$(cat "${SKILL}")"
assert_contains "no-regression: doubt-theater red flag retained" \
    "doubt theater" "${SKILL_CONTENT}"
assert_contains "no-regression: APPROVE verdict contract retained" \
    "Before emitting an APPROVE verdict" "${SKILL_CONTENT}"
assert_contains "lead: silent-drop red flag" \
    "**Silent drop:**" "${SKILL_CONTENT}"
assert_contains "lead: coverage counts reports, not spawns" \
    "Coverage counts reports delivered, not agents spawned" "${SKILL_CONTENT}"

print_summary

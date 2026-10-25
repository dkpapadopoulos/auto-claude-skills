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

# §4a's reproduction commands moved to references/adjudication-worktree.md
# (re-attach budget); four needles live in their comments. The needle text is
# the core plus that one file, never all of references/, so a §4a clause moved
# into some other reference still fails.
WORKTREE_REF="$(dirname "${SKILL}")/references/adjudication-worktree.md"
SKILL_TEXT=""
[ -f "${SKILL}" ] && SKILL_TEXT="$(cat "${SKILL}")"
assert_not_empty "SKILL.md is readable" "${SKILL_TEXT}"
WORKTREE_TEXT=""
[ -f "${WORKTREE_REF}" ] && WORKTREE_TEXT="$(cat "${WORKTREE_REF}")"
assert_not_empty "references/adjudication-worktree.md is readable" "${WORKTREE_TEXT}"
NEEDLE_TEXT="${SKILL_TEXT}
${WORKTREE_TEXT}"

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
    if printf '%s\n' "${NEEDLE_TEXT}" | grep -qF -- "${c}"; then
        _record_pass "skill states: ${c}"
    else
        _record_fail "skill states: ${c}" "clause absent from skills/agent-team-review/SKILL.md and references/adjudication-worktree.md"
    fi
done <<EOF
${CLAUSES}
EOF

# --- The moved commands stay reachable and their rule stays in the core -----
SECTION_4A="$(awk '/^### 4a\./{f=1;next} f && /^#+ /{exit} f' "${SKILL}")"
assert_contains "§4a sends the lead to the worktree commands before any reproduction" \
    'Before any reproduction, Read `references/adjudication-worktree.md`' "${SECTION_4A}"
assert_contains "§4a restates the carry rule: git diff HEAD, never base" \
    'carried with `git diff HEAD` (never `{base_sha}`)' "${SECTION_4A}"
assert_contains "§4a gives the 2026-08-12 mistake its referent, with when to Read it" \
    '(Read `references/adjudication-example.md` before calling one refuted)' "${SECTION_4A}"
assert_contains "worktree commands check out the reviewed head detached" \
    'git worktree add --detach "$WT" {head_sha}' "${WORKTREE_TEXT}"
assert_contains "worktree commands carry uncommitted work from HEAD" \
    'git diff HEAD | git -C "$WT" apply' "${WORKTREE_TEXT}"

# --- The rules survive a post-compaction re-attach --------------------------
# Claude Code re-attaches an invoked skill cut to its first ~20,000 characters,
# and this SKILL.md is still larger than that, so the FINDING contract, §4a and
# §5 must sit wholly inside the first 19,500 bytes (the re-attach budget). Each
# section ends where the next heading of the same or a higher level begins. A
# `# comment` inside a fenced code block is not a heading: without the fence
# toggle a fenced shell comment in §5 ended it early and the cell passed with
# §5 really ending 2,000 bytes past the cut.
REATTACH_BYTES=19500
# _section_end <heading-prefix> <level> [file] — byte offset where the section ends.
_section_end() {
    LC_ALL=C awk -v h="$1" -v lv="$2" '
        /^[[:space:]]*```/ { fence = !fence }
        f && !fence && match($0, /^#+ /) && RLENGTH - 1 <= lv { print n; done = 1; exit }
        !f && index($0, h) == 1 { f = 1 }
        { n += length($0) + 1 }
        END { if (f && !done) print n }
    ' "${3:-${SKILL}}"
}
# Control: a fenced `# comment` inside a section does not end it. The expected
# end is the next real heading's byte offset, read independently with grep -b.
_fence_doc="$(mktemp)"
printf '%s\n' '# T' '' '### 5. X' 'text' '```bash' '# a shell comment' 'echo hi' '```' 'more' '### 6. Y' 'tail' > "${_fence_doc}"
_fence_want="$(grep -b -m1 '^### 6\. Y' "${_fence_doc}" | cut -d: -f1)"
assert_equals "control: a fenced # comment does not end a section early" \
    "${_fence_want}" "$(_section_end '### 5. ' 3 "${_fence_doc}")"
rm -f "${_fence_doc}"
while IFS='|' read -r _h _lv _label; do
    [ -n "${_h}" ] || continue
    _end="$(_section_end "${_h}" "${_lv}")"
    case "${_end}" in
        ''|*[!0-9]*)
            _record_fail "${_label} ends within the first ${REATTACH_BYTES} bytes" "heading '${_h}' not found" ;;
        *)
            if [ "${_end}" -le "${REATTACH_BYTES}" ]; then
                _record_pass "${_label} ends within the first ${REATTACH_BYTES} bytes (byte ${_end})"
            else
                _record_fail "${_label} ends within the first ${REATTACH_BYTES} bytes" \
                    "it ends at byte ${_end}, past the re-attach cut — move situational detail below it"
            fi ;;
    esac
done <<'SECTIONS'
## Communication Contract|2|the FINDING contract
### 4a. |3|§4a
### 5. Verdict Routing|3|§5
SECTIONS

# --- References index: every references/*.md is named from SKILL.md ---------
# A file the core never names is never Read, and a named file must exist.
_refs_n=0
for _f in "$(dirname "${SKILL}")/references"/*.md; do
    [ -f "${_f}" ] || continue
    _refs_n=$((_refs_n + 1))
    assert_contains "SKILL.md names references/$(basename "${_f}")" \
        "references/$(basename "${_f}")" "${SKILL_TEXT}"
done
assert_equals "references/ holds the five moved files" "5" "${_refs_n}"
for _named in $(grep -oE 'references/[A-Za-z0-9_-]+\.md' "${SKILL}" | sort -u); do
    assert_file_exists "named ${_named} exists" "$(dirname "${SKILL}")/${_named}"
done

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

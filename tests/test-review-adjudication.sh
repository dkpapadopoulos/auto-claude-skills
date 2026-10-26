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
# A fence opens with 3+ backticks or 3+ tildes and closes only on a line of the
# SAME character, at least as long, with nothing after it — so a ``` inside a
# ```` fence, or a ~~~ fence, does not end it. `fl` is the open fence's length.
_section_end() {
    LC_ALL=C awk -v h="$1" -v lv="$2" '
        match($0, /^[[:space:]]*(```+|~~~+)/) {
            _m = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", _m)
            if (!fl) { fc = substr(_m, 1, 1); fl = length(_m) }
            else if (substr(_m, 1, 1) == fc && length(_m) >= fl && substr($0, RSTART + RLENGTH) ~ /^[[:space:]]*$/) fl = 0
        }
        f && !fl && match($0, /^#+ /) && RLENGTH - 1 <= lv { print n; done = 1; exit }
        !f && index($0, h) == 1 { f = 1 }
        { n += length($0) + 1 }
        END { if (f && !done) print n }
    ' "${3:-${SKILL}}"
}
# Controls: a fenced `# comment` inside a section does not end it, for each
# fence shape. The expected end is the next real heading's byte offset, read
# independently with grep -b.
_fence_doc="$(mktemp)"
printf '%s\n' '# T' '' '### 5. X' 'text' '```bash' '# a shell comment' 'echo hi' '```' 'more' '### 6. Y' 'tail' > "${_fence_doc}"
_fence_want="$(grep -b -m1 '^### 6\. Y' "${_fence_doc}" | cut -d: -f1)"
assert_equals "control: a fenced # comment does not end a section early" \
    "${_fence_want}" "$(_section_end '### 5. ' 3 "${_fence_doc}")"
printf '%s\n' '# T' '' '### 5. X' 'text' '~~~bash' '# a shell comment' 'echo hi' '~~~' 'more' '### 6. Y' 'tail' > "${_fence_doc}"
_fence_want="$(grep -b -m1 '^### 6\. Y' "${_fence_doc}" | cut -d: -f1)"
assert_equals "control: a # comment in a tilde fence does not end a section early" \
    "${_fence_want}" "$(_section_end '### 5. ' 3 "${_fence_doc}")"
printf '%s\n' '# T' '' '### 5. X' 'text' '````markdown' '```bash' '# a shell comment' '```' '````' 'more' '### 6. Y' 'tail' > "${_fence_doc}"
_fence_want="$(grep -b -m1 '^### 6\. Y' "${_fence_doc}" | cut -d: -f1)"
assert_equals "control: a # comment in a four-backtick fence holding a \`\`\` block does not end a section early" \
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

# --- What runs every time past the cut is restated inside the window ---------
# Recording the verdict (after Verification) and §6's Mode B and same-family
# rules sit past the cut; §5 and §6's opening paragraph restate them, and each
# restated line is pinned on its own, so moving one past the cut fails by name.
SECTION_5="$(awk '/^### 5\./{f=1;next} f && /^#+ /{exit} f' "${SKILL}")"
SECTION_6_OPEN="$(awk '/^### 6\./{f=1;next} f && /^\*\*Mode A/{exit} f' "${SKILL}")"
assert_contains "§5 routes clean through recording before SHIP" \
    '| `clean` | TeamDelete → cross-model offer (§6, when applicable) → record the verdict → proceed to SHIP |' "${SECTION_5}"
assert_contains "§5 routes suggestions_only through recording before SHIP" \
    '| `suggestions_only` | TeamDelete → cross-model offer (§6, when applicable) → record the verdict → proceed to SHIP |' "${SECTION_5}"
assert_contains "§5 records once, after §6 resolves" \
    '**Then record the verdict** (Record the Review Verdict, after Verification), once, after §6 resolves' "${SECTION_5}"
assert_contains "§5 restates: clean only when every actionable finding was resolved or accepted" \
    '`--verdict clean` ONLY when every actionable finding was resolved or explicitly accepted' "${SECTION_5}"
assert_contains "§5 restates: findings-open with the real count" \
    '`findings-open` with the real `--unresolved-blocking` count otherwise' "${SECTION_5}"
assert_contains "§5 restates: could-not-review when a lens never delivered" \
    '`could-not-review` when a lens never delivered' "${SECTION_5}"
assert_contains "§5 restates: --self-authored when this context wrote the diff" \
    'pass `--self-authored` when this context authored the diff' "${SECTION_5}"
assert_contains "§5 restates: never read the singleton token" \
    'never read `~/.claude/.skill-session-token`' "${SECTION_5}"
assert_contains "§6 opening restates: a same-family substitute is never a cross-family pass" \
    'A same-family substitute is never presented as a cross-family pass' "${SECTION_6_OPEN}"
assert_contains "§6 opening names Mode B's second cycle and recomputed verdict" \
    'an accepted Mode B offer runs a second cycle in which the verdict is recomputed' "${SECTION_6_OPEN}"
# _line_end <line-prefix> — byte offset where the first unfenced line starting
# with the prefix ends (same fence rule as _section_end).
_line_end() {
    LC_ALL=C awk -v h="$1" '
        match($0, /^[[:space:]]*(```+|~~~+)/) {
            _m = substr($0, RSTART, RLENGTH); sub(/^[[:space:]]*/, "", _m)
            if (!fl) { fc = substr(_m, 1, 1); fl = length(_m) }
            else if (substr(_m, 1, 1) == fc && length(_m) >= fl && substr($0, RSTART + RLENGTH) ~ /^[[:space:]]*$/) fl = 0
        }
        { n += length($0) + 1 }
        !fl && index($0, h) == 1 { print n; exit }
    ' "${SKILL}"
}
while IFS='|' read -r _p _label; do
    [ -n "${_p}" ] || continue
    _end="$(_line_end "${_p}")"
    case "${_end}" in
        ''|*[!0-9]*)
            _record_fail "${_label} ends within the first ${REATTACH_BYTES} bytes" "'${_p}' not found" ;;
        *)
            if [ "${_end}" -le "${REATTACH_BYTES}" ]; then
                _record_pass "${_label} ends within the first ${REATTACH_BYTES} bytes (byte ${_end})"
            else
                _record_fail "${_label} ends within the first ${REATTACH_BYTES} bytes" \
                    "it ends at byte ${_end}, past the re-attach cut"
            fi ;;
    esac
done <<'LINES'
**Then record the verdict**|§5 record-the-verdict restatement
A same-family substitute is never presented as a cross-family pass|§6 same-family and Mode B restatement
LINES

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

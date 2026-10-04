#!/usr/bin/env bash
# test-activation-question-guard.sh — a question is not a work order.
#
# The activation hook used to tell the model a process skill "MUST INVOKE" whenever a trigger
# word appeared, including in a question: "what's the next step here?" mandated
# executing-plans, "is the review done?" mandated requesting-code-review, and
# tests/test-routing.sh has carried "what does this error message mean" as a KNOWN FALSE
# POSITIVE for systematic-debugging since it was written.
#
# THE RULE. A prompt is question-shaped when it ENDS with "?" and no statement precedes that
# question, or when it STARTS with a question word and is one clause on one line. It is not
# question-shaped when it contains a polite request (can/could/would/will + you/we/i,
# "please", "would it be possible"). On a question-shaped prompt, if the selected process
# skill got there on trigger words alone — no skill name, no keyword phrase, no trigger
# alternative that is itself written as a question, phase not LEARN — and no domain or
# workflow skill was selected alongside it, the hook DISPLAYS NOTHING.
#
# DISPLAY-ONLY, and this file exists as much for that as for the rule. The first cut dropped
# the skill in the scorer, which also stopped the composition-state write; the push gate runs
# its chain checks only when that file exists, so a push after "is the review of the PR diff
# for bugs done?" went from DENY to allow (measured; the gate's decision is pinned in
# tests/test-push-gate-display-suppression.sh). Every suppressed prompt below is therefore
# also run with ACS_QUESTION_GUARD=off, and the routing state the two runs write must be
# identical. The guard does not look at whether a chain is active: it changes no state, so
# there is nothing for an active chain to be protected from.
#
#   G1  control: an instruction mandates the process skill and starts a chain
#   G2  the same words as a question: nothing displayed, state as with the guard off
#       (including the armed chain)
#   G3  a one-clause question with no question mark: the same
#   G4  the suite's long-standing known false positive: the same
#   G5  a polite request keeps its mandate, wherever the polite words sit (four phrasings)
#   G6  an imperative that starts with "do" keeps its mandate
#   G7  naming the skill in a question keeps it
#   G8  a keyword phrase in a question keeps it
#   G9  a LEARN-phase question still routes outcome-review
#   G10 a question followed by an instruction keeps its mandate (same line, and next line)
#   G11 with a chain ACTIVE, a question displays nothing and moves state as with the guard off
#   G12 SKILL_EXPLAIN=1 says what was suppressed and that state is still written
#   G13 a question that ALSO selects a domain or workflow skill is displayed unchanged
#   G14 a work order that merely ENDS with a question keeps its mandate (next line, same
#       line, "!", ":", CRLF), while a prompt made only of questions is still suppressed
#   (G15 is retired. It asserted that a suppressed question records neither gating milestone
#   as completed, which mattered when the first cut moved the chain's anchor. State is now
#   identical to the guard-off run by the cells inside `suppressed`, and removing the
#   walker's exclusion no longer changed G15's outcome — a cell that cannot fail. The
#   exclusion keeps its own regression in tests/test-routing.sh.)
#   G16 KNOWN LIMITS, pinned so nobody reads them as coverage
#   G17 a trigger alternative that is itself a question ("how would", "which issue") keeps
#       its mandate
#   G18 an imperative behind a subordinate clause keeps its mandate — by the comma rule
#       ("how about this, do Y") and, separately, because when/where are not question words
#       ("when you get a moment do Y"); one prompt per defence, so neither hides the other
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-activation-question-guard.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
REAL_JQ="$(command -v jq 2>/dev/null)"
if [ -z "${REAL_JQ}" ]; then
    _record_fail "jq available" "jq is required"; print_summary; exit 1
fi

setup_test_env
BASE_HOME="${TEST_TMPDIR}/base"
mkdir -p "${BASE_HOME}/.claude"
echo '{}' | HOME="${BASE_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    /bin/bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" >/dev/null 2>&1 < /dev/null
FULL="${TEST_TMPDIR}/full.json"
"${REAL_JQ}" '.skills |= map(.available = true | .enabled = true) | .plugins |= map(.available = true)' \
    "${BASE_HOME}/.claude/.skill-registry-cache.json" > "${FULL}" 2>/dev/null

new_home() {
    LAST_HOME="$(mktemp -d "${TEST_TMPDIR}/run.XXXXXX")"
    mkdir -p "${LAST_HOME}/.claude"
    cp "${FULL}" "${LAST_HOME}/.claude/.skill-registry-cache.json"
}
# ask <prompt> [env...] : the hook's stdout and stderr for a prompt, in LAST_HOME.
ask() {
    local p="$1"; shift
    "${REAL_JQ}" -n --arg p "${p}" --arg t "${LAST_HOME}/.claude/abc123.jsonl" '{prompt:$p,transcript_path:$t}' \
      | env HOME="${LAST_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${TEST_TMPDIR}" "$@" \
            /bin/bash "${HOOK}" 2>&1
}
state_files() { ls "${LAST_HOME}"/.claude/.skill-composition-state-* 2>/dev/null | wc -l | tr -d ' '; }
# snap : every routing state file in LAST_HOME, name and checksum, with the one timestamp
# field removed and the throwaway home path normalised. The registry cache is an input.
snap() {
    ( cd "${LAST_HOME}/.claude" && ls -A | grep -E '^\.skill-' | grep -v '^\.skill-registry-cache\.json$' | LC_ALL=C sort \
        | while IFS= read -r _sf; do
            printf '%s %s\n' "${_sf}" "$(sed -e 's/"updated_at": *"[^"]*"/"updated_at":"T"/' -e "s|${LAST_HOME}|HOME|g" "${_sf}" | cksum)"
          done )
}
mandates() { assert_contains "$1" "$2 MUST INVOKE" "$3"; }

# suppressed <label> <prompt> <skill-the-guard-off-run-mandates>
#   guard on : nothing is displayed
#   guard off: the named skill IS mandated (the control: without it "nothing displayed" is
#              equally true of a prompt that never matched anything)
#   and the two runs write identical routing state.
suppressed() {
    local on off snap_on snap_off
    new_home; on="$(ask "$2")"; snap_on="$(snap)"
    new_home; off="$(ask "$2" ACS_QUESTION_GUARD=off)"; snap_off="$(snap)"
    assert_equals "$1: nothing is displayed (output length)" "0" "${#on}"
    mandates "$1: control, the guard-off run mandates $3" "$3" "${off}"
    if [ -n "${snap_off}" ]; then
        assert_equals "$1: routing state is identical to the guard-off run" "${snap_off}" "${snap_on}"
    else
        _record_fail "$1: routing state is identical to the guard-off run" "the guard-off run wrote no state, so there is nothing to compare"
    fi
}
# kept <label> <prompt> <skill>
kept() {
    local out
    new_home; out="$(ask "$2")"
    mandates "$1" "$3" "${out}"
}

# G1 control
new_home; OUT="$(ask 'review the PR diff for bugs')"
mandates "G1 control: an instruction mandates requesting-code-review" "requesting-code-review" "${OUT}"
assert_equals "G1 control: and starts a composition chain" "1" "$(state_files)"

# G2
suppressed "G2: the same words as a question" 'is the review of the PR diff for bugs done?' "requesting-code-review"
new_home; ask 'is the review of the PR diff for bugs done?' >/dev/null
assert_equals "G2: and the chain is still ARMED (the push gate's chain checks depend on it)" "1" "$(state_files)"

# G3
suppressed "G3: a one-clause question without a question mark" "what's the best next step here" "executing-plans"

# G4
suppressed "G4: the known false positive" 'what does this error message mean' "systematic-debugging"

# G5 polite requests, at the start and elsewhere
kept "G5: 'can you ...?' keeps its mandate" 'can you review the PR diff for bugs?' "requesting-code-review"
kept "G5: 'could you ...?' keeps its mandate" 'could you debug this failing test?' "systematic-debugging"
kept "G5: 'please can you ...?' keeps its mandate" 'please can you review the PR diff for bugs?' "requesting-code-review"
kept "G5: 'ok, can you ...?' keeps its mandate" 'ok, can you debug the failing test?' "systematic-debugging"

# G6 imperative starting with "do"
kept "G6: an imperative starting with 'do' keeps its mandate" 'do a code review of the PR diff' "requesting-code-review"

# G7 named skill
kept "G7: naming the skill in a question keeps it" 'should we run systematic-debugging on this?' "systematic-debugging"

# G8 keyword phrase
# ("best way to" is a keyword and not a question-form trigger match, so this prompt is held
# by the keyword exemption alone; "how should we ..." would also pass through G17's rule.)
kept "G8: a keyword phrase in a question keeps brainstorming" 'is there a best way to design the cache layer?' "brainstorming"

# G9 LEARN
new_home; OUT="$(ask 'how did the auth feature perform')"
assert_contains "G9: a LEARN-phase question still routes outcome-review" "outcome-review" "${OUT}"
# ("how did ..." is also a question-form match; this one is held by the LEARN exemption alone.)
kept "G9: a LEARN-phase question with no question-form trigger still routes outcome-review" 'is the adoption funnel healthy' "outcome-review"

# G10 question followed by an instruction
kept "G10: a question, then an instruction on the same line, keeps its mandate" 'is it ready? review the PR diff for bugs.' "requesting-code-review"
kept "G10: a question, then an instruction on the next line, keeps its mandate" "$(printf 'what is the status\nreview the PR diff for bugs')" "requesting-code-review"

# G11 active chain. Two homes, the same two prompts; the second is the question.
new_home; HOME_ON="${LAST_HOME}";  ask 'review the PR diff for bugs' >/dev/null
new_home; HOME_OFF="${LAST_HOME}"; ask 'review the PR diff for bugs' ACS_QUESTION_GUARD=off >/dev/null
LAST_HOME="${HOME_ON}"
if [ "$(state_files)" = "1" ]; then
    _record_pass "G11 setup: a chain is active before the question"
else
    _record_fail "G11 setup: a chain is active before the question" "no composition state — the cells below would prove nothing"
fi
OUT_ON="$(ask "what's the next step?")"; SNAP_ON="$(snap)"
LAST_HOME="${HOME_OFF}"; OUT_OFF="$(ask "what's the next step?" ACS_QUESTION_GUARD=off)"; SNAP_OFF="$(snap)"
mandates "G11 control: with the guard off, the in-chain question carries a mandate" "executing-plans" "${OUT_OFF}"
assert_equals "G11: with a chain active, the question displays nothing" "0" "${#OUT_ON}"
assert_equals "G11: and moves the chain's state exactly as with the guard off" "${SNAP_OFF}" "${SNAP_ON}"

# G12 explain
new_home; OUT="$(ask 'is the review of the PR diff for bugs done?' SKILL_EXPLAIN=1)"
assert_contains "G12: SKILL_EXPLAIN reports the suppression" "[display-suppressed] question: requesting-code-review" "${OUT}"
assert_contains "G12: and says state is still written" "routing state is written as usual" "${OUT}"

# G13 a domain or workflow skill selected alongside: displayed unchanged
G13_P='we deployed v3.2.1 thirty minutes ago and error rates jumped from 0.1% to 15%, should we rollback?'
new_home; OUT_ON="$(ask "${G13_P}")"; _h_on="${LAST_HOME}"
new_home; OUT_OFF="$(ask "${G13_P}" ACS_QUESTION_GUARD=off)"; _h_off="${LAST_HOME}"
assert_contains "G13 setup: the prompt selects a domain skill next to the process skill" "+ Domain" "${OUT_OFF}"
assert_equals "G13: a question that also selects a domain skill is displayed unchanged" "${OUT_OFF//${_h_off}/H}" "${OUT_ON//${_h_on}/H}"

# G14 a statement before the trailing question
kept "G14: an instruction, then a question on the next line, keeps its mandate" "$(printf 'Review the PR diff for bugs.\nAnything unclear?')" "requesting-code-review"
kept "G14: an instruction, then a question on the same line, keeps its mandate" 'review the PR diff for bugs. anything unclear?' "requesting-code-review"
kept "G14: an instruction ending in '!', then a question, keeps its mandate" 'review the PR diff for bugs! ok?' "requesting-code-review"
kept "G14: an unpunctuated instruction line, then a question line, keeps its mandate" "$(printf 'review the PR diff for bugs\nanything unclear?')" "requesting-code-review"
kept "G14: the same with CRLF line endings keeps its mandate" "$(printf 'review the PR diff for bugs\r\nanything unclear?')" "requesting-code-review"
kept "G14: an instruction, a colon, then a question keeps its mandate" 'debug this: why does the parser crash?' "systematic-debugging"
suppressed "G14 control: a prompt made only of questions (two lines)" "$(printf 'is the review of the PR diff for bugs done?\nis it any good?')" "requesting-code-review"
suppressed "G14 control: two questions on one line" 'is the review of the PR diff for bugs done? is it any good?' "requesting-code-review"

# G16 KNOWN LIMITS. These assert the CURRENT, imperfect behaviour. If one starts failing
# because the rule got better, update the cell and the hook comment together. The first two
# are work orders the rule misreads as questions: they lose their DISPLAY for that one
# prompt, and nothing else — the state cells inside `suppressed` hold for them too.
suppressed "G16 KNOWN LIMIT: a suggestion opening with 'how about'" 'how about we implement the cache layer now' "brainstorming"
suppressed "G16 KNOWN LIMIT: a statement opening with 'what we need'" 'what we need now is to debug the crash in the parser' "systematic-debugging"
kept "G16 KNOWN LIMIT: a polite-form question keeps a mandate it should not have" 'can you explain why the review matters?' "requesting-code-review"
kept "G16 KNOWN LIMIT: a question that only mentions a skill name keeps a mandate" 'what does systematic-debugging mean?' "systematic-debugging"

# G17 question-form trigger alternatives
kept "G17: 'how would you ...?' keeps brainstorming (the trigger is written as a question)" 'how would you scope this?' "brainstorming"
kept "G17: 'which issue should we ...?' keeps product-discovery" 'which issue should we tackle next?' "product-discovery"

# G18 subordinate-clause openers
kept "G18: 'when X, do Y' keeps its mandate" 'when the build finishes, review the PR diff for bugs' "requesting-code-review"
kept "G18: 'where possible, do Y' keeps its mandate" 'where possible, fix the crash and add tests' "systematic-debugging"
kept "G18: a question word, a comma, then an instruction keeps its mandate (comma rule)" 'how about this, review the PR diff for bugs' "requesting-code-review"
kept "G18: 'when ... do Y' with no comma keeps its mandate (when is not a question word)" 'when you get a moment review the PR diff for bugs' "requesting-code-review"

teardown_test_env
print_summary

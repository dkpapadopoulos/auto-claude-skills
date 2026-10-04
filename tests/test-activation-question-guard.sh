#!/usr/bin/env bash
# test-activation-question-guard.sh — a question is not a work order.
#
# The activation hook used to tell the model a process skill "MUST INVOKE" whenever a trigger
# word appeared, including in a plain question: "what's the next step?" mandated
# executing-plans and "is the review done?" mandated requesting-code-review.
#
# THE RULE, deliberately tight. A prompt is question-shaped only when ALL of these hold:
#   - it OPENS with an interrogative (what why how is are does did who which where when should)
#   - it ENDS with "?"
#   - it is ONE clause on ONE line (no ". ! ? : ; ," followed by more text, no " - " dash)
#   - it contains no request phrase (can/could/would/will + you/we/i, "is it possible",
#     "are you able", "any chance", "please", "how about", "what about", "why don't", "why not")
# On such a prompt, if the selected process skill got there on trigger words alone — the user
# did not name it, no keyword phrase matched, no trigger alternative written as a question
# matched, its phase is not LEARN or DEBUG, and it is not already a step of this session's
# chain — and no domain or workflow skill was selected with it, the hook DISPLAYS NOTHING.
#
# Two earlier, looser rules were reviewed and withdrawn: one also took any prompt ending in
# "?" and one-clause prompts with no "?" at all, and each review found more families of
# ordinary work orders read as questions ("fix the failing test, ok?", "is still broken
# after your change - debug it", "how about we implement the cache layer now"). This rule
# trades reach for precision on purpose; what it gives up is pinned in G16.
#
# DISPLAY-ONLY, and this file exists as much for that as for the rule. The first cut dropped
# the skill in the scorer, which also stopped the composition-state write; the push gate runs
# its chain checks only when that file exists, so a push after "is the review of the PR diff
# for bugs done?" went from DENY to allow (measured; the gate's decision is pinned in
# tests/test-push-gate-display-suppression.sh). Every suppressed prompt below is therefore
# also run with ACS_QUESTION_GUARD=off, and the routing state the two runs write must be
# identical.
#
#   G1  control: an instruction mandates the process skill and starts a chain
#   G2  each opening interrogative, as a one-clause question ending in "?": nothing is
#       displayed, the guard-off run mandates, and the state written is identical
#   G3  the chain is still ARMED after a suppressed question
#   G5  a request phrase keeps the mandate — one prompt per phrase in the list
#   G6  an imperative keeps its mandate, with or without a trailing "?"
#   G7  naming the skill in a question keeps it
#   G8  a keyword phrase in a question keeps it
#   G9  a LEARN-phase and a DEBUG-phase question keep their mandate
#   G10 more than one clause keeps the mandate — one prompt per separator
#   G11 with a chain ACTIVE: a question about a step OF that chain is displayed unchanged;
#       a question that would start an unrelated process skill is still suppressed; and a
#       bare follow-up that matches nothing keeps its sticky display
#   G12 SKILL_EXPLAIN=1 says what was suppressed and that state is still written
#   G13 a question that also selects a domain skill, or a workflow skill, is displayed
#       unchanged
#   G16 KNOWN LIMITS, pinned so nobody reads them as coverage
#   G17 a trigger alternative that is itself a question keeps its mandate (how / what /
#       which / where — one prompt each, none of them containing a request phrase)
#
# MUTATION SWEEP, 2026-10-05: 59 single-change mutants of the hook (every opening word, every
# request phrase, every separator, every exemption, both first-cut behaviours); each is caught
# by a named cell here or in the two sibling files, with ONE named exception. The scorer's
# `trigger_score -gt 0` condition is NOT held by any cell: a process skill with no trigger hit
# reaches selection only through sticky emission, and a sticky skill is always a step of the
# active chain, which the chain-member rule already exempts (G11). It is kept as a second
# line of defence and listed here so nobody reads this file as covering it.
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

# G2 one prompt per opening interrogative. Removing a word from the list fails its row.
suppressed "G2 what"   'what is the status of the code review?' "requesting-code-review"
suppressed "G2 why"    'why is the code review of the PR diff taking so long?' "requesting-code-review"
suppressed "G2 how"    'how is the code review of the PR diff going?' "requesting-code-review"
suppressed "G2 is"     'is the review of the PR diff for bugs done?' "requesting-code-review"
suppressed "G2 are"    'are the PR diff bugs worth a code review?' "requesting-code-review"
suppressed "G2 does"   'does the PR diff need a code review?' "requesting-code-review"
suppressed "G2 did"    'did the code review of the PR diff find anything?' "requesting-code-review"
suppressed "G2 who"    'who should review the PR diff for bugs?' "requesting-code-review"
suppressed "G2 which"  'which reviewer looked at the PR diff?' "requesting-code-review"
suppressed "G2 where"  'where is the code review of the PR diff?' "requesting-code-review"
suppressed "G2 when"   'when is the code review of the PR diff due?' "requesting-code-review"
suppressed "G2 should" 'should the PR diff get a code review?' "requesting-code-review"
suppressed "G2 another skill" "what's the next step?" "executing-plans"

# G3
new_home; ask 'is the review of the PR diff for bugs done?' >/dev/null
assert_equals "G3: the chain is still ARMED after a suppressed question (the push gate's chain checks depend on it)" "1" "$(state_files)"

# G5 one prompt per request phrase. Each opens with an interrogative, ends in "?" and is one
# clause, so the request phrase is the only thing holding its mandate.
kept "G5 can you"        'when can you review the PR diff for bugs?' "requesting-code-review"
kept "G5 could you"      'what could you review in the PR diff?' "requesting-code-review"
kept "G5 would you"      'when would you review the PR diff for bugs?' "requesting-code-review"
kept "G5 will you"       'when will you review the PR diff for bugs?' "requesting-code-review"
kept "G5 can we"         'when can we review the PR diff for bugs?' "requesting-code-review"
kept "G5 can i"          'where can i review the PR diff for bugs?' "requesting-code-review"
kept "G5 can u"          'when can u review the PR diff for bugs?' "requesting-code-review"
kept "G5 is it possible" 'is it possible to review the PR diff for bugs?' "requesting-code-review"
kept "G5 are you able"   'are you able to review the PR diff for bugs?' "requesting-code-review"
kept "G5 any chance"     'is there any chance of a code review of the PR diff?' "requesting-code-review"
kept "G5 please"         'should we review the PR diff for bugs please?' "requesting-code-review"
kept "G5 how about"      'how about we review the PR diff for bugs?' "requesting-code-review"
kept "G5 what about"     'what about a code review of the PR diff?' "requesting-code-review"
kept "G5 why don't"      "why don't you review the PR diff for bugs?" "requesting-code-review"
kept "G5 why not"        'why not review the PR diff for bugs?' "requesting-code-review"

# G6 imperatives
kept "G6: an imperative starting with 'do' keeps its mandate" 'do a code review of the PR diff' "requesting-code-review"
kept "G6: an imperative with a trailing '?' keeps its mandate" 'review the PR diff for bugs?' "requesting-code-review"
kept "G6: 'can you ...?' keeps its mandate" 'can you review the PR diff for bugs?' "requesting-code-review"

# G7 named skill
# (A non-DEBUG skill on purpose: a debugging skill would be held by the DEBUG exemption and
# this cell would pass with the name rule deleted — which is what a mutation sweep found.)
kept "G7: naming the skill in a question keeps it" 'should we run requesting-code-review on this?' "requesting-code-review"

# G8 keyword phrase ("best way to" is a keyword and not a question-form trigger match)
kept "G8: a keyword phrase in a question keeps brainstorming" 'is there a best way to design the cache layer?' "brainstorming"

# G9 LEARN and DEBUG: a question is how an outcome review, or a debugging session, is asked for
kept "G9: a LEARN-phase question keeps outcome-review" 'is the adoption funnel healthy?' "outcome-review"
kept "G9: a DEBUG-phase question keeps systematic-debugging" 'why is the test failing?' "systematic-debugging"

# G10 more than one clause — one prompt per separator
kept "G10 dash"      'what is the status - is the review of the PR diff done?' "requesting-code-review"
kept "G10 comma"     'what is the status, and is the review of the PR diff done?' "requesting-code-review"
kept "G10 semicolon" 'what is the status; is the review of the PR diff done?' "requesting-code-review"
kept "G10 colon"     'what is the status: is the review of the PR diff done?' "requesting-code-review"
kept "G10 period"    'what is the status. is the review of the PR diff done?' "requesting-code-review"
kept "G10 question mark" 'what is the status? is the review of the PR diff done?' "requesting-code-review"
kept "G10 exclamation" 'what is the status! is the review of the PR diff done?' "requesting-code-review"
kept "G10 em dash"   'what is the status — is the review of the PR diff done?' "requesting-code-review"
kept "G10 en dash"   'what is the status – is the review of the PR diff done?' "requesting-code-review"
kept "G10 newline"   "$(printf 'what is the status\nis the review of the PR diff done?')" "requesting-code-review"

# G11 active chain. Homes come in pairs (guard on / guard off) fed the same prompts.
new_home; HOME_ON="${LAST_HOME}";  ask 'review the PR diff for bugs' >/dev/null
new_home; HOME_OFF="${LAST_HOME}"; ask 'review the PR diff for bugs' ACS_QUESTION_GUARD=off >/dev/null
LAST_HOME="${HOME_ON}"
if [ "$(state_files)" = "1" ]; then
    _record_pass "G11 setup: a chain is active before the questions"
else
    _record_fail "G11 setup: a chain is active before the questions" "no composition state — the cells below would prove nothing"
fi
# (a) a question about a step of THIS chain: displayed, exactly as with the guard off
OUT_ON="$(ask "what's the next step?")"; SNAP_ON="$(snap)"
LAST_HOME="${HOME_OFF}"; OUT_OFF="$(ask "what's the next step?" ACS_QUESTION_GUARD=off)"; SNAP_OFF="$(snap)"
mandates "G11 control: the guard-off run mandates executing-plans for the in-chain question" "executing-plans" "${OUT_OFF}"
assert_equals "G11: a question about a step of the active chain is displayed unchanged" "${OUT_OFF//${HOME_OFF}/H}" "${OUT_ON//${HOME_ON}/H}"
assert_equals "G11: and the chain's state moves exactly as with the guard off" "${SNAP_OFF}" "${SNAP_ON}"
# (b) a bare follow-up that matches no trigger keeps its sticky display
LAST_HOME="${HOME_ON}";  OUT_ON="$(ask "is it done?")"
LAST_HOME="${HOME_OFF}"; OUT_OFF="$(ask "is it done?" ACS_QUESTION_GUARD=off)"
assert_contains "G11 control: the guard-off run displays the chain for a bare follow-up" "SKILL ACTIVATION" "${OUT_OFF}"
assert_equals "G11: a bare follow-up question keeps its sticky display" "${OUT_OFF//${HOME_OFF}/H}" "${OUT_ON//${HOME_ON}/H}"
# (c) a question that would start a process skill NOT in the chain is still suppressed.
# product-discovery belongs to a different chain than the one armed above.
new_home; HOME_ON="${LAST_HOME}";  ask 'review the PR diff for bugs' >/dev/null
new_home; HOME_OFF="${LAST_HOME}"; ask 'review the PR diff for bugs' ACS_QUESTION_GUARD=off >/dev/null
LAST_HOME="${HOME_ON}";  OUT_ON="$(ask 'is the backlog prioritised for this quarter?')"; SNAP_ON="$(snap)"
LAST_HOME="${HOME_OFF}"; OUT_OFF="$(ask 'is the backlog prioritised for this quarter?' ACS_QUESTION_GUARD=off)"; SNAP_OFF="$(snap)"
mandates "G11 control: the guard-off run mandates a skill outside the chain" "product-discovery" "${OUT_OFF}"
assert_equals "G11: a question that would start an unrelated process skill displays nothing" "0" "${#OUT_ON}"
assert_equals "G11: and state moves exactly as with the guard off" "${SNAP_OFF}" "${SNAP_ON}"

# G12 explain
new_home; OUT="$(ask 'is the review of the PR diff for bugs done?' SKILL_EXPLAIN=1)"
assert_contains "G12: SKILL_EXPLAIN reports the suppression" "[display-suppressed] question: requesting-code-review" "${OUT}"
assert_contains "G12: and says state is still written" "routing state is written as usual" "${OUT}"

# G13 a domain or workflow skill selected alongside: displayed unchanged. Both prompts are
# question-shaped (the G2 shape), so only the co-selection holds their display.
for _row in "Domain|is the frontend design of the login page done?" "Workflow|is the PR diff ready to merge?"; do
    _kind="${_row%%|*}"; _p="${_row#*|}"
    new_home; OUT_ON="$(ask "${_p}")"; _h_on="${LAST_HOME}"
    new_home; OUT_OFF="$(ask "${_p}" ACS_QUESTION_GUARD=off)"; _h_off="${LAST_HOME}"
    assert_contains "G13 setup: the prompt selects a ${_kind} skill next to the process skill" "+ ${_kind}" "${OUT_OFF}"
    assert_contains "G13 setup: and a process mandate" "MUST INVOKE" "${OUT_OFF}"
    assert_equals "G13: a question that also selects a ${_kind} skill is displayed unchanged" "${OUT_OFF//${_h_off}/H}" "${OUT_ON//${_h_on}/H}"
done

# G16 KNOWN LIMITS. These assert the CURRENT, imperfect behaviour. If one starts failing
# because the rule got better, update the cell and the hook comment together.
# Plain questions that still carry a mandate:
kept "G16 KNOWN LIMIT: a question with no question mark keeps its mandate" 'is the review of the PR diff for bugs done' "requesting-code-review"
kept "G16 KNOWN LIMIT: so does the suite's old false positive (and DEBUG is exempt anyway)" 'what does this error message mean' "systematic-debugging"
kept "G16 KNOWN LIMIT: a two-clause question keeps its mandate" 'is the review of the PR diff for bugs done? is it any good?' "requesting-code-review"
kept "G16 KNOWN LIMIT: a question containing a request phrase keeps its mandate" 'can you explain why the review matters?' "requesting-code-review"
kept "G16 KNOWN LIMIT: a question that only mentions a skill name keeps a mandate" 'what does systematic-debugging mean?' "systematic-debugging"
# A work order the rule still reads as a question (it loses its DISPLAY for that one prompt;
# the state cells inside `suppressed` hold for it too):
suppressed "G16 KNOWN LIMIT: 'should we <do the work>?' is read as a question" 'should we review the PR diff for bugs now?' "requesting-code-review"

# G17 question-form trigger alternatives, one per word the hook checks that a shipped trigger
# uses. None contains a request phrase, so the question-form rule is what holds each.
kept "G17 how: 'how would ...?' keeps brainstorming" 'how would the cache layer work?' "brainstorming"
kept "G17 what: 'what should we ...?' keeps product-discovery" 'what should we look at first?' "product-discovery"
kept "G17 which: 'which issue ...?' keeps product-discovery" 'which issue is next?' "product-discovery"
kept "G17 where: 'where were we?' keeps executing-plans" 'where were we?' "executing-plans"

teardown_test_env
print_summary

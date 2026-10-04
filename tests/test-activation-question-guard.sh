#!/usr/bin/env bash
# test-activation-question-guard.sh — a question is not a work order.
#
# The activation hook used to tell the model a process skill "MUST INVOKE" whenever a trigger
# word appeared, including in a question: "what's the next step here?" mandated
# executing-plans, "is the review done?" mandated requesting-code-review, and
# tests/test-routing.sh has carried "what does this error message mean" as a KNOWN FALSE
# POSITIVE for systematic-debugging since it was written.
#
# Measured 2026-10-05 (two blind labellers, kappa 0.79, on real prompts): on the development
# half the hook issued 9 right and 90 wrong process mandates; with this guard 9 right and 75
# wrong, and no previously-right mandate is lost. On a separately labelled field set the
# model had still INVOKED the mandated skill on 8 of 36 question-shaped prompts, 31 of which
# were clearly wrong routings.
#
# THE RULE. A prompt is question-shaped when it ENDS with "?" and no statement precedes that
# question, or when it STARTS with a
# question word and is a single sentence on a single line. It is not question-shaped when it
# starts with a polite request (can/could/would/will + you/we/i). On a question-shaped
# prompt a role=process skill is not admitted from its triggers alone. It is still admitted
# when the user names the skill, when one of the skill's keyword PHRASES matches, when the
# skill's phase is LEARN (a question is how an outcome review is asked for), or when a
# composition chain is already active for the session (the guard never disturbs a workflow
# in progress — it only declines to START one from a question).
#
#   G1  control: an instruction mandates the process skill and starts a chain
#   G2  the same words as a question ending in "?" mandate nothing and start no chain
#   G3  a single-sentence question with no question mark mandates nothing
#   G4  the suite's long-standing known false positive no longer mandates debugging
#   G5  a polite request keeps its mandate (two phrasings)
#   G6  an imperative that starts with "do" keeps its mandate
#   G7  naming the skill in a question keeps it
#   G8  a keyword phrase in a question keeps it
#   G9  a LEARN-phase question still routes outcome-review
#   G10 a question followed by an instruction keeps its mandate (same line, and next line)
#   G11 with a chain ACTIVE, a question is routed exactly as before the guard existed
#   G12 SKILL_EXPLAIN=1 says the guard applied, and names what it dropped
#   G13 a guarded question can still surface a non-process skill
#   G14 a work order that merely ENDS with a question keeps its mandate (next line, same
#       line, "!"), while a prompt made only of questions is still guarded
#   G15 a guarded question that still anchors a chain through a workflow skill records
#       NEITHER gating milestone as completed (persisted state, not rendered output)
#   G16 KNOWN LIMITS, pinned so nobody reads them as coverage
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
# ask <prompt> [env...] : the hook's additionalContext (plus stderr) for a prompt, in LAST_HOME.
ask() {
    local p="$1"; shift
    "${REAL_JQ}" -n --arg p "${p}" --arg t "${LAST_HOME}/.claude/abc123.jsonl" '{prompt:$p,transcript_path:$t}' \
      | env HOME="${LAST_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${TEST_TMPDIR}" "$@" \
            /bin/bash "${HOOK}" 2>&1
}
state_files() { ls "${LAST_HOME}"/.claude/.skill-composition-state-* 2>/dev/null | wc -l | tr -d ' '; }
mandates() { assert_contains "$1" "$2 MUST INVOKE" "$3"; }
no_mandate() { assert_not_contains "$1" "MUST INVOKE" "$2"; }

# G1 control
new_home; OUT="$(ask 'review the PR diff for bugs')"
mandates "G1 control: an instruction mandates requesting-code-review" "requesting-code-review" "${OUT}"
assert_equals "G1 control: and starts a composition chain" "1" "$(state_files)"

# G2
new_home; OUT="$(ask 'is the review of the PR diff for bugs done?')"
no_mandate "G2: the same words as a question mandate nothing" "${OUT}"
assert_equals "G2: and start no composition chain" "0" "$(state_files)"

# G3
new_home; OUT="$(ask "what's the best next step here")"
no_mandate "G3: a single-sentence question without a question mark mandates nothing" "${OUT}"

# G4
new_home; OUT="$(ask 'what does this error message mean')"
no_mandate "G4: the known false positive no longer mandates systematic-debugging" "${OUT}"

# G5 polite requests
new_home; OUT="$(ask 'can you review the PR diff for bugs?')"
mandates "G5: 'can you ...?' keeps its mandate" "requesting-code-review" "${OUT}"
new_home; OUT="$(ask 'could you debug this failing test?')"
mandates "G5: 'could you ...?' keeps its mandate" "systematic-debugging" "${OUT}"

# G6 imperative starting with "do"
new_home; OUT="$(ask 'do a code review of the PR diff')"
mandates "G6: an imperative starting with 'do' keeps its mandate" "requesting-code-review" "${OUT}"

# G7 named skill
new_home; OUT="$(ask 'should we run systematic-debugging on this?')"
mandates "G7: naming the skill in a question keeps it" "systematic-debugging" "${OUT}"

# G8 keyword phrase
new_home; OUT="$(ask 'how should we design the cache layer?')"
mandates "G8: a keyword phrase in a question keeps brainstorming" "brainstorming" "${OUT}"

# G9 LEARN
new_home; OUT="$(ask 'how did the auth feature perform')"
assert_contains "G9: a LEARN-phase question still routes outcome-review" "outcome-review" "${OUT}"

# G10 question followed by an instruction
new_home; OUT="$(ask 'is it ready? review the PR diff for bugs.')"
mandates "G10: a question followed by an instruction on the same line keeps its mandate" "requesting-code-review" "${OUT}"
new_home; OUT="$(ask "$(printf 'what is the status\nreview the PR diff for bugs')")"
mandates "G10: a question followed by an instruction on the next line keeps its mandate" "requesting-code-review" "${OUT}"

# G11 active chain: the guard is off. The reference is the same question in a home where the
# guard is disabled by ACS_QUESTION_GUARD=off, after the same chain-starting prompt.
new_home; ask 'review the PR diff for bugs' >/dev/null
HOME_ACTIVE="${LAST_HOME}"
OUT_ACTIVE="$(ask "what's the next step?")"
new_home; ask 'review the PR diff for bugs' >/dev/null
OUT_REF="$(ask "what's the next step?" ACS_QUESTION_GUARD=off)"
if [ "$(ls "${HOME_ACTIVE}"/.claude/.skill-composition-state-* 2>/dev/null | wc -l | tr -d ' ')" = "1" ]; then
    _record_pass "G11 setup: a chain is active before the question"
else
    _record_fail "G11 setup: a chain is active before the question" "no composition state — the cell below would prove nothing"
fi
assert_equals "G11: with a chain active, a question is routed exactly as with the guard off" "${OUT_REF}" "${OUT_ACTIVE}"
new_home; OUT_OFF="$(ask 'is the review of the PR diff for bugs done?' ACS_QUESTION_GUARD=off)"
mandates "G11 control: the off switch really restores the old mandate on a fresh session" "requesting-code-review" "${OUT_OFF}"

# G12 explain
new_home; OUT="$(ask 'is the review of the PR diff for bugs done?' SKILL_EXPLAIN=1)"
assert_contains "G12: SKILL_EXPLAIN reports the guard" "[question-guard]" "${OUT}"
assert_contains "G12: and names the process skill it did not admit" "requesting-code-review" "${OUT}"

# G13 a non-process skill still surfaces on a guarded question
new_home; OUT="$(ask 'is the PR diff for bugs ready for a security scan?')"
no_mandate "G13: no process mandate on this question" "${OUT}"
assert_contains "G13: but a non-process skill is still offered" "SKILL ACTIVATION" "${OUT}"

# G14 a statement before the trailing question
new_home; OUT="$(ask "$(printf 'Review the PR diff for bugs.\nAnything unclear?')")"
mandates "G14: an instruction, then a question on the next line, keeps its mandate" "requesting-code-review" "${OUT}"
new_home; OUT="$(ask 'review the PR diff for bugs. anything unclear?')"
mandates "G14: an instruction, then a question on the same line, keeps its mandate" "requesting-code-review" "${OUT}"
new_home; OUT="$(ask 'review the PR diff for bugs! ok?')"
mandates "G14: an instruction ending in '!', then a question, keeps its mandate" "requesting-code-review" "${OUT}"
new_home; OUT="$(ask "$(printf 'review the PR diff for bugs\nanything unclear?')")"
mandates "G14: an unpunctuated instruction line, then a question line, keeps its mandate" "requesting-code-review" "${OUT}"
new_home; OUT="$(ask "$(printf 'is the review of the PR diff done?\nis it merged?')")"
no_mandate "G14 control: a prompt made only of questions is still guarded" "${OUT}"
new_home; OUT="$(ask 'is the review of the PR diff done? is it merged?')"
no_mandate "G14 control: two questions on one line are still guarded" "${OUT}"

# G15 the gating milestones. A guarded question can still start a chain, anchored on a
# workflow skill instead of the process skill it no longer admits. What must hold is the
# PERSISTED state the push gate reads: review and verification are not recorded as done.
new_home; OUT="$(ask 'is the review done and are we ready to ship this?')"
STATE_FILE="$(ls "${LAST_HOME}"/.claude/.skill-composition-state-* 2>/dev/null | head -1)"
if [ -n "${STATE_FILE}" ] && "${REAL_JQ}" -e '.chain | index("requesting-code-review") != null and index("verification-before-completion") != null' "${STATE_FILE}" >/dev/null 2>&1; then
    _record_pass "G15 setup: the question anchored a chain that contains both gating milestones"
    COMPLETED="$("${REAL_JQ}" -r '.completed | join(" ")' "${STATE_FILE}")"
    assert_not_contains "G15: requesting-code-review is not recorded as completed" "requesting-code-review" "${COMPLETED}"
    assert_not_contains "G15: verification-before-completion is not recorded as completed" "verification-before-completion" "${COMPLETED}"
else
    _record_fail "G15 setup: the question anchored a chain that contains both gating milestones" "no such chain — the two cells below would prove nothing"
fi
no_mandate "G15: and the question itself carries no process mandate" "${OUT}"

# G16 KNOWN LIMITS. These assert the CURRENT, imperfect behaviour. If one starts failing
# because the rule got better, update the cell and the hook comment together.
new_home; OUT="$(ask 'review the PR diff for bugs, please?')"
no_mandate "G16 KNOWN LIMIT: a one-sentence imperative ending in '?' loses its mandate" "${OUT}"
new_home; OUT="$(ask 'can you explain why the review matters?')"
mandates "G16 KNOWN LIMIT: a polite-form question keeps a mandate it should not have" "requesting-code-review" "${OUT}"
new_home; OUT="$(ask 'what does systematic-debugging mean?')"
mandates "G16 KNOWN LIMIT: a question that only mentions a skill name keeps a mandate" "systematic-debugging" "${OUT}"

teardown_test_env
print_summary

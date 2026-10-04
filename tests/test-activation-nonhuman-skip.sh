#!/usr/bin/env bash
# test-activation-nonhuman-skip.sh — two more kinds of input reach UserPromptSubmit hooks
# without having been typed by the user, and the activation hook must not route either:
#
#   * a PEER MESSAGE — a subagent hand-back or a teammate's message, delivered as an
#     `<agent-message from="…">` block, optionally wrapped in a fixed intro line and one of
#     two fixed harness paragraphs;
#   * a NOTICE WITH A REMINDER — task-notification block(s) followed only by
#     `<system-reminder>` block(s): goal check-ins, background review notices.
#
# Measured 2026-10-04 over the owner's transcripts (745 distinct non-human inputs): 80 of
# 84 peer messages and 29 of 29 notices-with-reminder received a routing block carrying a
# `MUST INVOKE` line — a report that says "the test fails" was told to start
# systematic-debugging; a goal check-in was told to brainstorm, and one such mis-route
# started a composition chain that later made the skill gate refuse a real review.
# Pure task-notification prompts were already skipped (tests/test-activation-notification-skip.sh).
#
# SCOPE, and it is deliberate: the classification lives in the ACTIVATION hook only. The
# shared classifier hooks/lib/task-notification.sh is unchanged, so egress-consent-turn-hook.sh
# still treats these inputs as the user and still withdraws approvals over them — the safe
# direction for consent. E1/E2 pin that non-change.
#
#   H1  control: the peer body's text alone routes and starts a chain
#   H2  control: the reminder's text alone routes
#   P1  subagent hand-back (intro + block + harness paragraph) routes nothing, writes no state
#   P2  teammate variant of the paragraph routes nothing
#   P3  a bare agent-message block routes nothing
#   P4  an agent-message block followed by USER text still routes
#   P5  USER text followed by an agent-message block still routes
#   P6  a prompt that merely quotes the tag mid-line still routes
#   P7  two agent-message blocks (unobserved shape) still route — treated as the user
#   P8  a block whose `from` attribute is empty still routes (not the harness shape)
#   P9  a complete hand-back with a USER request on a new line after the harness paragraph
#       still routes (found in review: the first cut matched the paragraph by its opening
#       words and then swallowed anything after it)
#   P10 the same with the request appended on the paragraph's own line still routes
#   P12 the same with the request after each OTHER line separator — CR, VT, FF, NEL, U+2028,
#       U+2029 — and ending "permission laundering." still routes (found in review: only LF
#       was excluded from the paragraph, so a request on the next line was swallowed)
#   P11 a block, a second stray closing tag, then USER text still routes (the "exactly one
#       closing tag" rule; without it the text after the second tag is never looked at)
#   T1  notification + system-reminder routes nothing, writes no state
#   T2  notification + system-reminder + USER text still routes
#   T3  a system-reminder block with no notification before it still routes
#   T4  notification + two system-reminder blocks routes nothing
#   T5  USER text before a notice-with-reminder still routes (the part before the reminders
#       must itself be a notification, not merely end with a closing tag)
#   S1  a non-human input leaves an ACTIVE session's state byte-identical — composition
#       state, prompt counter, last-invoked — while the session-token singleton is still
#       re-stamped (a control shows a user prompt does move that state)
#   X1  a bounded-time regression cell, not a proof of linearity: three 200 KB near-misses
#       classify as the user within 3 s in total (the first cut was quadratic: 50k spaces
#       before a reminder tag took 4.6 s)
#   D1  SKILL_DEBUG=1 explains each skip
#   L1  without the shared lib: a peer message is still skipped (the peer check is the
#       hook's own), a notice-with-reminder routes as before (it reuses the lib's notion
#       of a notification, so without the lib it cannot be recognised)
#   E1  the egress turn hook still WITHDRAWS an approval over a peer message
#   E2  the egress turn hook still WITHDRAWS an approval over a notice-with-reminder
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-activation-nonhuman-skip.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
TURN="${PROJECT_ROOT}/hooks/egress-consent-turn-hook.sh"
FIX="${PROJECT_ROOT}/tests/fixtures/routing-input"
REAL_JQ="$(command -v jq 2>/dev/null)"
if [ -z "${REAL_JQ}" ]; then
    _record_fail "jq available" "jq is required"
    print_summary
    exit 1
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
}
# run_hook <prompt-file> [env...] : stdout and stderr, using LAST_HOME.
run_hook() {
    local pf="$1"; shift
    cp "${FULL}" "${LAST_HOME}/.claude/.skill-registry-cache.json"
    "${REAL_JQ}" -n --rawfile p "${pf}" --arg t "${LAST_HOME}/.claude/abc123.jsonl" \
        '{prompt:$p,transcript_path:$t}' \
      | env HOME="${LAST_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            SKILL_PROJECT_ROOT="${TEST_TMPDIR}" "$@" /bin/bash "${HOOK}" 2>&1
}
state_files() { ls "${LAST_HOME}"/.claude/.skill-composition-state-* 2>/dev/null | wc -l | tr -d ' '; }

# silent <label> <prompt-file> : the prompt routes nothing and writes no composition state.
silent() {
    local out
    new_home; out="$(run_hook "$2")"
    assert_equals "$1 routes nothing (output length)" "0" "${#out}"
    assert_equals "$1 writes no composition state" "0" "$(state_files)"
}
# routed <label> <prompt-file>
routed() {
    local out
    new_home; out="$(run_hook "$2")"
    assert_contains "$1 still routes" "SKILL ACTIVATION" "${out}"
}

for _f in peer-subagent-handback.txt peer-teammate.txt peer-bare-block.txt notice-with-reminder.txt; do
    if [ ! -s "${FIX}/${_f}" ]; then
        _record_fail "fixture ${_f} present" "missing or empty: every cell below would be vacuous"
        teardown_test_env; print_summary; exit 1
    fi
done
_record_pass "all four live-shaped fixtures are present"

# The synthetic body and reminder text, on their own, for the controls.
BODY="${TEST_TMPDIR}/body.txt"
sed -n '/<agent-message/,/<\/agent-message>/p' "${FIX}/peer-bare-block.txt" | sed '1d;$d' > "${BODY}"
REM="${TEST_TMPDIR}/rem.txt"
sed -n '/<system-reminder>/,/<\/system-reminder>/p' "${FIX}/notice-with-reminder.txt" | sed '1d;$d' > "${REM}"

# H1/H2: controls. Without these a silent result could mean "nothing routable was there".
new_home; OUT_H1="$(run_hook "${BODY}")"
assert_contains "H1 control: the peer body's text alone routes" "SKILL ACTIVATION" "${OUT_H1}"
assert_contains "H1 control: and is told a process skill MUST INVOKE" "MUST INVOKE" "${OUT_H1}"
assert_equals "H1 control: and starts a composition chain" "1" "$(state_files)"
new_home; OUT_H2="$(run_hook "${REM}")"
assert_contains "H2 control: the reminder's text alone routes" "SKILL ACTIVATION" "${OUT_H2}"

# P1-P3: the three observed peer shapes.
silent "P1: a subagent hand-back" "${FIX}/peer-subagent-handback.txt"
silent "P2: a teammate message" "${FIX}/peer-teammate.txt"
silent "P3: a bare agent-message block" "${FIX}/peer-bare-block.txt"

# P4-P8: anything that is not exactly one of those shapes is the user, or is treated as such.
P4="${TEST_TMPDIR}/p4.txt"
{ cat "${FIX}/peer-bare-block.txt"; printf '\nplease debug the failing test it mentions\n'; } > "${P4}"
routed "P4: an agent-message block followed by user text" "${P4}"
P5="${TEST_TMPDIR}/p5.txt"
{ printf 'debug the failing test described below\n'; cat "${FIX}/peer-bare-block.txt"; } > "${P5}"
routed "P5: user text followed by an agent-message block" "${P5}"
P6="${TEST_TMPDIR}/p6.txt"
printf '%s' 'debug the parser: it fails on <agent-message from="x"> blocks in the transcript' > "${P6}"
routed "P6: a prompt quoting the tag mid-line" "${P6}"
P7="${TEST_TMPDIR}/p7.txt"
{ cat "${FIX}/peer-bare-block.txt"; printf '\n'; cat "${FIX}/peer-bare-block.txt"; } > "${P7}"
routed "P7: two agent-message blocks (unobserved shape)" "${P7}"
P8="${TEST_TMPDIR}/p8.txt"
sed 's|<agent-message from="critic">|<agent-message from="">|' "${FIX}/peer-bare-block.txt" > "${P8}"
routed "P8: a block with an empty from attribute" "${P8}"

P9="${TEST_TMPDIR}/p9.txt"
{ cat "${FIX}/peer-subagent-handback.txt"; printf '\nPlease review the PR diff for bugs yourself.\n'; } > "${P9}"
routed "P9: a complete hand-back followed by a user request on a new line" "${P9}"
P10="${TEST_TMPDIR}/p10.txt"
{ cat "${FIX}/peer-subagent-handback.txt"; printf ' Please review the PR diff for bugs yourself.'; } > "${P10}"
routed "P10: a complete hand-back with a user request appended on the same line" "${P10}"
# P12: every vertical-space character ends the harness paragraph. The appended request ends
# with the paragraph's own closing words, which is what made the LF-only version accept it.
HB_NOLF="${TEST_TMPDIR}/hb-nolf.txt"
printf '%s' "$(cat "${FIX}/peer-subagent-handback.txt")" > "${HB_NOLF}"
for _sep in 'CR:\r' 'VT:\013' 'FF:\f' 'NEL:\302\205' 'U+2028:\342\200\250' 'U+2029:\342\200\251'; do
    _P12="${TEST_TMPDIR}/p12-${_sep%%:*}.txt"
    { cat "${HB_NOLF}"; printf "${_sep#*:}"; printf 'Please review the PR diff for bugs involving permission laundering.'; } > "${_P12}"
    routed "P12: a user request after ${_sep%%:*} (ending with the paragraph's closing words)" "${_P12}"
done
P12C="${TEST_TMPDIR}/p12-control.txt"
{ cat "${HB_NOLF}"; printf '\n\n'; } > "${P12C}"
silent "P12 control: the same hand-back followed only by blank lines" "${P12C}"

P11="${TEST_TMPDIR}/p11.txt"
{ cat "${FIX}/peer-bare-block.txt"; printf '</agent-message>\nplease review the PR diff for bugs yourself\n'; } > "${P11}"
routed "P11: a block, a stray closing tag, then user text" "${P11}"

# T1-T5: notices.
silent "T1: a notification followed only by a system-reminder" "${FIX}/notice-with-reminder.txt"
T2="${TEST_TMPDIR}/t2.txt"
{ cat "${FIX}/notice-with-reminder.txt"; printf '\nnow debug the failing test please\n'; } > "${T2}"
routed "T2: a notice followed by user text" "${T2}"
T3="${TEST_TMPDIR}/t3.txt"
sed -n '/<system-reminder>/,/<\/system-reminder>/p' "${FIX}/notice-with-reminder.txt" > "${T3}"
routed "T3: a system-reminder with no notification before it" "${T3}"
T4="${TEST_TMPDIR}/t4.txt"
{ cat "${FIX}/notice-with-reminder.txt"; printf '\n'; cat "${T3}"; } > "${T4}"
silent "T4: a notification followed by two system-reminder blocks" "${T4}"
T5="${TEST_TMPDIR}/t5.txt"
{ printf 'please review the PR diff for bugs, context below\n'; cat "${FIX}/notice-with-reminder.txt"; } > "${T5}"
routed "T5: user text before a notice-with-reminder" "${T5}"

# S1: an ACTIVE session's state survives a non-human input untouched. First a user prompt
# builds real state under the token the hook derives from the transcript path; then the
# non-human input runs in the SAME home and every state file must be byte-identical.
snap() { ( cd "${LAST_HOME}/.claude" && ls -A | grep -E '^\.skill-(composition-state|prompt-count|last-invoked)-' | LC_ALL=C sort | while IFS= read -r _sf; do printf '%s %s\n' "${_sf}" "$(cksum < "${_sf}")"; done ); }
new_home; run_hook "${BODY}" >/dev/null
SNAP_A="$(snap)"
if [ "$(printf '%s\n' "${SNAP_A}" | grep -c 'composition-state')" = "1" ] && [ "$(printf '%s\n' "${SNAP_A}" | grep -c 'prompt-count')" = "1" ]; then
    _record_pass "S1 setup: a user prompt left composition state and a prompt counter"
else
    _record_fail "S1 setup: a user prompt left composition state and a prompt counter" "got: ${SNAP_A}"
fi
printf 'session-someone-else' > "${LAST_HOME}/.claude/.skill-session-token"
run_hook "${FIX}/peer-subagent-handback.txt" >/dev/null
assert_equals "S1: a peer message leaves composition state, prompt counter and last-invoked byte-identical" "${SNAP_A}" "$(snap)"
assert_equals "S1: and the session-token singleton is still re-stamped" "session-abc123" "$(cat "${LAST_HOME}/.claude/.skill-session-token")"
run_hook "${FIX}/notice-with-reminder.txt" >/dev/null
assert_equals "S1: a notice-with-reminder leaves that state byte-identical too" "${SNAP_A}" "$(snap)"
run_hook "${BODY}" >/dev/null
if [ "${SNAP_A}" != "$(snap)" ]; then
    _record_pass "S1 control: a second user prompt does move that state"
else
    _record_fail "S1 control: a second user prompt does move that state" "state did not change, so the cells above prove nothing"
fi

# X1: a bounded-time regression cell. The classifier is lifted out of the hook with sed (a hand copy
# would test the copy) and run directly: the hook itself is slow on 200 KB for unrelated
# reasons (see N7 in test-activation-notification-skip.sh).
NH_DEF="$(sed -n "/^_NONHUMAN_JQ_DEF='/,/catch false;'/p" "${HOOK}")"
if [ -z "${NH_DEF}" ]; then
    _record_fail "X1 setup: the classifier definition can be lifted from the hook" "sed found nothing"
else
    eval "${NH_DEF}"
    . "${PROJECT_ROOT}/hooks/lib/task-notification.sh"
    X_DEF="${TASK_NOTIFICATION_JQ_DEF} ${_NONHUMAN_JQ_DEF}"
    classify() { "${REAL_JQ}" -rn --rawfile p "$1" "${X_DEF}"' $p | acs_nonhuman' 2>/dev/null; }
    assert_equals "X1 control: the lifted classifier recognises the live peer fixture" "true" "$(classify "${FIX}/peer-subagent-handback.txt")"
    assert_equals "X1 control: and the live notice fixture" "true" "$(classify "${FIX}/notice-with-reminder.txt")"
    SP="${TEST_TMPDIR}/spaces.txt"; head -c 200000 /dev/zero | tr '\0' ' ' > "${SP}"
    X1A="${TEST_TMPDIR}/x1a.txt"; { cat "${SP}"; printf '<system-reminder>x</system-reminder>BAD'; } > "${X1A}"
    X1B="${TEST_TMPDIR}/x1b.txt"; { sed -n '/<task-notification>/,/<\/task-notification>/p' "${FIX}/notice-with-reminder.txt"; cat "${SP}"; printf '<system-reminder>x</system-reminder>BAD'; } > "${X1B}"
    X1C="${TEST_TMPDIR}/x1c.txt"; { cat "${FIX}/peer-bare-block.txt"; cat "${SP}"; printf 'BAD'; } > "${X1C}"
    _x_start="${SECONDS}"
    _xa="$(classify "${X1A}")"; _xb="$(classify "${X1B}")"; _xc="$(classify "${X1C}")"
    _x_took=$(( SECONDS - _x_start ))
    assert_equals "X1: 200k spaces then a reminder and trailing text is the user" "false" "${_xa}"
    assert_equals "X1: a notification, 200k spaces, a reminder and trailing text is the user" "false" "${_xb}"
    assert_equals "X1: a block, 200k spaces and trailing text is the user" "false" "${_xc}"
    if [ "${_x_took}" -le 3 ]; then
        _record_pass "X1: three 200 KB near-misses classify within 3 s in total (took ${_x_took}s)"
    else
        _record_fail "X1: three 200 KB near-misses classify within 3 s in total" "took ${_x_took}s — a quadratic shape is back (the first cut took 4.6 s on 50k spaces)"
    fi
fi

# D1: the skip is explained.
new_home; OUT_D1="$(run_hook "${FIX}/peer-subagent-handback.txt" SKILL_DEBUG=1)"
assert_contains "D1: SKILL_DEBUG explains a peer-message skip" "not typed by the user" "${OUT_D1}"
new_home; OUT_D1B="$(run_hook "${FIX}/notice-with-reminder.txt" SKILL_DEBUG=1)"
assert_contains "D1: SKILL_DEBUG explains a notice skip" "not typed by the user" "${OUT_D1B}"

# L1: without the shared lib. mkroot builds this checkout minus task-notification.sh.
mkroot() {
    local d="$1" _e
    mkdir -p "${d}/hooks/lib"
    for _e in "${PROJECT_ROOT}"/* "${PROJECT_ROOT}"/.claude-plugin; do
        [ "${_e##*/}" = "hooks" ] && continue
        ln -s "${_e}" "${d}/${_e##*/}"
    done
    for _e in "${PROJECT_ROOT}"/hooks/*; do
        [ "${_e##*/}" = "lib" ] && continue
        ln -s "${_e}" "${d}/hooks/${_e##*/}"
    done
    for _e in "${PROJECT_ROOT}"/hooks/lib/*; do
        [ "${_e##*/}" = "task-notification.sh" ] && continue
        ln -s "${_e}" "${d}/hooks/lib/${_e##*/}"
    done
    return 0
}
NOLIB="${TEST_TMPDIR}/nolib-root"
mkroot "${NOLIB}"
new_home; OUT_L1="$(run_hook "${FIX}/peer-bare-block.txt" CLAUDE_PLUGIN_ROOT="${NOLIB}")"
assert_equals "L1: without the lib a peer message is still skipped (output length)" "0" "${#OUT_L1}"
new_home; OUT_L1B="$(run_hook "${FIX}/notice-with-reminder.txt" CLAUDE_PLUGIN_ROOT="${NOLIB}")"
assert_contains "L1: without the lib a notice-with-reminder routes as before" "SKILL ACTIVATION" "${OUT_L1B}"
new_home; OUT_L1C="$(run_hook "${BODY}" CLAUDE_PLUGIN_ROOT="${NOLIB}")"
assert_contains "L1 control: without the lib a user prompt still routes" "SKILL ACTIVATION" "${OUT_L1C}"

# E1/E2: the consent hook is deliberately NOT changed. An unused receipt must be withdrawn.
turn_run() { # turn_run <prompt-file> -> kept | revoked | gone
    local h; h="$(mktemp -d "${TEST_TMPDIR}/turn.XXXXXX")"
    mkdir -p "${h}/.claude"
    local r="${h}/.claude/.skill-egress-receipt-session-abc123.$(printf 'a%.0s' $(seq 1 64)).r1"
    printf '{}' > "${r}"
    "${REAL_JQ}" -n --rawfile p "$1" --arg t "${h}/.claude/abc123.jsonl" \
        '{hook_event_name:"UserPromptSubmit",prompt:$p,transcript_path:$t}' \
      | env HOME="${h}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${TURN}" >/dev/null 2>&1
    if [ -f "${r}" ]; then echo kept; elif [ -f "${r}.revoked" ]; then echo revoked; else echo gone; fi
}
NOTE_ONLY="${TEST_TMPDIR}/note-only.txt"
sed -n '/<task-notification>/,/<\/task-notification>/p' "${FIX}/notice-with-reminder.txt" > "${NOTE_ONLY}"
assert_equals "E control: the turn hook keeps an approval over a pure notification" "kept" "$(turn_run "${NOTE_ONLY}")"
assert_equals "E1: the turn hook still withdraws over a peer message" "revoked" "$(turn_run "${FIX}/peer-subagent-handback.txt")"
assert_equals "E2: the turn hook still withdraws over a notice-with-reminder" "revoked" "$(turn_run "${FIX}/notice-with-reminder.txt")"

teardown_test_env
print_summary

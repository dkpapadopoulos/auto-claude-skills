#!/usr/bin/env bash
# test-activation-notification-skip.sh — background-task notifications reach hooks as
# UserPromptSubmit prompts. The activation hook must not route them: their summaries are
# ordinary words ("Capture a second, path-normalised baseline" routed to second-opinion,
# observed live 2026-09-17), so every session with background jobs was getting skill
# suggestions nobody asked for, and chain-starting summaries could move composition state.
#
# The classifier (hooks/lib/task-notification.sh) is shared with egress-consent-turn-hook.sh,
# whose own cells live in tests/test-consult-dispatch.sh (R7-R10). What this file pins:
#   N1  control: the summary text on its own routes (so a silent result below means something)
#   N2  the same summary delivered as a notification routes nothing and writes no state
#   N3  a notification followed by user text still routes
#   N4  user text quoting the tag mid-line still routes
#   N5  two notification blocks route nothing
#   N6  SKILL_DEBUG=1 explains the skip
#   N7  a prompt the regex engine cannot evaluate is routed (treated as the user)
#   N8  without a usable shared lib (missing, or sourcing but not valid jq), the activation
#       hook routes as before and the turn hook still withdraws
#   N9  an "unclassifiable" prompt is routed by the hook itself
#   N10 a notification without transcript_path is still not routed
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-activation-notification-skip.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
TURN="${PROJECT_ROOT}/hooks/egress-consent-turn-hook.sh"
LIB="${PROJECT_ROOT}/hooks/lib/task-notification.sh"
REAL_JQ="$(command -v jq 2>/dev/null)"
if [ -z "${REAL_JQ}" ]; then
    _record_fail "jq available" "jq is required"
    print_summary
    exit 1
fi

setup_test_env
BASE_HOME="${TEST_TMPDIR}/base"
mkdir -p "${BASE_HOME}/.claude"
echo '{}' | HOME="${BASE_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    /bin/bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" >/dev/null 2>&1
FULL="${TEST_TMPDIR}/full.json"
"${REAL_JQ}" '.skills |= map(.available = true | .enabled = true) | .plugins |= map(.available = true)' \
    "${BASE_HOME}/.claude/.skill-registry-cache.json" > "${FULL}" 2>/dev/null

# new_home : a fresh HOME with the registry, in LAST_HOME (set in the CURRENT shell, so
# call it before a `$(run_hook ...)`, which runs in a subshell).
new_home() {
    LAST_HOME="$(mktemp -d "${TEST_TMPDIR}/run.XXXXXX")"
    mkdir -p "${LAST_HOME}/.claude"
}
# run_hook <prompt-file> [env...] : prints stdout and stderr, using LAST_HOME.
run_hook() {
    local pf="$1"; shift
    cp "${FULL}" "${LAST_HOME}/.claude/.skill-registry-cache.json"
    "${REAL_JQ}" -n --rawfile p "${pf}" --arg t "${LAST_HOME}/.claude/abc123.jsonl" \
        '{prompt:$p,transcript_path:$t}' \
      | env HOME="${LAST_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            SKILL_PROJECT_ROOT="${TEST_TMPDIR}" "$@" /bin/bash "${HOOK}" 2>&1
}
state_files() { ls "${LAST_HOME}"/.claude/.skill-composition-state-* 2>/dev/null | wc -l | tr -d ' '; }

# notification <summary> : the live-captured shape (fixture), with this summary.
notification() {
    sed "s|<summary>.*</summary>|<summary>$1</summary>|" \
        "${PROJECT_ROOT}/tests/fixtures/egress-consent/task-notification-bash.txt"
}

PLAIN="${TEST_TMPDIR}/plain.txt"
printf '%s' 'Background command "review the PR diff for bugs" completed (exit code 0)' > "${PLAIN}"
NOTE="${TEST_TMPDIR}/note.txt"
notification 'Background command "review the PR diff for bugs" completed (exit code 0)' > "${NOTE}"

# N1: control
new_home; OUT1="$(run_hook "${PLAIN}")"
assert_contains "N1 control: the summary text on its own routes" "SKILL ACTIVATION" "${OUT1}"
assert_equals "N1 control: it starts a composition chain" "1" "$(state_files)"

# N2: the notification is silent and stateless
if grep -q '<task-notification>' "${NOTE}" && grep -q 'review the PR diff' "${NOTE}"; then
    _record_pass "N2 setup: the notification carries the routable summary"
else
    _record_fail "N2 setup: the notification carries the routable summary" "fixture substitution failed"
fi
new_home; OUT2="$(run_hook "${NOTE}")"
assert_equals "N2: a notification-only prompt routes nothing (output length)" "0" "${#OUT2}"
assert_equals "N2: a notification-only prompt writes no composition state" "0" "$(state_files)"

# N3: notification + user text
MIXED="${TEST_TMPDIR}/mixed.txt"
{ cat "${NOTE}"; printf '\nnow review the PR diff for bugs please\n'; } > "${MIXED}"
new_home; OUT3="$(run_hook "${MIXED}")"
assert_contains "N3: user text after a notification still routes" "SKILL ACTIVATION" "${OUT3}"

# N4: quoted tag mid-line
QUOTE="${TEST_TMPDIR}/quote.txt"
printf '%s' 'review the PR diff for bugs, the parser mishandles <task-notification> blocks' > "${QUOTE}"
new_home; OUT4="$(run_hook "${QUOTE}")"
assert_contains "N4: a prompt quoting the tag still routes" "SKILL ACTIVATION" "${OUT4}"

# N5: two blocks
TWO="${TEST_TMPDIR}/two.txt"
{ cat "${NOTE}"; printf '\n'; cat "${NOTE}"; } > "${TWO}"
new_home; OUT5="$(run_hook "${TWO}")"
assert_equals "N5: two notification blocks route nothing (output length)" "0" "${#OUT5}"

# N6: debug breadcrumb
new_home; OUT6="$(run_hook "${NOTE}" SKILL_DEBUG=1)"
assert_contains "N6: SKILL_DEBUG explains the skip" "background-task notification" "${OUT6}"

# N7: unclassifiable -> the classifier says so, and the hook does not treat it as a
# notification. The hook itself is not run on a multi-MB prompt (routing would be slow);
# the classifier is exercised directly with the same jq definition the hooks use.
if [ -f "${LIB}" ]; then
    . "${LIB}"
    BIG="${TEST_TMPDIR}/big.txt"
    { printf '<task-notification>'; head -c 7000000 /dev/zero | tr '\0' 'x'; printf '\n'; } > "${BIG}"
    KIND7="$("${REAL_JQ}" -rn --rawfile p "${BIG}" "${TASK_NOTIFICATION_JQ_DEF}"' $p | notification_kind' 2>/dev/null)"
    assert_equals "N7: a prompt the regex engine cannot evaluate is 'unclassifiable'" "unclassifiable" "${KIND7}"
    KIND7N="$("${REAL_JQ}" -rn --rawfile p "${NOTE}" "${TASK_NOTIFICATION_JQ_DEF}"' $p | notification_kind' 2>/dev/null)"
    assert_equals "N7 control: the live fixture shape is 'notification'" "notification" "${KIND7N}"
else
    _record_fail "N7: shared classifier lib exists" "missing ${LIB}"
fi

# N8: without a usable lib. mkroot <dir> [lib-content-file] builds a plugin root that is this
# checkout with task-notification.sh removed or replaced (symlinks keep every other lib
# loadable).
mkroot() {
    local d="$1" libsrc="${2:-}" _e
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
    [ -n "${libsrc}" ] && cp "${libsrc}" "${d}/hooks/lib/task-notification.sh"
    return 0
}
NOLIB="${TEST_TMPDIR}/nolib-root"
mkroot "${NOLIB}"
new_home; OUT8="$(run_hook "${NOTE}" CLAUDE_PLUGIN_ROOT="${NOLIB}")"
assert_contains "N8: without the lib, the activation hook routes as before" "SKILL ACTIVATION" "${OUT8}"

# The turn hook, with an unused receipt present: a notification keeps it (lib present)...
turn_run() { # turn_run <plugin-root> <prompt-file> -> prints receipt state
    local h; h="$(mktemp -d "${TEST_TMPDIR}/turn.XXXXXX")"
    mkdir -p "${h}/.claude"
    local r="${h}/.claude/.skill-egress-receipt-session-abc123.$(printf 'a%.0s' $(seq 1 64)).r1"
    printf '{}' > "${r}"
    "${REAL_JQ}" -n --rawfile p "$2" --arg t "${h}/.claude/abc123.jsonl" \
        '{hook_event_name:"UserPromptSubmit",prompt:$p,transcript_path:$t}' \
      | env HOME="${h}" CLAUDE_PLUGIN_ROOT="$1" /bin/bash "${TURN}" >/dev/null 2>&1
    if [ -f "${r}" ]; then echo kept; elif [ -f "${r}.revoked" ]; then echo revoked; else echo gone; fi
}
assert_equals "N8 control: with the lib, the turn hook keeps an approval over a notification" \
    "kept" "$(turn_run "${PROJECT_ROOT}" "${NOTE}")"
assert_equals "N8: without the lib, the turn hook withdraws (the safe direction)" \
    "revoked" "$(turn_run "${NOLIB}" "${NOTE}")"
assert_equals "N8 control: with the lib, a user prompt still withdraws" \
    "revoked" "$(turn_run "${PROJECT_ROOT}" "${PLAIN}")"

# A lib that SOURCES but whose jq does not compile (a syntax slip, a renamed function after a
# partial update) must fall back exactly like a missing lib, not break the jq call: the turn
# hook would otherwise report the payload unparseable and KEEP approvals over a user prompt,
# and the activation hook would drop every prompt.
_i=0
for _def in 'def notification_kind: ;' 'def notification_kind: "prompt"' 'def task_kind: "prompt";' ' '; do
    _i=$((_i + 1))
    printf "TASK_NOTIFICATION_JQ_DEF='%s'\n" "${_def}" > "${TEST_TMPDIR}/badlib${_i}.sh"
    BADROOT="${TEST_TMPDIR}/badroot${_i}"
    mkroot "${BADROOT}" "${TEST_TMPDIR}/badlib${_i}.sh"
    new_home; OUTB="$(run_hook "${PLAIN}" CLAUDE_PLUGIN_ROOT="${BADROOT}")"
    assert_contains "N8: broken lib #${_i}, the activation hook still routes a user prompt" \
        "SKILL ACTIVATION" "${OUTB}"
    assert_equals "N8: broken lib #${_i}, the turn hook still withdraws over a user prompt" \
        "revoked" "$(turn_run "${BADROOT}" "${PLAIN}")"
done

# N9: the hook routes a prompt the classifier calls "unclassifiable". A lib that says so for
# every prompt stands in for a multi-MB prompt, which would make the hook slow to run here.
printf '%s\n' "TASK_NOTIFICATION_JQ_DEF='def notification_kind: \"unclassifiable\";'" > "${TEST_TMPDIR}/unclass.sh"
UNROOT="${TEST_TMPDIR}/unclass-root"
mkroot "${UNROOT}" "${TEST_TMPDIR}/unclass.sh"
new_home; OUT9="$(run_hook "${NOTE}" CLAUDE_PLUGIN_ROOT="${UNROOT}")"
assert_contains "N9: an unclassifiable prompt is routed" "SKILL ACTIVATION" "${OUT9}"

# N10: a notification without a transcript_path is still not routed.
new_home
cp "${FULL}" "${LAST_HOME}/.claude/.skill-registry-cache.json"
OUT10="$("${REAL_JQ}" -n --rawfile p "${NOTE}" '{prompt:$p}' \
  | env HOME="${LAST_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${TEST_TMPDIR}" \
        /bin/bash "${HOOK}" 2>&1)"
assert_equals "N10: a notification without transcript_path routes nothing (output length)" "0" "${#OUT10}"

teardown_test_env
print_summary

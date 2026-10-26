#!/usr/bin/env bash
# test-typed-slash-credit.sh — a TYPED slash command naming an installed, credited
# REVIEW skill earns the same evidence as a Skill tool return (openspec change
# review-credit-from-evidence, design decision 1).
#
# Measured on Claude Code 2.1.308: a typed "/name args" reaches UserPromptSubmit as the
# raw text and fires no Skill tool hook, so without this nothing records it. The routing
# hook's slash early exit now first calls hooks/lib/typed-slash-credit.sh, which pipes a
# synthetic PostToolUse(Skill) payload (acs_source "typed-slash") to the REAL completion
# hook. Every cell drives the REAL activation hook (and, for e2e, the REAL push guard) in
# a sandbox HOME, from a throwaway non-routing repo, so routing-governance cannot deny.
#
#   S1  /superpowers:requesting-code-review args == a real Skill return, field by field
#   S2  /code-review (built-in, no registry entry) credits
#   S3  /pr-review-toolkit:review-pr 12 (plugin command) credits
#   S4  a mid-text mention records nothing
#   S5  a task notification carrying the command records nothing (pins the :281 exit);
#       the push still denies
#   S6  the prompt-kind gate is load-bearing (an "unclassifiable" kind credits nothing)
#   S7  uncredited names (/simplify, /receiving-code-review) record nothing
#   S8  uninstalled names record nothing (each with an installed control)
#   S9  a typed /superpowers:verification-before-completion records no VERIFY milestone
#   S10 credited-skills.sh unreadable: nothing, exit 0, empty stdout
#   S11 fork cell: jq calls on non-slash / uncredited-slash prompts equal the pre-change hook's
#   S12 registry missing or corrupt: built-ins only
#   S13 e2e: /code-review lets the push through; a mention does not
#   S14 leading whitespace, a tab or a newline after the name still credit
#   S15 malformed first tokens record nothing; the 100-char bound is pinned both sides
#   S16 repeats and a later real return do not duplicate evidence
#   S17 typed credit writes no advisory-lens line (a real return does)
#   U*  unit cells on the lib's functions, incl. every non-"prompt" kind
#   X*  cross-session messages carrying the command record nothing (hook-level pins)
#   S5b a prompt that BEGINS with the command credits though notification text follows
#   F*  the lib's first-token rule refuses wrapped and mid-text commands on its own
#   L*  a lib faulting at load or call leaves the hook at exit 0 with empty stdout
#   W*  carriage return and (UTF-8) no-break space before the first token credit
#   V*  a typed BUILT-IN credits only on Claude Code >= 2.1.308 (AI_AGENT); registry
#       skills credit whatever the version; without acs_cc_version only built-ins fail
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-typed-slash-credit.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
COMPLETION="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
LIB="${PROJECT_ROOT}/hooks/lib/typed-slash-credit.sh"
REAL_JQ="$(command -v jq 2>/dev/null)"
if [ -z "${REAL_JQ}" ]; then
    _record_fail "jq available" "jq is required"
    print_summary
    exit 1
fi

setup_test_env
trap 'rm -rf "${TEST_TMPDIR}"' EXIT
# Built-in typed credit requires Claude Code >= 2.1.308 read from AI_AGENT (cells V).
# Pinned for the whole file so the cells do not depend on the caller's harness.
AI_AGENT_OK="claude-code_2-1-308_harness"
export AI_AGENT="${AI_AGENT_OK}"
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"

# A throwaway NON-routing repo (no config/default-triggers.json) with one commit.
# Physical path: the ledger is keyed on `git rev-parse --show-toplevel`, which resolves
# macOS's /var -> /private/var, so a logical path would read another key.
mkdir -p "${TEST_TMPDIR}/repo"
REPO="$(cd "${TEST_TMPDIR}/repo" && pwd -P)"
git -C "${REPO}" init -q -b feature 2>/dev/null || { git -C "${REPO}" init -q; git -C "${REPO}" checkout -q -b feature; }
git -C "${REPO}" config user.email t@example.com
git -C "${REPO}" config user.name t
printf 'x\n' > "${REPO}/a.txt"
git -C "${REPO}" add a.txt && git -C "${REPO}" commit -q -m init
REPO_HEAD="$(git -C "${REPO}" rev-parse HEAD)"

# Registry fixture.
REG="${TEST_TMPDIR}/registry.json"
"${REAL_JQ}" -n '{
  skills: [
    {name:"requesting-code-review", invoke:"Skill(superpowers:requesting-code-review)", available:true, enabled:true},
    {name:"verification-before-completion", invoke:"Skill(superpowers:verification-before-completion)", available:true, enabled:true},
    {name:"receiving-code-review", invoke:"Skill(superpowers:receiving-code-review)", available:true, enabled:true}
  ],
  plugins: [
    {name:"pr-review-toolkit", available:true, provides:{commands:["/review-pr"], skills:[], agents:[], hooks:[]}}
  ]
}' > "${REG}"

TOK="session-t"
# _new_home [registry-file|none] : a fresh HOME (exported in THIS shell), chain armed.
_new_home() {
    _H="$(mktemp -d "${TEST_TMPDIR}/h.XXXXXX")"
    export HOME="${_H}"
    mkdir -p "${HOME}/.claude"
    _TP="${HOME}/t.jsonl"; : > "${_TP}"
    case "${1:-${REG}}" in
        none) ;;
        *) cp "${1:-${REG}}" "${HOME}/.claude/.skill-registry-cache.json" ;;
    esac
    printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' \
        > "${HOME}/.claude/.skill-composition-state-${TOK}"
}
# _turn <prompt> [plugin-root] [extra env...] : the REAL activation hook from REPO
# (or the hook file named by _TURN_HOOK, which only S11 sets). Sets _OUT and _RC.
_turn() {
    local _p="$1" _root="${2:-${PROJECT_ROOT}}"
    shift; [ "$#" -gt 0 ] && shift
    _OUT="$("${REAL_JQ}" -nc --arg p "${_p}" --arg t "${_TP}" --arg c "${REPO}" \
            '{prompt:$p, transcript_path:$t, session_id:"sid-typed", cwd:$c}' \
        | ( cd "${REPO}" && env CLAUDE_PLUGIN_ROOT="${_root}" "$@" /bin/bash "${_TURN_HOOK:-${HOOK}}" 2>/dev/null ))"
    _RC=$?
}
# _turn_raw <prompt-file> : same, prompt read from a file (keeps exact bytes).
_turn_raw() {
    _OUT="$("${REAL_JQ}" -nc --rawfile p "$1" --arg t "${_TP}" --arg c "${REPO}" \
            '{prompt:$p, transcript_path:$t, session_id:"sid-typed", cwd:$c}' \
        | ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${HOOK}" 2>/dev/null ))"
    _RC=$?
}
# _skill_return <skill> : a real-shaped PostToolUse(Skill) payload to the REAL completion hook.
_skill_return() {
    "${REAL_JQ}" -nc --arg s "$1" --arg t "${_TP}" --arg c "${REPO}" \
        '{session_id:"sid-typed", transcript_path:$t, cwd:$c, hook_event_name:"PostToolUse",
          tool_name:"Skill", tool_input:{skill:$s},
          tool_response:{success:true, commandName:$s, content:"line1\nline2"}}' \
    | ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${COMPLETION}" ) >/dev/null 2>&1
}
# _push : the REAL guard on a push from REPO.
_push() {
    "${REAL_JQ}" -nc --arg tp "${_TP}" --arg c "git push origin HEAD" \
        '{transcript_path:$tp, tool_name:"Bash", tool_input:{command:$c}}' \
    | ( cd "${REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null )
}
_seed_verify() { ( cd "${REPO}" && branch_ledger_record verification-before-completion "${REPO}" ) >/dev/null 2>&1; }

_INVOC() { printf '%s' "${HOME}/.claude/.skill-invocation-evidence-${TOK}"; }
_SIDECAR() { printf '%s' "${HOME}/.claude/.skill-invocation-evidence-sha-${TOK}"; }
_has_review() { branch_ledger_has requesting-code-review "${REPO}"; }

# _expect_nothing <label> : no evidence of any kind, exit 0, empty stdout.
_expect_nothing() {
    if [ -e "$(_INVOC)" ]; then
        _record_fail "$1: no invocation evidence" "$(cat "$(_INVOC)")"
    else
        _record_pass "$1: no invocation evidence"
    fi
    if _has_review; then
        _record_fail "$1: no REVIEW ledger milestone" "ledger has requesting-code-review"
    else
        _record_pass "$1: no REVIEW ledger milestone"
    fi
    assert_equals "$1: exit 0" "0" "${_RC}"
    assert_equals "$1: empty stdout" "" "${_OUT}"
}
# _expect_credit <label> <bare-name-in-invocation-evidence>
_expect_credit() {
    if _has_review; then
        _record_pass "$1: REVIEW ledger milestone recorded"
    else
        _record_fail "$1: REVIEW ledger milestone recorded" "no requesting-code-review"
    fi
    if [ -f "$(_INVOC)" ] && "${REAL_JQ}" -e --arg s "$2" 'index($s) != null' "$(_INVOC)" >/dev/null 2>&1; then
        _record_pass "$1: invocation evidence holds $2"
    else
        _record_fail "$1: invocation evidence holds $2" "$(cat "$(_INVOC)" 2>/dev/null || echo '<none>')"
    fi
    assert_equals "$1: exit 0" "0" "${_RC}"
    assert_equals "$1: empty stdout" "" "${_OUT}"
}

# _snapshot : the four evidence facts, one per line, HOME-relative.
_snapshot() {
    local _d _sha=""
    _d="$(branch_ledger_dir "${REPO}")" && [ -f "${_d}/requesting-code-review" ] && \
        _sha="$(cut -d' ' -f1 "${_d}/requesting-code-review")"
    printf 'invoc=%s\n' "$(cat "$(_INVOC)" 2>/dev/null | "${REAL_JQ}" -c . 2>/dev/null)"
    printf 'sidecar=%s\n' "$(cat "$(_SIDECAR)" 2>/dev/null)"
    printf 'ledger_sha=%s\n' "${_sha}"
    printf 'completed=%s\n' "$("${REAL_JQ}" -c '.completed' "${HOME}/.claude/.skill-composition-state-${TOK}" 2>/dev/null)"
}

# ---------------------------------------------------------------------------------------
# S1: a typed namespaced review command == a real Skill return (twin sandboxes)
_new_home
_turn "/superpowers:requesting-code-review check the diff"
S1_TYPED="$(_snapshot)"
_expect_credit "S1 typed /superpowers:requesting-code-review" "requesting-code-review"
_new_home
_skill_return "superpowers:requesting-code-review"
S1_REAL="$(_snapshot)"
assert_contains "S1 control: the real Skill return recorded a ledger sha" "ledger_sha=${REPO_HEAD}" "${S1_REAL}"
assert_contains "S1 control: the real Skill return recorded .completed" '"requesting-code-review"' "${S1_REAL}"
assert_equals "S1: typed evidence equals the real Skill return's (invocation, sidecar, ledger sha, .completed)" \
    "${S1_REAL}" "${S1_TYPED}"

# S2: built-in with no registry entry
_new_home
_turn "/code-review"
_expect_credit "S2 /code-review" "code-review"

# S3: a plugin command, namespaced, with args
_new_home
_turn "/pr-review-toolkit:review-pr 12"
_expect_credit "S3 /pr-review-toolkit:review-pr 12" "review-pr"

# S4: a mid-text mention
_new_home
_turn "please run /superpowers:requesting-code-review"
if [ -e "$(_INVOC)" ]; then _record_fail "S4 mention: no invocation evidence" "$(cat "$(_INVOC)")"
else _record_pass "S4 mention: no invocation evidence"; fi
if _has_review; then _record_fail "S4 mention: no REVIEW ledger milestone" "recorded"
else _record_pass "S4 mention: no REVIEW ledger milestone"; fi
_seed_verify
S4_PUSH="$(_push)"
assert_contains "S13b e2e: after a mention the push denies" '"deny"' "${S4_PUSH:-<empty>}"
assert_contains "S13b e2e: and names requesting-code-review" "requesting-code-review" "${S4_PUSH:-<empty>}"

# S5: a live-shaped task notification whose body carries the command.
# At HOOK level this is a REGRESSION PIN of the notification early exit
# (skill-activation-hook.sh:281): a pure notification never reaches the slash line, so
# these hook cells pass with or without the lib. What makes the lib's own first-token
# rule decide such text is cell F below, which calls the lib directly.
_new_home
NOTE="${TEST_TMPDIR}/note.txt"
sed 's|<summary>.*</summary>|<summary>Background command /superpowers:requesting-code-review completed</summary>|' \
    "${PROJECT_ROOT}/tests/fixtures/egress-consent/task-notification-bash.txt" > "${NOTE}"
if grep -qF ' /superpowers:requesting-code-review ' "${NOTE}"; then
    _record_pass "S5 setup: the notification carries the command"
else
    _record_fail "S5 setup: the notification carries the command" "sed did not apply"
fi
_turn_raw "${NOTE}"
_expect_nothing "S5 task notification (pin of the :281 early exit)"
_seed_verify
S5_PUSH="$(_push)"
assert_contains "S5: the push still denies" '"deny"' "${S5_PUSH:-<empty>}"
assert_contains "S5: and names requesting-code-review" "requesting-code-review" "${S5_PUSH:-<empty>}"

# S5b: the rule is the FIRST token. A prompt the person BEGINS with a typed credited
# command credits even when other text follows it -- here the live notification fixture,
# as if pasted after the command. The person typed the command first; what follows it
# cannot un-type it, and a notification cannot put text in front of it (a pure
# notification exits at :281, and anything else leading the prompt is not a slash).
_new_home
NOTE2="${TEST_TMPDIR}/note2.txt"
{ printf '/superpowers:requesting-code-review\n'; cat "${PROJECT_ROOT}/tests/fixtures/egress-consent/task-notification-bash.txt"; } > "${NOTE2}"
_turn_raw "${NOTE2}"
_expect_credit "S5b first token typed, notification text after it: credits" "requesting-code-review"

# S6: the kind gate is load-bearing. A copied plugin root whose shared classifier yields
# "unclassifiable" for everything; the stock-lib copy is the positive control.
COPY_STOCK="${TEST_TMPDIR}/root-stock"; COPY_UNCL="${TEST_TMPDIR}/root-uncl"
COPY_NOCRED="${TEST_TMPDIR}/root-nocred"; COPY_NOTS="${TEST_TMPDIR}/root-nots"
for _d in "${COPY_STOCK}" "${COPY_UNCL}" "${COPY_NOCRED}" "${COPY_NOTS}"; do
    mkdir -p "${_d}" && cp -R "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/config" "${_d}/"
done
printf '%s\n' "TASK_NOTIFICATION_JQ_DEF='def notification_kind: \"unclassifiable\";'" \
    > "${COPY_UNCL}/hooks/lib/task-notification.sh"
rm -f "${COPY_NOCRED}/hooks/lib/credited-skills.sh"
rm -f "${COPY_NOTS}/hooks/lib/typed-slash-credit.sh"
if [ -f "${COPY_STOCK}/hooks/lib/typed-slash-credit.sh" ] && [ -f "${COPY_STOCK}/hooks/lib/credited-skills.sh" ] \
   && grep -q unclassifiable "${COPY_UNCL}/hooks/lib/task-notification.sh" \
   && [ ! -e "${COPY_NOCRED}/hooks/lib/credited-skills.sh" ] && [ -f "${COPY_NOCRED}/hooks/lib/typed-slash-credit.sh" ] \
   && [ ! -e "${COPY_NOTS}/hooks/lib/typed-slash-credit.sh" ]; then
    _record_pass "S6 setup: plugin-root copies built as intended"
else
    _record_fail "S6 setup: plugin-root copies built as intended" "copy setup wrong"
fi
_new_home
_turn "/code-review" "${COPY_UNCL}"
_expect_nothing "S6 kind unclassifiable: /code-review"
_new_home
_turn "/code-review" "${COPY_STOCK}"
_expect_credit "S6 control: the stock-lib copy credits /code-review" "code-review"

# S7: uncredited names
for _p in "/simplify" "/receiving-code-review" "/superpowers:receiving-code-review"; do
    _new_home; _turn "${_p}"
    _expect_nothing "S7 uncredited ${_p}"
done

# S8: uninstalled names, each with an installed control
REG_NO_RCR="${TEST_TMPDIR}/reg-no-rcr.json"
"${REAL_JQ}" '.skills |= map(select(.name != "requesting-code-review"))' "${REG}" > "${REG_NO_RCR}"
REG_RCR_OFF="${TEST_TMPDIR}/reg-rcr-off.json"
"${REAL_JQ}" '.skills |= map(if .name == "requesting-code-review" then .available = false else . end)' "${REG}" > "${REG_RCR_OFF}"
REG_PLUG_OFF="${TEST_TMPDIR}/reg-plug-off.json"
"${REAL_JQ}" '.plugins |= map(.available = false)' "${REG}" > "${REG_PLUG_OFF}"
_new_home "${REG_NO_RCR}"; _turn "/superpowers:requesting-code-review"
_expect_nothing "S8 registry without the skill: /superpowers:requesting-code-review"
_new_home "${REG_RCR_OFF}"; _turn "/superpowers:requesting-code-review"
_expect_nothing "S8 skill available:false: /superpowers:requesting-code-review"
_new_home; _turn "/foo:requesting-code-review"
_expect_nothing "S8 wrong prefix: /foo:requesting-code-review"
_new_home; _turn "/foo:review-pr"
_expect_nothing "S8 wrong plugin prefix: /foo:review-pr"
_new_home "${REG_PLUG_OFF}"; _turn "/review-pr"
_expect_nothing "S8 plugin available:false: /review-pr"
_new_home "${REG_PLUG_OFF}"; _turn "/pr-review-toolkit:review-pr"
_expect_nothing "S8 plugin available:false: /pr-review-toolkit:review-pr"
_new_home; _turn "/security-review:security-review"
_expect_nothing "S8 a prefixed built-in is not a built-in: /security-review:security-review"
_new_home; _turn "/requesting-code-review"
_expect_credit "S8 control: bare /requesting-code-review (installed) credits" "requesting-code-review"
_new_home; _turn "/review-pr"
_expect_credit "S8 control: bare /review-pr (plugin available) credits" "review-pr"
_new_home; _turn "/security-review"
_expect_credit "S8 control: built-in /security-review credits" "security-review"

# S9: a typed VERIFY skill credits nothing
_new_home
_turn "/superpowers:verification-before-completion"
if branch_ledger_has verification-before-completion "${REPO}"; then
    _record_fail "S9: no verification-before-completion ledger milestone" "recorded"
else
    _record_pass "S9: no verification-before-completion ledger milestone"
fi
if [ -f "$(_INVOC)" ] && grep -q verification-before-completion "$(_INVOC)"; then
    _record_fail "S9: not in invocation evidence" "$(cat "$(_INVOC)")"
else
    _record_pass "S9: not in invocation evidence"
fi
_expect_nothing "S9 /superpowers:verification-before-completion"

# S10: credited-skills.sh unreadable => no typed credit at all
_new_home
_turn "/code-review" "${COPY_NOCRED}"
_expect_nothing "S10 credited-skills.sh missing: /code-review"

# S11: fork cell. Same shape as the jq shim in tests/test-activation-registry-extract.sh
# (C1): one script on PATH logs each call and execs the real jq.
SHIM="${TEST_TMPDIR}/shim"; mkdir -p "${SHIM}"
cat > "${SHIM}/jq" <<EOF
#!/bin/bash
printf 'x\n' >> "\${JQ_COUNT_LOG}"
exec "${REAL_JQ}" "\$@"
EOF
chmod +x "${SHIM}/jq"
# _jq_calls <prompt> <root> : prints how many jq processes one turn of <root>'s OWN
# activation hook started (roots differ only in the files the cells name).
_jq_calls() {
    local _log
    _new_home
    _log="${HOME}/jq-count.log"; : > "${_log}"
    _TURN_HOOK="$2/hooks/skill-activation-hook.sh"
    _turn "$1" "$2" PATH="${SHIM}:${PATH}" JQ_COUNT_LOG="${_log}"
    wc -l < "${_log}" | tr -d ' '
}
# The counterfactual is the hook as it was BEFORE this change, so a mutant that adds a
# fork to the non-slash path -- on line 397's left side, say -- is counted in one arm
# only. (Comparing against a lib-deleted copy of the CURRENT hook could not see it: both
# arms would run the same line.) It is built from the CURRENT hook with the slash line
# put back to the pre-change literal, NOT read from git history: a shallow clone or a
# rewritten branch would turn a history read red, and one red test blocks every push.
COPY_BASE="${TEST_TMPDIR}/root-base"
mkdir -p "${COPY_BASE}" && cp -R "${COPY_STOCK}/hooks" "${COPY_STOCK}/config" "${COPY_BASE}/"
# The slash line is found by text unique to it ANYWHERE on the line (a literal `index`,
# not a regex), so a fork prepended to it is swapped out with it and shows in the counts.
# Values via ENVIRON, since awk -v would process backslash escapes. LIMIT: a fork added on
# some OTHER line is copied into both arms and is not seen here; this pins line 397.
S11_SLASH_MARK='hooks/lib/typed-slash-credit.sh" ]] && ('
S11_OLD_LINE='[[ "$PROMPT" =~ ^[[:space:]]*/ ]] && exit 0'
S11_MARK="${S11_SLASH_MARK}" S11_OLD="${S11_OLD_LINE}" awk '
    index($0, ENVIRON["S11_MARK"]) > 0 { print ENVIRON["S11_OLD"]; n++; next }
    { print }
    END { print n + 0 > "/dev/stderr" }' \
    "${COPY_STOCK}/hooks/skill-activation-hook.sh" \
    > "${COPY_BASE}/hooks/skill-activation-hook.sh" 2> "${TEST_TMPDIR}/s11-subst-count"
assert_equals "S11 setup: exactly one slash line was replaced in the baseline hook" "1" \
    "$(tr -d ' \n' < "${TEST_TMPDIR}/s11-subst-count")"
if ! cmp -s "${COPY_STOCK}/hooks/skill-activation-hook.sh" "${COPY_BASE}/hooks/skill-activation-hook.sh" \
   && grep -qxF "${S11_OLD_LINE}" "${COPY_BASE}/hooks/skill-activation-hook.sh" \
   && ! grep -qF "${S11_SLASH_MARK}" "${COPY_BASE}/hooks/skill-activation-hook.sh" \
   && grep -qF "${S11_SLASH_MARK}" "${COPY_STOCK}/hooks/skill-activation-hook.sh" \
   && [ "$(wc -l < "${COPY_BASE}/hooks/skill-activation-hook.sh")" = "$(wc -l < "${COPY_STOCK}/hooks/skill-activation-hook.sh")" ]; then
    _record_pass "S11 setup: the baseline differs from the stock hook only by the pre-change slash line"
else
    _record_fail "S11 setup: the baseline differs from the stock hook only by the pre-change slash line" \
        "substitution did not apply, or the copies are wrong"
fi
for _p in "please refactor the parser" "fix the failing login test" "/simplify x"; do
    _with="$(_jq_calls "${_p}" "${COPY_STOCK}")"
    _base="$(_jq_calls "${_p}" "${COPY_BASE}")"
    if [ "${_with}" -gt 0 ] 2>/dev/null; then
        _record_pass "S11 setup: the shim counted jq calls for '${_p}' (${_with})"
    else
        _record_fail "S11 setup: the shim counted jq calls for '${_p}'" "count '${_with}'"
    fi
    assert_equals "S11 '${_p}': jq calls now == with the pre-change slash line" "${_base}" "${_with}"
done
# The lib itself adds no jq to an uncredited slash command (kills a lib that forks first).
assert_equals "S11 '/simplify x': jq calls with the lib == without it" \
    "$(_jq_calls "/simplify x" "${COPY_NOTS}")" "$(_jq_calls "/simplify x" "${COPY_STOCK}")"
_with="$(_jq_calls "/code-review" "${COPY_STOCK}")"
_without="$(_jq_calls "/code-review" "${COPY_NOTS}")"
if [ "${_with}" -gt "${_without}" ] 2>/dev/null; then
    _record_pass "S11 control: /code-review starts more jq with the lib (${_with} > ${_without})"
else
    _record_fail "S11 control: /code-review starts more jq with the lib" "with=${_with} without=${_without}"
fi

# S12: registry missing, then corrupt => built-ins only
for _mode in none corrupt; do
    _new_home none
    [ "${_mode}" = corrupt ] && printf 'not json' > "${HOME}/.claude/.skill-registry-cache.json"
    _turn "/code-review"
    _expect_credit "S12 registry ${_mode}: /code-review" "code-review"
    _new_home none
    [ "${_mode}" = corrupt ] && printf 'not json' > "${HOME}/.claude/.skill-registry-cache.json"
    _turn "/superpowers:requesting-code-review"
    _expect_nothing "S12 registry ${_mode}: /superpowers:requesting-code-review"
    _new_home none
    [ "${_mode}" = corrupt ] && printf 'not json' > "${HOME}/.claude/.skill-registry-cache.json"
    _turn "/pr-review-toolkit:review-pr"
    _expect_nothing "S12 registry ${_mode}: /pr-review-toolkit:review-pr"
done

# S13: e2e — a typed /code-review lets the push through (S13b is in S4 above)
_new_home
_seed_verify
S13_PRE="$(_push)"
assert_contains "S13 control: before the typed command the push denies on REVIEW" "requesting-code-review" "${S13_PRE:-<empty>}"
_turn "/code-review"
S13_POST="$(_push)"
assert_not_contains "S13: after /code-review the push emits no deny" '"deny"' "${S13_POST:-<empty>}"

# S14: whitespace shapes that still credit
for _p in "   /code-review" "$(printf '/code-review\targs')" "$(printf '/code-review\nmore text')" "$(printf '\n\t /code-review')"; do
    _new_home; _turn "${_p}"
    _expect_credit "S14 '$(printf '%s' "${_p}" | tr '\t\n' 'TN')'" "code-review"
done

# S15: malformed first tokens; and the 100-char bound, pinned on both sides through a
# registry plugin whose prefix makes the typed name exactly 100, 101 and 200 chars.
_pfx() { printf "%${1}s" "" | tr ' ' 'p'; }
P90="$(_pfx 90)"; P91="$(_pfx 91)"; P190="$(_pfx 190)"
REG_LONG="${TEST_TMPDIR}/reg-long.json"
"${REAL_JQ}" --arg a "${P90}" --arg b "${P91}" --arg c "${P190}" \
    '.plugins += [($a, $b, $c) | {name:., available:true, provides:{commands:["/review-pr"]}}]' "${REG}" > "${REG_LONG}"
assert_equals "S15 setup: the 100-char name is 100 chars" "100" "$(printf '%s' "${P90}:review-pr" | wc -c | tr -d ' ')"
for _p in "/" "/ code-review" "/code-review:" "/a:b:code-review" "//code-review" "/:code-review" \
          "/code-review/x" "/pr-review-toolkit:x:review-pr" "/${P190}:review-pr" "/${P91}:review-pr" "/code-review;x"; do
    _new_home "${REG_LONG}"; _turn "${_p}"
    _expect_nothing "S15 malformed '$(printf '%.40s' "${_p}")' (len ${#_p})"
done
_new_home "${REG_LONG}"; _turn "/${P90}:review-pr"
_expect_credit "S15 control: a 100-char name credits" "review-pr"

# S16: repeats and a later real return do not duplicate
_new_home
_turn "/code-review"; _turn "/code-review"
# Mid-sequence: the two typed turns did record (else the final counts hold vacuously).
assert_equals "S16: two typed turns leave code-review in invocation evidence once" "1" \
    "$("${REAL_JQ}" '[.[] | select(. == "code-review")] | length' "$(_INVOC)" 2>/dev/null)"
_skill_return "code-review"
assert_equals "S16: invocation evidence holds code-review once" "1" \
    "$("${REAL_JQ}" '[.[] | select(. == "code-review")] | length' "$(_INVOC)" 2>/dev/null)"
assert_equals "S16: sidecar holds one code-review line" "1" \
    "$(grep -c "^code-review ${REPO_HEAD}\$" "$(_SIDECAR)" 2>/dev/null)"

# S17: no advisory-lens telemetry from a typed credit; a real return writes one line
_new_home
_turn "/code-review"
assert_equals "S17: typed credit writes no advisory-lens line" "0" \
    "$(cat "${HOME}/.claude/.advisory-lens-log.jsonl" 2>/dev/null | wc -l | tr -d ' ')"
_skill_return "code-review"
assert_equals "S17 control: a real Skill return writes one" "1" \
    "$(cat "${HOME}/.claude/.advisory-lens-log.jsonl" 2>/dev/null | wc -l | tr -d ' ')"

# X: cross-session messages carrying the command. Like S5, at HOOK level these are
# REGRESSION PINS: text that does not begin with `/` never reaches the slash line, so
# they pass with or without the lib. Cells F below put the same texts to the lib.
_new_home
_turn "$(printf '<agent-message from="peer">\n/code-review\n</agent-message>')"
if _has_review || [ -e "$(_INVOC)" ]; then _record_fail "X1 peer message carrying /code-review records nothing" "recorded"
else _record_pass "X1 peer message carrying /code-review records nothing"; fi
_new_home
_turn "$(printf '<cross-session-message from="other">/code-review</cross-session-message>')"
if _has_review || [ -e "$(_INVOC)" ]; then _record_fail "X2 cross-session message carrying /code-review records nothing" "recorded"
else _record_pass "X2 cross-session message carrying /code-review records nothing"; fi

# F: the lib's FIRST-TOKEN rule decides wrapped and mid-text commands on its own.
# typed_slash_credit is called directly with kind "prompt" -- the hook's earlier exits
# (the :281 notification exit, the `^[[:space:]]*/` slash test) are bypassed, so only
# the lib's own first-token check stands between each text and a credit. Each text
# carries a credited, installed command as a whitespace-separated token.
_unit_text() {   # <prompt-text> ; run in a subshell from REPO; HOME from _new_home
    local _in; _in="$("${REAL_JQ}" -nc --arg p "$1" --arg t "${_TP}" '{prompt:$p, transcript_path:$t, session_id:"s"}')"
    ( cd "${REPO}" && . "${LIB}" && typed_slash_credit prompt "$1" "${_in}" "${PROJECT_ROOT}" ) >/dev/null 2>&1
}
_f_nothing() {   # <label> <text>
    _new_home; _unit_text "$2"
    if _has_review || [ -e "$(_INVOC)" ]; then _record_fail "$1: the lib credits nothing" "recorded"
    else _record_pass "$1: the lib credits nothing"; fi
}
_f_nothing "F1 task notification with the command in its summary" "$(cat "${NOTE}")"
_f_nothing "F2 peer <agent-message> with the command on its own line" "$(printf '<agent-message from="peer">\n/code-review\n</agent-message>')"
_f_nothing "F3 <cross-session-message> with the command on its own line" "$(printf '<cross-session-message from="other">\n/code-review\n</cross-session-message>')"
_f_nothing "F4 harness intro line, then the command" "$(printf 'Another Claude session sent a message:\n/code-review')"
_f_nothing "F5 a mid-text mention" "please run /superpowers:requesting-code-review now"
_new_home; _unit_text "$(cat "${NOTE2}")"
if _has_review; then _record_pass "F6 control: the same lib call on S5b's text (command first) credits"
else _record_fail "F6 control: the same lib call on S5b's text (command first) credits" "nothing recorded"; fi

# L: a lib that faults at LOAD or at CALL costs only the typed credit. The hook sources it
# in a silenced subshell: an `exit`, a `set -u` abort or stray output must not change the
# hook's exit status or stdout (UserPromptSubmit stdout reaches the model's context, and
# exit 2 would block the person's prompt). Each copy differs from the stock lib only as named.
_L_N=0
_lib_fault() {   # <label> <lib-text>
    local _root="${TEST_TMPDIR}/root-fault-${_L_N}"; _L_N=$((_L_N + 1))
    mkdir -p "${_root}" && cp -R "${COPY_STOCK}/hooks" "${COPY_STOCK}/config" "${_root}/"
    printf '%s\n' "$2" > "${_root}/hooks/lib/typed-slash-credit.sh"
    _new_home; _turn "/code-review" "${_root}"
    _expect_nothing "L $1"
}
_lib_fault "exit 3 at load" "exit 3"
_lib_fault "exit 2 at load (would block the prompt)" "exit 2"
_lib_fault "unbound variable at load (set -u abort)" ': "${_TSC_NEVER_SET_ANYWHERE}"'
_lib_fault "stdout and stderr at load" "echo LIB-STDOUT-JUNK; echo LIB-STDERR-JUNK >&2"
_lib_fault "defines no typed_slash_credit" "_unrelated() { :; }"
_lib_fault "syntax error" "if then fi ("
_lib_fault "the function prints and exits 2" 'typed_slash_credit() { echo CALL-JUNK; echo CALL-ERR >&2; exit 2; }'
_lib_fault "the function hits an unbound variable" 'typed_slash_credit() { : "${_TSC_NEVER_SET_ANYWHERE}"; }'

# W: whitespace before the first token is whitespace in the hook's own `[[:space:]]`
# sense, and the lib uses the same class in the same process, so the two agree. A
# carriage return is [[:space:]] in every locale. A no-break space (U+00A0) is
# [[:space:]] under a UTF-8 locale (measured: C.UTF-8, en_US.UTF-8) and not under C,
# where the hook's slash test does not match either and the prompt is routed as text.
# Both are whitespace before the first token, so both credit where they are whitespace.
_new_home; _turn "$(printf '\r/code-review')"
_expect_credit "W1 carriage return before /code-review" "code-review"
_NBSP="$(printf '\302\240')"
_UTF_LOC=""
for _l in C.UTF-8 en_US.UTF-8 UTF-8; do
    if LC_ALL="${_l}" /bin/bash -c '[[ "$1" == [[:space:]] ]]' _ "${_NBSP}" 2>/dev/null; then _UTF_LOC="${_l}"; break; fi
done
if [ -n "${_UTF_LOC}" ]; then
    _new_home; _turn "${_NBSP}/code-review" "${PROJECT_ROOT}" LC_ALL="${_UTF_LOC}"
    _expect_credit "W2 no-break space before /code-review under ${_UTF_LOC}" "code-review"
else
    echo "  SKIP: W2 no UTF-8 locale classifies U+00A0 as [[:space:]] here -- NOT checked"
fi
_new_home; _turn "${_NBSP}/code-review" "${PROJECT_ROOT}" LC_ALL=C
if _has_review || [ -e "$(_INVOC)" ]; then _record_fail "W3 no-break space under LC_ALL=C: not whitespace, credits nothing" "recorded"
else _record_pass "W3 no-break space under LC_ALL=C: not whitespace, credits nothing"; fi

# V: a built-in has no registry entry, and on 2.1.308 an unknown slash command reaches the
# hook exactly like a real one, so the Claude Code version (AI_AGENT) is the only witness
# that /code-review and /security-review exist. >= 2.1.308 credits; anything else does not.
_v_turn() {   # <AI_AGENT value | -unset-> <prompt> [registry]
    _new_home "${3:-${REG}}"
    if [ "$1" = "-unset-" ]; then unset AI_AGENT; else export AI_AGENT="$1"; fi
    _turn "$2"
    export AI_AGENT="${AI_AGENT_OK}"
}
for _a in claude-code_2-1-308_harness claude-code_2-1-309_harness claude-code_2-2-0_harness \
          claude-code_3-0-0_harness claude-code_2-1-308; do
    _v_turn "${_a}" "/code-review"
    _expect_credit "V1 AI_AGENT=${_a}: /code-review" "code-review"
done
_v_turn claude-code_2-1-309_harness "/security-review"
_expect_credit "V1 AI_AGENT=claude-code_2-1-309_harness: /security-review" "security-review"
for _a in -unset- "" claude-code_2-1-307_harness claude-code_2-0-999_harness claude-code_1-9-999_harness \
          garbage claude-code_ claude-code_2-1_harness claude-code_2-1-308-1_harness \
          claude-code_02-1-308_harness claude-code_2-01-308_harness claude-code_2-1-0308_harness \
          claude-code_2-1-9999999_harness claude-code_a-b-c_harness claude-code_2-1-3o8_harness \
          other-agent_2-1-308_harness CLAUDE-CODE_2-1-308_harness; do
    _v_turn "${_a}" "/code-review"
    _expect_nothing "V2 AI_AGENT='${_a}': /code-review"
done
_v_turn claude-code_2-1-307_harness "/security-review"
_expect_nothing "V2 AI_AGENT=claude-code_2-1-307_harness: /security-review"
# Registry skills are unaffected by the version.
for _a in -unset- garbage claude-code_2-1-307_harness; do
    _v_turn "${_a}" "/superpowers:requesting-code-review"
    _expect_credit "V3 AI_AGENT='${_a}': registry skill /superpowers:requesting-code-review" "requesting-code-review"
    _v_turn "${_a}" "/pr-review-toolkit:review-pr"
    _expect_credit "V3 AI_AGENT='${_a}': registry plugin command /pr-review-toolkit:review-pr" "review-pr"
done
# A built-in NAME that is also a registry command still credits through the registry.
REG_CR_PLUGIN="${TEST_TMPDIR}/reg-cr-plugin.json"
"${REAL_JQ}" '.plugins += [{name:"code-review", available:true, provides:{commands:["/code-review"]}}]' "${REG}" > "${REG_CR_PLUGIN}"
_v_turn -unset- "/code-review" "${REG_CR_PLUGIN}"
_expect_credit "V4 AI_AGENT unset, /code-review provided by an available plugin: credits" "code-review"
_v_turn -unset- "/code-review:code-review" "${REG_CR_PLUGIN}"
_expect_credit "V4 AI_AGENT unset, /code-review:code-review (plugin): credits" "code-review"
# V6: without acs_cc_version the BUILT-IN branch fails closed and only it: a copied root
# whose credited-skills.sh has that one function deleted. The capture then yields nothing
# (command not found, silenced by the hook's subshell), so /code-review credits nothing,
# while the registry plugin command /review-pr still credits. AI_AGENT is the good value.
COPY_NOCCV="${TEST_TMPDIR}/root-noccv"
mkdir -p "${COPY_NOCCV}" && cp -R "${COPY_STOCK}/hooks" "${COPY_STOCK}/config" "${COPY_NOCCV}/"
awk '/^acs_cc_version\(\) \{/ { skip = 1 } skip && /^}/ { skip = 0; next } !skip { print }' \
    "${COPY_STOCK}/hooks/lib/credited-skills.sh" > "${COPY_NOCCV}/hooks/lib/credited-skills.sh"
if ! grep -q 'acs_cc_version()' "${COPY_NOCCV}/hooks/lib/credited-skills.sh" \
   && grep -q 'acs_cc_version()' "${COPY_STOCK}/hooks/lib/credited-skills.sh" \
   && ( . "${COPY_NOCCV}/hooks/lib/credited-skills.sh" && command -v credited_review_skill \
        && command -v credited_review_builtin && command -v review_reviewer_covers \
        && ! command -v acs_cc_version ) >/dev/null 2>&1; then
    _record_pass "V6 setup: the copy lacks only acs_cc_version (other functions still load)"
else
    _record_fail "V6 setup: the copy lacks only acs_cc_version (other functions still load)" "copy wrong"
fi
_new_home; _turn "/code-review" "${COPY_NOCCV}"
_expect_nothing "V6 acs_cc_version missing: built-in /code-review"
_new_home; _turn "/review-pr" "${COPY_NOCCV}"
_expect_credit "V6 acs_cc_version missing: registry /review-pr still credits" "review-pr"
_new_home; _turn "/code-review" "${COPY_STOCK}"
_expect_credit "V6 control: the stock copy credits built-in /code-review" "code-review"

# acs_cc_version itself (credited-skills.sh): one definition, reused by Task 7.
_ccv() { ( . "${PROJECT_ROOT}/hooks/lib/credited-skills.sh" && AI_AGENT="$1" acs_cc_version; echo "|rc=$?" ); }
assert_equals "V5 acs_cc_version claude-code_2-1-308_harness" "2.1.308|rc=0" "$(_ccv claude-code_2-1-308_harness)"
assert_equals "V5 acs_cc_version claude-code_10-0-12" "10.0.12|rc=0" "$(_ccv claude-code_10-0-12)"
assert_equals "V5 acs_cc_version 0 components" "0.0.0|rc=0" "$(_ccv claude-code_0-0-0_x)"
for _a in "" garbage claude-code_2-1 claude-code_02-1-308 claude-code_2-1-1234567 claude-code_2--308 x_claude-code_2-1-308; do
    assert_equals "V5 acs_cc_version '${_a}' prints nothing, returns 0" "|rc=0" "$(_ccv "${_a}")"
done
assert_equals "V5 acs_cc_version with AI_AGENT unset" "|rc=0" \
    "$( ( unset AI_AGENT; . "${PROJECT_ROOT}/hooks/lib/credited-skills.sh" && acs_cc_version; echo "|rc=$?" ) )"
assert_equals "V5 acs_cc_version is set -u clean with AI_AGENT unset" "|rc=0" \
    "$( ( set -u; unset AI_AGENT; . "${PROJECT_ROOT}/hooks/lib/credited-skills.sh" && acs_cc_version; echo "|rc=$?" ) 2>&1)"

# U: unit cells on the lib (each in a subshell; the lib sources nothing at load)
_unit_name() { ( . "${LIB}" 2>/dev/null && _typed_slash_name "$1" ) 2>/dev/null; }
assert_equals "U1 _typed_slash_name bare" "code-review" "$(_unit_name '/code-review x')"
assert_equals "U2 _typed_slash_name namespaced" "superpowers:requesting-code-review" "$(_unit_name '  /superpowers:requesting-code-review')"
assert_equals "U3 _typed_slash_name rejects a mention" "" "$(_unit_name 'run /code-review')"
assert_equals "U4 _typed_slash_name rejects two colons" "" "$(_unit_name '/a:b:c')"
# typed_slash_credit kind gate, called directly with a payload that WOULD credit.
# _new_home runs in THIS shell before each call: inside `$( )` its HOME would not
# reach the assertions that follow.
_unit_kind() {
    local _in; _in="$("${REAL_JQ}" -nc --arg t "${_TP}" '{prompt:"/code-review", transcript_path:$t, session_id:"s"}')"
    ( cd "${REPO}" && . "${LIB}" && typed_slash_credit "$1" "/code-review" "${_in}" "${PROJECT_ROOT}"; echo "rc=$?" )
}
for _k in notification nonhuman unclassifiable "" Prompt; do
    _new_home; _r="$(_unit_kind "${_k}")"
    assert_equals "U5 kind '${_k}': returns 0" "rc=0" "${_r}"
    if _has_review; then _record_fail "U5 kind '${_k}': credits nothing" "recorded"
    else _record_pass "U5 kind '${_k}': credits nothing"; fi
done
_new_home; _r="$(_unit_kind prompt)"
assert_equals "U6 control kind 'prompt': returns 0" "rc=0" "${_r}"
if _has_review; then _record_pass "U6 control kind 'prompt': credits"
else _record_fail "U6 control kind 'prompt': credits" "nothing recorded"; fi
# set -u clean: the activation hook runs `set -uo pipefail`.
_r="$( ( set -uo pipefail; . "${LIB}" && typed_slash_credit && _typed_slash_name ""; echo "rc=$?" ) 2>&1)"
assert_equals "U7 no-arg calls are set -u clean" "rc=1" "${_r}"

# I: two credited REVIEW names (subagent-driven-development, agent-team-execution) are
# also IMPLEMENT-slot names, so a typed one writes invocation evidence the push guard's
# IMPLEMENT leg (Check 0) accepts, the same as a Skill return. That changes which pushes
# become IMPLEMENT shadow records, hence IMPLEMENT_SHADOW_PREDICATE_VERSION 6. Both arms,
# REAL activation hook then REAL guard, on a push whose diff touches material source,
# with REVIEW and VERIFY in the ledger so only the IMPLEMENT leg is in question:
#   I1 typed /superpowers:subagent-driven-development -> no advisory, no record
#   I2 typed /superpowers:executing-plans (not a credited REVIEW name) -> still a record
_I_SAVED_REPO="${REPO}"
REPO="$(cd "$(mktemp -d "${TEST_TMPDIR}/irepo.XXXXXX")" && pwd -P)"
( cd "${REPO}" && git init -q && git config user.email t@example.com && git config user.name t \
  && echo '# f' > README.md && git add README.md && git commit -qm init && git branch -M main \
  && git checkout -qb feat/impl && mkdir -p src && echo "print('x')" > src/app.py \
  && git add src/app.py && git commit -qm "feat: material" ) >/dev/null 2>&1
REG_IMPL="${TEST_TMPDIR}/reg-impl.json"
"${REAL_JQ}" '.skills += [
    {name:"subagent-driven-development", invoke:"Skill(superpowers:subagent-driven-development)", available:true, enabled:true},
    {name:"executing-plans", invoke:"Skill(superpowers:executing-plans)", available:true, enabled:true}]' \
    "${REG}" > "${REG_IMPL}"
_I_PV="$( ( . "${PROJECT_ROOT}/hooks/lib/implement-shadow.sh" && printf '%s' "${IMPLEMENT_SHADOW_PREDICATE_VERSION}" ) 2>/dev/null)"
# _impl_arm <prompt> : fresh HOME, IMPLEMENT chain, REVIEW+VERIFY ledger, the typed turn,
# then the push. Sets _I_PUSH and _I_RECS (one "<would_block>|<kind>|<pv>" per record).
_impl_arm() {
    _new_home "${REG_IMPL}"
    printf '%s' '{"chain":["writing-plans","executing-plans","requesting-code-review","verification-before-completion"],"current_index":1,"completed":[]}' \
        > "${HOME}/.claude/.skill-composition-state-${TOK}"
    ( cd "${REPO}" && branch_ledger_record requesting-code-review "${REPO}" \
        && branch_ledger_record verification-before-completion "${REPO}" ) >/dev/null 2>&1
    export IMPLEMENT_SHADOW_LOG="${HOME}/impl-shadow.jsonl"
    _turn "$1"
    _I_PUSH="$(_push)"
    _I_RECS="$("${REAL_JQ}" -r '"\(.would_block)|\(.impl_evidence_kind)|\(.predicate_version)"' \
        "${IMPLEMENT_SHADOW_LOG}" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
    unset IMPLEMENT_SHADOW_LOG
}
_impl_arm "/superpowers:subagent-driven-development docs/plans/x-plan.md"
if [ -f "$(_INVOC)" ] && "${REAL_JQ}" -e 'index("subagent-driven-development") != null' "$(_INVOC)" >/dev/null 2>&1; then
    _record_pass "I1 setup: typed SDD wrote subagent-driven-development to invocation evidence"
else
    _record_fail "I1 setup: typed SDD wrote subagent-driven-development to invocation evidence" "$(cat "$(_INVOC)" 2>/dev/null || echo '<none>')"
fi
assert_not_contains "I1 typed SDD: the push is not denied" '"deny"' "${_I_PUSH:-<empty>}"
assert_not_contains "I1 typed SDD: no IMPLEMENT advisory" "IMPLEMENT:" "${_I_PUSH:-<empty>}"
assert_equals "I1 typed SDD: no IMPLEMENT shadow record" "" "${_I_RECS}"
_impl_arm "/superpowers:executing-plans docs/plans/x-plan.md"
if [ -e "$(_INVOC)" ]; then _record_fail "I2 typed executing-plans: no invocation evidence" "$(cat "$(_INVOC)")"
else _record_pass "I2 typed executing-plans: no invocation evidence"; fi
assert_not_contains "I2 typed executing-plans: the push is not denied" '"deny"' "${_I_PUSH:-<empty>}"
assert_contains "I2 typed executing-plans: the IMPLEMENT advisory fires" "IMPLEMENT:" "${_I_PUSH:-<empty>}"
assert_equals "I2 typed executing-plans: one would-block record at the current predicate" \
    "true|none|${_I_PV}" "${_I_RECS}"
assert_equals "I2 the current IMPLEMENT predicate is 6" "6" "${_I_PV}"
REPO="${_I_SAVED_REPO}"

print_summary

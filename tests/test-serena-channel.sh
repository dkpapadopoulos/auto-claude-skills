#!/usr/bin/env bash
# tests/test-serena-channel.sh — #124
#
# #124's pre-registered kill criterion could not be applied because the
# MEASUREMENT CHANNEL was structurally dead: serena-nudge.sh required
# tool_name == "Grep", while sessions are instructed to work through the Bash
# tool and increasingly search with grep/rg there. Measured 2026-09-19: 5
# telemetry records, all "observe", not one "nudge", across 38 days.
#
# That matters beyond telemetry. The issue's SECONDARY signal says to delete
# the broadened matcher as dead code if it fires ~0 times in the window — and
# acting on it would have deleted a demonstrably working matcher on the
# strength of a number that measures tool ROUTING, not matcher quality.
#
# Repairing the channel is the precondition for that evaluation, not a
# substitute for it, and this file does not claim the evaluation is done.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

NUDGE="${PROJECT_ROOT}/hooks/serena-nudge.sh"

# _fire <payload-json> -> the telemetry class, or "-" when it did not fire
_fire() {
    local _w _t _out; _w="$(mktemp -d /tmp/acs-serena-XXXXXX)"; mkdir -p "${_w}/.claude"
    printf '%s' '{"context_capabilities":{"serena":true}}' > "${_w}/.claude/.skill-registry-cache.json"
    printf '%s' "$1" | HOME="${_w}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        /bin/bash "${NUDGE}" >/dev/null 2>&1
    _t="${_w}/.claude/.serena-nudge-telemetry"
    if [ -f "${_t}" ]; then awk -F'\t' 'END{print $5}' "${_t}"; else printf '%s' '-'; fi
    rm -rf "${_w}"
}
_grep_payload() { jq -nc --arg p "$1" '{tool_name:"Grep",tool_input:{pattern:$p}}'; }
_bash_payload() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

test_preconditions() {
    if command -v jq >/dev/null 2>&1 && [ -r "${NUDGE}" ]; then
        _record_pass "jq and the nudge hook are present"
    else
        _record_fail "jq and the nudge hook are present" "missing — cells below vacuous"
    fi
}

test_bash_search_reaches_the_channel() {
    # THE defect: a grep routed through Bash used to reach nothing at all.
    local c; c="$(_fire "$(_bash_payload "grep -rn 'class UserService' src/")")"
    [ "${c}" = "definition_prefix" ] && _record_pass "a Bash-routed grep now reaches the channel" \
        || _record_fail "a Bash-routed grep now reaches the channel" "class was '${c}', expected definition_prefix"
}

test_quoted_phrase_is_not_truncated() {
    # Naive word-splitting yields `class`, which matches no definition prefix
    # (they carry a trailing space) and silently loses the nudge — an
    # under-fire that looks exactly like the dead channel this fixes.
    local c; c="$(_fire "$(_bash_payload "grep -rE 'class Foo' .")")"
    [ "${c}" = "definition_prefix" ] && _record_pass "a quoted multi-word pattern survives extraction" \
        || _record_fail "a quoted multi-word pattern survives extraction" "class was '${c}'"
}

test_classification_is_identical_to_grep() {
    # The justification for extending rather than duplicating: only EXTRACTION
    # is tool-specific. If these ever diverge, the Bash path has grown its own
    # classifier and the telemetry stops being comparable across tools.
    local p g b diverged=""
    for p in "class UserService" "def handle_auth" "AuthHandler" "todo" "some random words here"; do
        g="$(_fire "$(_grep_payload "${p}")")"
        b="$(_fire "$(_bash_payload "grep -n '${p}' .")")"
        [ "${g}" = "${b}" ] || diverged="${diverged} [${p}: Grep=${g} Bash=${b}]"
    done
    [ -z "${diverged}" ] && _record_pass "Bash and Grep classify identically (5 patterns)" \
        || _record_fail "Bash and Grep classify identically" "diverged:${diverged}"
}

test_non_search_bash_does_not_fire() {
    # This hook now sees EVERY Bash call. A nudge on `cat` or `ls` would be
    # noise on the hottest path in the session, and noise gets hooks disabled.
    local c bad=""
    for c in "cat file.txt" "ls -la" "git status" "echo grep hello"; do
        [ "$(_fire "$(_bash_payload "${c}")")" = "-" ] || bad="${bad} ${c}"
    done
    [ -z "${bad}" ] && _record_pass "non-search Bash commands do not fire" \
        || _record_fail "non-search Bash commands do not fire" "fired on:${bad}"
}

test_bash_matcher_is_wired() {
    # The hook can only see Bash if hooks.json routes Bash to it. Without this
    # the code above is correct and still never runs — which is the shape of
    # the original defect.
    local n
    n="$(python3 -c "
import json,sys
d=json.load(open('${PROJECT_ROOT}/hooks/hooks.json'))
print(sum(1 for e in d['hooks']['PreToolUse']
          if e.get('matcher')=='Bash'
          and any('serena-nudge' in h.get('command','') for h in e.get('hooks',[]))))" 2>/dev/null)"
    [ "${n}" = "1" ] && _record_pass "hooks.json routes Bash to serena-nudge" \
        || _record_fail "hooks.json routes Bash to serena-nudge" "found ${n:-0} such entries"
}

test_preconditions
test_bash_search_reaches_the_channel
test_quoted_phrase_is_not_truncated
test_classification_is_identical_to_grep
test_non_search_bash_does_not_fire
test_bash_matcher_is_wired

print_summary

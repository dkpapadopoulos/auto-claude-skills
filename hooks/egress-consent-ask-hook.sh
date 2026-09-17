#!/bin/bash
# egress-consent-ask-hook.sh — PreToolUse(AskUserQuestion): records a CLEAN consent ask,
# and denies a consent question the model could have answered for the user.
#
# A cross-family send is authorised only by a receipt that
# hooks/egress-consent-receipt-hook.sh writes from the user's answer. That answer is only
# trustworthy if the MODEL did not supply it: the AskUserQuestion schema lets a caller pass
# `answers` and `annotations` (the preview that gets hashed). Measured live 2026-09-16: a
# genuine ask arrives here with ONLY `questions`; the harness fills the rest afterwards.
# So a marked question carrying either key is denied, and every other marked question must
# match a strict schema, so the receipt hook can find the one answer unambiguously.
#
# Asking about a package WITHDRAWS every earlier unused approval of it, before anything
# else is decided: the latest question supersedes, and if it is then cancelled (no
# PostToolUse) or fails to record, no stale approval survives it.
#
# Acts ONLY on questions whose text carries `[egress-consent:<digest>]`. Everything else
# passes untouched. It never emits an allow. Inability to check is announced, never
# silent, and states truthfully whether earlier approvals were withdrawn.
#
# No `trap 'exit 0' ERR` on purpose: every failure path below is explicit.
# Design: openspec/changes/archive/2026-09-17-egress-consent-dispatcher/design.md

# JSON-safe: C0 controls (incl. TAB/CR/LF) are dropped, backslash before quote.
_json_escape() {
    printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
_announce() {
    printf '{"systemMessage":"egress-consent: %s"}\n' "$(_json_escape "$1")"
}
_deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"egress-consent: %s"}}\n' \
        "$(_json_escape "$1")"
}
_NOT_WITHDRAWN="an earlier unused approval of this package, if any, was NOT withdrawn"

_INPUT="$(cat)"
# Cheap pre-filter: only consent questions can contain the marker.
case "${_INPUT}" in
    *egress-consent*) ;;
    *) exit 0 ;;
esac

_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "${_PLUGIN_ROOT}" ]; then
    _PLUGIN_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || _PLUGIN_ROOT=""
fi
_LIBS_OK=false
# shellcheck source=/dev/null
if . "${_PLUGIN_ROOT}/hooks/lib/egress-consent.sh" 2>/dev/null \
    && command -v egress_revoke_unused >/dev/null 2>&1 \
    && . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null \
    && command -v session_token_from_transcript >/dev/null 2>&1; then
    _LIBS_OK=true
fi
if [ "${_LIBS_OK}" != "true" ]; then
    _announce "consent libraries not loadable under ${_PLUGIN_ROOT:-<no plugin root>} — this consent question was NOT recorded (so it cannot approve anything), and ${_NOT_WITHDRAWN}."
    exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
    _announce "jq unavailable — this consent question was NOT recorded (so it cannot approve anything), and ${_NOT_WITHDRAWN}. The dispatcher also needs jq, so it will refuse to send."
    exit 0
fi

# One jq pass: schema verdict + the facts the decision needs, US-separated.
# shellcheck disable=SC2016
_PROG='
def strs: if type == "string" then . else "" end;
def marked: (.question | strs) | contains("[egress-consent:");
def approve($m): [(($m.options | arrays)[]? | objects | select(.label == $L))];
(if (.tool_input | type) == "object" then .tool_input else {} end) as $ti
| (if ($ti.questions | type) == "array" then [$ti.questions[] | objects] else [] end) as $qs
| [$qs[] | select(marked)] as $m
| ([$m[] | .question | strs | capture("\\[egress-consent:(?<d>[0-9a-f]{64})\\]")? | .d] | first // "") as $raw
| (if ($m | length) == 0 then "none"
   elif ($m | length) > 1 then "multiple-marked-questions"
   elif ([$qs[] | .question | strs] | length) != ([$qs[] | .question | strs] | unique | length)
     then "duplicate-question-text"
   elif ([$m[0].question | strs | scan("\\[egress-consent:")] | length) != 1 then "multiple-markers"
   elif ($m[0].question | strs | test("\\[egress-consent:[0-9a-f]{64}\\]") | not) then "malformed-marker"
   elif ($m[0].multiSelect // false) != false then "multiselect"
   elif ([$qs[] | (.header | strs),
                 ((.options | arrays)[]? | objects | (.label | strs), (.description | strs), (.preview | strs))]
         | any(contains("[egress-consent:"))) then "marker-in-option"
   elif (approve($m[0]) | length) != 1 then "approve-label-count"
   elif ((($m[0].options | arrays)[0] | objects | .label) // "") == $L then "approve-option-first"
   elif ((($m[0].options | arrays)[0] | objects | .label) // "") != $N then "decline-option-first"
   elif (approve($m[0])[0].preview | strs) == "" then "approve-preview-missing"
   elif (approve($m[0])[0].preview | strs | explode
         | any((. < 32 and . != 9 and . != 10) or . == 127 or (. >= 128 and . <= 159)
               or (. >= 8234 and . <= 8238) or (. >= 8294 and . <= 8297)))
     then "hidden-characters-in-preview"
   else "ok" end) as $verdict
| [ $verdict,
    (if ($ti | has("answers")) or ($ti | has("annotations")) then "1" else "0" end),
    (if (.agent_id // null) == null then "0" else "1" end),
    ((.tool_use_id // "") | tostring),
    ((.transcript_path // "") | tostring),
    $raw
  ] | join("\u001f")'

_META="$(printf '%s' "${_INPUT}" | jq -r --arg L "${EGRESS_APPROVE_LABEL}" --arg N "${EGRESS_DECLINE_LABEL}" "${_PROG}" 2>/dev/null)"
if [ -z "${_META}" ]; then
    _announce "hook payload unparseable — this consent question was NOT recorded (so it cannot approve anything), and ${_NOT_WITHDRAWN}."
    exit 0
fi
IFS=$'\x1f' read -r _VERDICT _PREFILLED _SUBAGENT _ID _TP _DIGEST <<EOF
${_META}
EOF

[ "${_VERDICT}" = "none" ] && exit 0

# Withdraw earlier approvals of this package FIRST — every path below is covered.
_TOKEN="$(session_token_from_transcript "${_TP}")"
_WITHDRAWN="${_NOT_WITHDRAWN} (no session identity or digest in the payload)"
if egress_valid_token "${_TOKEN}" && egress_valid_digest "${_DIGEST}"; then
    read -r _RV_OK _RV_BAD <<EOF
$(egress_revoke_unused "${_TOKEN}" "${_DIGEST}")
EOF
    if [ "${_RV_BAD:-0}" = "0" ]; then
        _WITHDRAWN="no earlier approval of this package remains usable"
    else
        _WITHDRAWN="${_RV_BAD} earlier approval(s) of this package could NOT be withdrawn"
    fi
fi

if [ "${_PREFILLED}" = "1" ]; then
    _deny "pre-answered — a consent question must reach the user with no answers or annotations supplied by the caller. ${_WITHDRAWN}."
    exit 0
fi
if [ "${_SUBAGENT}" = "1" ]; then
    _deny "subagent — consent must be asked from the main conversation, not from a subagent. ${_WITHDRAWN}."
    exit 0
fi
if [ "${_VERDICT}" != "ok" ]; then
    _deny "${_VERDICT} — a consent question needs exactly one question carrying one [egress-consent:<digest>] marker in its text, single-select, unique question texts, \"${EGRESS_DECLINE_LABEL}\" as the FIRST (default) option so a reflexive Enter never approves, exactly one \"${EGRESS_APPROVE_LABEL}\" option whose preview is the complete package with no control characters other than tab and newline, and no marker anywhere else. ${_WITHDRAWN}."
    exit 0
fi

_PREVIEW_DIGEST="$(printf '%s' "${_INPUT}" \
    | jq -r --arg L "${EGRESS_APPROVE_LABEL}" \
        '[.tool_input.questions[] | objects | select((.question | strings) | contains("[egress-consent:"))][0].options[] | objects | select(.label == $L) | .preview' \
        2>/dev/null | egress_digest_stdin)"
if [ -z "${_PREVIEW_DIGEST}" ]; then
    _announce "could not hash the approval preview — this consent question was NOT recorded (so it cannot approve anything); ${_WITHDRAWN}."
    exit 0
fi
if [ "${_PREVIEW_DIGEST}" != "${_DIGEST}" ]; then
    _deny "preview-digest-mismatch — the \"${EGRESS_APPROVE_LABEL}\" preview must be the exact prepared package (digest ${_DIGEST}); it hashes to ${_PREVIEW_DIGEST}. Paste the package verbatim. ${_WITHDRAWN}."
    exit 0
fi

if ! egress_valid_token "${_TOKEN}" || ! egress_valid_id "${_ID}"; then
    _announce "no usable session identity or tool_use_id in the hook payload — this consent question was NOT recorded (so it cannot approve anything); ${_WITHDRAWN}."
    exit 0
fi

_ASK="$(egress_ask_path "${_TOKEN}" "${_ID}")"
if [ -e "${_ASK}" ] || [ -e "${_ASK}.used" ]; then
    _deny "reused-tool-use-id — a consent ask with this id was already recorded. ${_WITHDRAWN}."
    exit 0
fi

_NOW="$(egress_now_ms)" || _NOW=""
case "${_NOW}" in ''|*[!0-9]*)
    _announce "clock unavailable — this consent question was NOT recorded (so it cannot approve anything); ${_WITHDRAWN}."
    exit 0 ;;
esac
if ! printf '%s' "${_INPUT}" \
    | jq -c --arg d "${_DIGEST}" --argjson ms "${_NOW}" \
        '{digest: $d, ask_ms: $ms,
          question: ([.tool_input.questions[] | objects | select((.question | strings) | contains("[egress-consent:"))][0].question)}' \
        2>/dev/null \
    | egress_write_atomic "${_ASK}"; then
    _announce "could not write the consent snapshot — this consent question was NOT recorded (so it cannot approve anything); ${_WITHDRAWN}."
fi
exit 0

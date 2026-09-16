#!/bin/bash
# egress-consent-receipt-hook.sh — PostToolUse(AskUserQuestion): turns the user's
# approval of a consent question into ONE egress receipt for scripts/consult-dispatch.sh.
#
# A receipt is written only when ALL hold:
#   - hooks/egress-consent-ask-hook.sh recorded this tool_use_id as a clean ask. The
#     snapshot is consumed FIRST, so a repeated PostToolUse cannot issue a second receipt.
#   - the harness-returned answer for the snapshot's question is exactly the approve label;
#   - the harness-returned annotation for that question carries a preview (never fall
#     back to the option preview in tool_input — that is model-authored text);
#   - that preview hashes (egress_digest_stdin) to the snapshot's digest.
# The receipt carries the ask time (ms), so the dispatcher can discard it if a decline of
# the same package was ANSWERED after this question was asked (parallel asks, any order).
# A repeat delivery of an already-processed answer is ignored entirely.
#
# Any OTHER outcome withdraws approvals: a decline (any non-approve answer) records a
# veto for the package and revokes every unused approval of the conversation; an
# unverifiable answer revokes the approvals of that package. The latest answer wins.
#
# Receipt files live in ~/.claude and are agent-writable: this defends against a model
# that SKIPS the ask, not one that forges a file (see the design's threat model).
# No `trap 'exit 0' ERR` on purpose: every failure path below is explicit.
# Design: openspec/changes/egress-consent-dispatcher/design.md

_json_escape() {
    printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
_announce() {
    printf '{"systemMessage":"egress-consent: %s"}\n' "$(_json_escape "$1")"
}
_NOT_WITHDRAWN="an earlier unused approval of this package, if any, was NOT withdrawn"

_INPUT="$(cat)"
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
    _announce "consent libraries not loadable under ${_PLUGIN_ROOT:-<no plugin root>} — no approval receipt was written, and ${_NOT_WITHDRAWN}."
    exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
    _announce "jq unavailable — no approval receipt was written, and ${_NOT_WITHDRAWN}. The dispatcher also needs jq, so it will refuse to send."
    exit 0
fi

# tool_use_id, transcript_path, and the digest named by the (first) marker in the
# payload — the latter lets us withdraw approvals even when no snapshot exists.
# shellcheck disable=SC2016
_META="$(printf '%s' "${_INPUT}" | jq -r '
    def strs: if type == "string" then . else "" end;
    if type != "object" then empty else
    [ ((.tool_use_id // "") | tostring),
      ((.transcript_path // "") | tostring),
      ([ (.tool_input | objects | .questions | arrays | .[] | objects | .question | strs),
         (.tool_response | objects | .questions | arrays | .[] | objects | .question | strs) ]
       | map(capture("\\[egress-consent:(?<d>[0-9a-f]{64})\\]")? | .d) | first // "")
    ] | join("\u001f") end' 2>/dev/null)"
if [ -z "${_META}" ]; then
    _announce "hook payload unparseable — no approval receipt was written, and ${_NOT_WITHDRAWN}."
    exit 0
fi
IFS=$'\x1f' read -r _ID _TP _MARKED <<EOF
${_META}
EOF

_TOKEN="$(session_token_from_transcript "${_TP}")"
if ! egress_valid_token "${_TOKEN}"; then
    _announce "no session identity in the hook payload — no approval receipt was written, and ${_NOT_WITHDRAWN}."
    exit 0
fi

# _finish <message> <scope> — withdraw approvals, then announce what actually happened.
#   scope "package": this package's unused approvals; "all": every unused approval here.
_finish() {
    local _msg="$1" _scope="$2" _d="${_DIGEST:-${_MARKED}}" _rv _ok _bad
    if [ "${_scope}" = "all" ]; then
        _rv="$(egress_revoke_unused "${_TOKEN}")"
    elif egress_valid_digest "${_d}"; then
        _rv="$(egress_revoke_unused "${_TOKEN}" "${_d}")"
    else
        _announce "${_msg} ${_NOT_WITHDRAWN} (no package digest could be identified)."
        exit 0
    fi
    _ok="${_rv%% *}"; _bad="${_rv##* }"
    if [ "${_bad}" != "0" ]; then
        _msg="${_msg} WARNING: ${_bad} earlier approval(s) could NOT be withdrawn and may still be usable."
    elif [ "${_ok}" != "0" ]; then
        _msg="${_msg} ${_ok} earlier unused approval(s) were revoked."
    fi
    _announce "${_msg}"
    exit 0
}

_DIGEST=""
if ! egress_valid_id "${_ID}"; then
    _finish "no usable tool_use_id in the hook payload — no approval receipt was written." package
fi

_ASK="$(egress_ask_path "${_TOKEN}" "${_ID}")"
if [ -e "${_ASK}.used" ]; then
    # A repeat delivery of an answer already processed (e.g. the plugin loaded twice).
    # It carries no new user intent: never re-issue, and never revoke what it issued.
    exit 0
fi
if [ ! -f "${_ASK}" ]; then
    # Not a recorded clean ask (unmarked, or denied at PreToolUse). A marked answer
    # still withdraws: whatever the user said here, it was not a verifiable approval.
    if egress_valid_digest "${_MARKED}"; then
        _finish "no clean ask recorded for this consent answer — no approval receipt was written." package
    fi
    exit 0
fi
# Consume the snapshot BEFORE judging the answer: one ask can yield at most one receipt.
if ! mv "${_ASK}" "${_ASK}.used" 2>/dev/null; then
    _finish "could not consume the consent snapshot — no approval receipt was written." package
fi
_SNAP="${_ASK}.used"

_DIGEST="$(jq -r '.digest // empty' "${_SNAP}" 2>/dev/null)"
_ASK_MS="$(jq -r '.ask_ms // empty | numbers | floor' "${_SNAP}" 2>/dev/null)"
if ! egress_valid_digest "${_DIGEST}"; then
    _DIGEST=""
    _finish "consent snapshot unreadable — no approval receipt was written." package
fi
case "${_ASK_MS}" in ''|*[!0-9]*)
    _finish "consent snapshot has no ask time — no approval receipt was written." package ;;
esac

# shellcheck disable=SC2016
_STATE="$(printf '%s' "${_INPUT}" | jq -r --slurpfile s "${_SNAP}" --arg L "${EGRESS_APPROVE_LABEL}" '
    ($s[0].question // "") as $q
    | (if (.tool_response | type) == "object" then .tool_response else null end) as $tr
    | if $q == "" then "no-question"
      elif $tr == null then "no-response"
      elif ((($tr.answers | objects | .[$q]) // null) != $L) then "not-approved"
      elif (((($tr.annotations | objects | .[$q]) | objects | .preview | strings) // null) == null)
        then "no-annotation"
      else "ok" end' 2>/dev/null)"

case "${_STATE}" in
    ok) ;;
    not-approved)
        # The decline voids every approval of this package whose question was asked
        # before NOW — i.e. was still open when the user said no.
        _DECLINED_MS="$(egress_now_ms)" || _DECLINED_MS=""
        if ! egress_record_veto "${_TOKEN}" "${_DIGEST}" "${_DECLINED_MS}"; then
            _finish "the user did not choose \"${EGRESS_APPROVE_LABEL}\" — not approved; nothing will be sent from this answer. WARNING: the decline could not be recorded durably." all
        fi
        _finish "the user did not choose \"${EGRESS_APPROVE_LABEL}\" — not approved; nothing will be sent from this answer." all ;;
    no-annotation)
        _finish "the answer carried no returned preview to verify — no approval receipt was written." package ;;
    no-response)
        _finish "tool_response is not the expected object — no approval receipt was written." package ;;
    *)
        _finish "could not evaluate the consent answer (${_STATE:-jq error}) — no approval receipt was written." package ;;
esac

_SEEN="$(printf '%s' "${_INPUT}" \
    | jq -r --slurpfile s "${_SNAP}" '.tool_response.annotations[$s[0].question].preview' 2>/dev/null \
    | egress_digest_stdin)"
if ! egress_valid_digest "${_SEEN}"; then
    _finish "could not hash the approved preview (no shasum or sha256sum) — no approval receipt was written." package
fi
if [ "${_SEEN}" != "${_DIGEST}" ]; then
    _finish "the approved preview does not match the prepared package (digest ${_DIGEST}) — no approval receipt was written." package
fi

_NOW="$(date +%s 2>/dev/null)"
case "${_NOW}" in ''|*[!0-9]*)
    _finish "clock unavailable — no approval receipt was written." package ;;
esac
if ! jq -nc --arg d "${_DIGEST}" --arg id "${_ID}" --argjson ts "${_NOW}" --argjson ask "${_ASK_MS}" \
        '{digest: $d, tool_use_id: $id, ts: $ts, ask_ms: $ask}' 2>/dev/null \
    | egress_write_atomic "$(egress_receipt_path "${_TOKEN}" "${_DIGEST}" "${_ID}")"; then
    _announce "could not write the approval receipt — this approval cannot be used; ask again."
    exit 0
fi
# Re-check AFTER publishing: a decline of this package answered after this question was
# asked (a parallel ask) wins even if it was recorded while this hook ran.
if [ "${_ASK_MS}" -le "$(egress_veto_ts "${_TOKEN}" "${_DIGEST}")" ]; then
    _R="$(egress_receipt_path "${_TOKEN}" "${_DIGEST}" "${_ID}")"
    mv "${_R}" "${_R}.revoked" 2>/dev/null \
        && _announce "this approval was superseded by a \"${EGRESS_DECLINE_LABEL}\" given for the same package while the question was open; nothing will be sent from it." \
        || _announce "WARNING: this approval was superseded by a decline but could NOT be withdrawn."
fi
exit 0

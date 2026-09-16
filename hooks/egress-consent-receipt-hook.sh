#!/bin/bash
# egress-consent-receipt-hook.sh — PostToolUse(AskUserQuestion): turns the user's
# approval of a consent question into ONE egress receipt for scripts/consult-dispatch.sh.
#
# A receipt is written only when ALL hold:
#   - hooks/egress-consent-ask-hook.sh recorded this tool_use_id as a clean ask
#     (no caller-supplied answers/annotations, main thread, strict schema, preview ==
#     the prepared package). The snapshot is consumed FIRST, so a repeated PostToolUse
#     cannot issue a second receipt after the first was spent.
#   - the harness-returned answer for the snapshot's question is exactly the approve label;
#   - the harness-returned annotation for that question carries a preview (never fall
#     back to the option preview in tool_input — that is model-authored text);
#   - that preview hashes (egress_digest_stdin) to the snapshot's digest.
#
# Receipt files live in ~/.claude and are agent-writable: this defends against a model
# that SKIPS the ask, not one that forges a file (see the design's threat model).
# Writes nothing on any doubt, and announces it — no receipt means the send is refused.
# No `trap 'exit 0' ERR` on purpose: every failure path below is explicit.
# Design: openspec/changes/egress-consent-dispatcher/design.md

_json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n\r'
}
_announce() {
    printf '{"systemMessage":"egress-consent: %s"}\n' "$(_json_escape "$1")"
}

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
    && command -v egress_digest_stdin >/dev/null 2>&1 \
    && . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null \
    && command -v session_token_from_transcript >/dev/null 2>&1; then
    _LIBS_OK=true
fi
_NO_RECEIPT="no approval receipt was written, so the send will be refused"
if [ "${_LIBS_OK}" != "true" ]; then
    _announce "consent libraries not loadable under ${_PLUGIN_ROOT:-<no plugin root>} — ${_NO_RECEIPT}."
    exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
    _announce "jq unavailable — ${_NO_RECEIPT}."
    exit 0
fi

_META="$(printf '%s' "${_INPUT}" | jq -r \
    'if type == "object" then [((.tool_use_id // "") | tostring), ((.transcript_path // "") | tostring)] | join("\u001f") else empty end' \
    2>/dev/null)"
if [ -z "${_META}" ]; then
    _announce "hook payload unparseable — ${_NO_RECEIPT}."
    exit 0
fi
IFS=$'\x1f' read -r _ID _TP <<EOF
${_META}
EOF

_TOKEN="$(session_token_from_transcript "${_TP}")"
if ! egress_valid_token "${_TOKEN}" || ! egress_valid_id "${_ID}"; then
    _announce "no usable session identity or tool_use_id in the hook payload — ${_NO_RECEIPT}."
    exit 0
fi

_ASK="$(egress_ask_path "${_TOKEN}" "${_ID}")"
if [ ! -f "${_ASK}" ]; then
    # Either the question carried no consent marker the ask hook accepted, or this
    # answer was already processed once. Both mean: nothing to issue.
    case "${_INPUT}" in
        *"[egress-consent:"*)
            _announce "no clean ask recorded for this consent answer — ${_NO_RECEIPT}." ;;
    esac
    exit 0
fi
# Consume the snapshot BEFORE judging the answer: one ask can yield at most one receipt.
if ! mv "${_ASK}" "${_ASK}.used" 2>/dev/null; then
    _announce "could not consume the consent snapshot — ${_NO_RECEIPT}."
    exit 0
fi
_SNAP="${_ASK}.used"

_DIGEST="$(jq -r '.digest // empty' "${_SNAP}" 2>/dev/null)"
if ! egress_valid_digest "${_DIGEST}"; then
    _announce "consent snapshot unreadable — ${_NO_RECEIPT}."
    exit 0
fi

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
        # The latest answer wins: an earlier, still-unused approval of the SAME package
        # must not outlive the user's decline (found live 2026-09-16). Revoked receipts
        # are renamed, not deleted, so the history stays auditable.
        _REVOKED=0
        for _R in "$(egress_receipt_path "${_TOKEN}" "${_DIGEST}" "")"*; do
            [ -f "${_R}" ] || continue
            case "${_R}" in *.consumed|*.revoked|*.tmp.*) continue ;; esac
            mv "${_R}" "${_R}.revoked" 2>/dev/null && _REVOKED=$((_REVOKED + 1))
        done
        _MSG="the user did not choose \"${EGRESS_APPROVE_LABEL}\" — not approved; nothing will be sent."
        [ "${_REVOKED}" -gt 0 ] && _MSG="${_MSG} ${_REVOKED} earlier unused approval(s) of this package were revoked."
        _announce "${_MSG}"
        exit 0 ;;
    no-annotation)
        _announce "the answer carried no returned preview to verify — ${_NO_RECEIPT}."
        exit 0 ;;
    no-response)
        _announce "tool_response is not the expected object — ${_NO_RECEIPT}."
        exit 0 ;;
    *)
        _announce "could not evaluate the consent answer (${_STATE:-jq error}) — ${_NO_RECEIPT}."
        exit 0 ;;
esac

_SEEN="$(printf '%s' "${_INPUT}" \
    | jq -r --slurpfile s "${_SNAP}" '.tool_response.annotations[$s[0].question].preview' 2>/dev/null \
    | egress_digest_stdin)"
if [ "${_SEEN}" != "${_DIGEST}" ]; then
    _announce "the approved preview does not match the prepared package (digest ${_DIGEST}) — ${_NO_RECEIPT}."
    exit 0
fi

_NOW="$(date +%s 2>/dev/null)"
case "${_NOW}" in ''|*[!0-9]*)
    _announce "clock unavailable — ${_NO_RECEIPT}."
    exit 0 ;;
esac
if ! jq -nc --arg d "${_DIGEST}" --arg id "${_ID}" --argjson ts "${_NOW}" \
        '{digest: $d, tool_use_id: $id, ts: $ts}' 2>/dev/null \
    | egress_write_atomic "$(egress_receipt_path "${_TOKEN}" "${_DIGEST}" "${_ID}")"; then
    _announce "could not write the approval receipt — the send will be refused."
fi
exit 0

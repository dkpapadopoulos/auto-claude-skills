#!/bin/bash
# egress-consent-turn-hook.sh — UserPromptSubmit: an egress approval lives only within the
# turn in which the user gave it.
#
# The consent flow is prepare -> ask -> answer -> send inside ONE assistant turn (an
# AskUserQuestion answer is a tool result, not a new prompt). A new user prompt means that
# turn ended without sending — and the prompt may well be "no, don't send it". So every
# unused approval of this conversation is revoked here (renamed .revoked, kept for audit).
# Cost of a false withdrawal: one re-ask.
#
# Runs on every prompt, so the common case (no approvals at all) exits before any fork.
# Fails open and announces only when approvals exist and cannot be withdrawn.
# Design: openspec/changes/egress-consent-dispatcher/design.md

_any=false
for _f in "${HOME}"/.claude/.skill-egress-receipt-*; do
    case "${_f}" in *.consumed|*.revoked|*.tmp.*) continue ;; esac
    [ -f "${_f}" ] && { _any=true; break; }
done
[ "${_any}" = "true" ] || { cat > /dev/null; exit 0; }

_json_escape() {
    printf '%s' "$1" | LC_ALL=C tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
_announce() {
    printf '{"systemMessage":"egress-consent: %s"}\n' "$(_json_escape "$1")"
}

_INPUT="$(cat)"
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
if [ -z "${_PLUGIN_ROOT}" ]; then
    _PLUGIN_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || _PLUGIN_ROOT=""
fi
# shellcheck source=/dev/null
if ! { . "${_PLUGIN_ROOT}/hooks/lib/egress-consent.sh" 2>/dev/null \
        && command -v egress_revoke_unused >/dev/null 2>&1 \
        && . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null \
        && command -v session_token_from_transcript >/dev/null 2>&1; }; then
    _announce "consent libraries not loadable — unused egress approvals of this conversation (if any) were NOT withdrawn and remain usable for up to 15 minutes."
    exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
    _announce "jq unavailable to this hook — unused egress approvals of this conversation (if any) were NOT withdrawn at the turn boundary."
    exit 0
fi
_TP="$(printf '%s' "${_INPUT}" | jq -r 'if type == "object" then (.transcript_path // "") | tostring else "" end' 2>/dev/null)"
_TOKEN="$(session_token_from_transcript "${_TP}")"
if ! egress_valid_token "${_TOKEN}"; then
    _announce "no session identity in the prompt payload — unused egress approvals of this conversation (if any) were NOT withdrawn."
    exit 0
fi
_RV="$(egress_revoke_unused "${_TOKEN}")"
_BAD="${_RV##* }"
if [ "${_BAD}" != "0" ]; then
    _announce "${_BAD} unused egress approval(s) from the previous turn could NOT be withdrawn and may still be usable."
fi
exit 0

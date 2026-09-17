#!/bin/bash
# egress-consent-turn-hook.sh — UserPromptSubmit: an egress approval lives only within the
# turn in which the user gave it.
#
# Exception: a prompt made up entirely of <task-notification> blocks (measured live: that
# is how background-task notifications arrive) is not the user and ends nothing.
# The consent flow is prepare -> ask -> answer -> send inside ONE assistant turn (an
# AskUserQuestion answer is a tool result, not a new prompt). A new user prompt means that
# turn ended without sending — and the prompt may well be "no, don't send it". So every
# unused approval of this conversation is revoked here (renamed .revoked, kept for audit).
# Cost of a false withdrawal: one re-ask.
#
# Background-task notifications (also delivered as UserPromptSubmit) are ignored.
# Runs on every prompt, so the common case (no approvals at all) exits before any fork.
# Fails open and announces only when approvals exist and cannot be withdrawn.
# Design: openspec/changes/archive/2026-09-17-egress-consent-dispatcher/design.md

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
# A prompt made up ENTIRELY of <task-notification> blocks is a background-task
# notification (measured live 2026-09-17), not the user speaking; treating it as a turn
# boundary revoked a genuine approval mid-flow. The classifier and its documented edge
# cases live in hooks/lib/task-notification.sh, shared with the activation hook.
# Without that lib, or when its definition does not compile, every prompt counts as the
# user: withdrawing is the safe direction.
_TN_FALLBACK_DEF='def notification_kind: "prompt";'
TASK_NOTIFICATION_JQ_DEF=""
# shellcheck source=/dev/null
. "${_PLUGIN_ROOT}/hooks/lib/task-notification.sh" 2>/dev/null || TASK_NOTIFICATION_JQ_DEF=""
[ -n "${TASK_NOTIFICATION_JQ_DEF}" ] || TASK_NOTIFICATION_JQ_DEF="${_TN_FALLBACK_DEF}"
# The trailing "end" field is a sentinel: a newline inside transcript_path cuts the read
# short, and acting on the truncated path would silently resolve the wrong conversation.
_meta_extract() {
    printf '%s' "${_INPUT}" | jq -r "$1"' if type == "object" then
    [ ((.transcript_path // "") | tostring),
      ((.prompt // "") | tostring
           | notification_kind),
      "end"
    ] | join("\u001f") else "" end' 2>/dev/null
}
_META="$(_meta_extract "${TASK_NOTIFICATION_JQ_DEF}")"
IFS=$'\x1f' read -r _TP _KIND _END <<EOF
${_META}
EOF
if [ "${_END:-}" != "end" ] && [ "${TASK_NOTIFICATION_JQ_DEF}" != "${_TN_FALLBACK_DEF}" ]; then
    # The shared lib's definition may not compile: classify every prompt as the user.
    _META="$(_meta_extract "${_TN_FALLBACK_DEF}")"
    IFS=$'\x1f' read -r _TP _KIND _END <<EOF
${_META}
EOF
fi
if [ "${_END:-}" != "end" ]; then
    _announce "prompt payload unparseable — unused egress approvals of this conversation (if any) were NOT withdrawn."
    exit 0
fi
[ "${_KIND}" = "notification" ] && exit 0
_CLASSIFY_NOTE=""
[ "${_KIND}" = "unclassifiable" ] && _CLASSIFY_NOTE=" (the prompt could not be classified — e.g. a regex engine limit on a very large prompt — so it was treated as the user speaking)"
_TOKEN="$(session_token_from_transcript "${_TP}")"
if ! egress_valid_token "${_TOKEN}"; then
    _announce "no session identity in the prompt payload — unused egress approvals of this conversation (if any) were NOT withdrawn."
    exit 0
fi
_RV="$(egress_revoke_unused "${_TOKEN}")"
_OK="${_RV%% *}"
_BAD="${_RV##* }"
if [ "${_BAD}" != "0" ]; then
    _announce "${_BAD} unused egress approval(s) from the previous turn could NOT be withdrawn and may still be usable.${_CLASSIFY_NOTE}"
elif [ -n "${_CLASSIFY_NOTE}" ] && [ "${_OK}" != "0" ]; then
    _announce "${_OK} unused egress approval(s) were withdrawn${_CLASSIFY_NOTE}."
fi
exit 0

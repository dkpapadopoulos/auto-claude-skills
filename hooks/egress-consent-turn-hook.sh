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
# Measured live 2026-09-17: a background-task notification arrives as UserPromptSubmit
# whose prompt is the "<task-notification>" block. It is not the user speaking, and treating
# it as a turn boundary revoked a genuine approval mid-flow.
# A prompt counts as a notification only if it consists ENTIRELY of notification blocks:
# a user who pastes one and then writes "no" is the user speaking.
# - A block body may not contain a closing tag (a lazy `.*?` backtracks across one, so
#   text BETWEEN two blocks matched).
# - A nested block — an opening tag right after the outer one, or at the start of a line —
#   is not a notification shape. An opening tag QUOTED mid-line (a command description,
#   an agent result about this feature) is allowed: rejecting it withdrew approvals on
#   genuine notifications.
# - "Start of a line" means after any vertical-space character (LF, CR, VT, FF, NEL,
#   U+2028, U+2029), optionally indented with spaces/tabs.
# - If the regex engine cannot evaluate the prompt (retry limit on multi-MB input), the
#   prompt is treated as the user speaking: withdrawing is the safe direction.
# - Known costs (safe direction, one re-ask): a genuine notification whose text starts a
#   line with an opening tag (an XML example in an agent result), or quotes the CLOSING tag
#   anywhere, is treated as the user.
# - Plain text typed INSIDE one well-formed block is indistinguishable from a
#   notification's free-text fields (agent results are arbitrary): accepted residual.
# Fixture: tests/fixtures/egress-consent/task-notification-bash.txt, captured live
# 2026-09-17 — nothing follows the closing tag. Agent-completion notifications were not
# captured; if one ever carries trailing text it is treated as the user (one re-ask).
# The trailing "end" field is a sentinel: a newline inside transcript_path cuts the read
# short, and acting on the truncated path would silently resolve the wrong conversation.
_META="$(printf '%s' "${_INPUT}" | jq -r 'if type == "object" then
    [ ((.transcript_path // "") | tostring),
      ((.prompt // "") | tostring
           | try (if test("^\\s*(<task-notification>(?![ \\t]*<task-notification>)(?:(?!</task-notification>|[\\n\\r\\v\\f\\x{85}\\x{2028}\\x{2029}][ \\t]*<task-notification>)[\\s\\S])*</task-notification>\\s*)+$")
                  then "notification" else "prompt" end)
             catch "unclassifiable"),
      "end"
    ] | join("\u001f") else "" end' 2>/dev/null)"
IFS=$'\x1f' read -r _TP _KIND _END <<EOF
${_META}
EOF
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

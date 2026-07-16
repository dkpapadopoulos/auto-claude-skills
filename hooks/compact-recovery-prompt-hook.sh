#!/bin/bash
# compact-recovery-prompt-hook.sh — UserPromptSubmit prompt-carrier for
# post-compaction state recovery. Since Claude Code ~2.1.179, AUTO
# compaction no longer emits SessionStart(source=compact), so
# compact-recovery-hook.sh never fires for the unattended case (see
# openspec/changes/compact-recovery-prompt-carrier). PreCompact arms a
# per-token marker; this hook re-injects state on the NEXT prompt and
# consumes the marker. When SessionStart(compact) DOES fire (manual
# /compact), it consumes the marker first — no double injection.
#
# Fail-open: every failure exits 0 silently. Common path (no marker for
# any session) is ONE glob test — no stdin read, no jq fork.

trap 'exit 0' ERR

# Cheap common-path bailout.
compgen -G "${HOME}/.claude/.skill-compact-pending-*" >/dev/null 2>&1 || exit 0

# jq is required both to resolve the token and to emit JSON — bail BEFORE
# consuming the marker so recovery is not lost on a jq-less machine.
command -v jq >/dev/null 2>&1 || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

INPUT=""
if [ ! -t 0 ]; then
    INPUT="$(cat 2>/dev/null)" || INPUT=""
fi
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)" || TRANSCRIPT_PATH=""

# Payload-first token resolution (issue #51); singleton fallback.
_SESSION_TOKEN=""
if [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_session_token_from_transcript >/dev/null 2>&1 && \
        _SESSION_TOKEN="$(resolve_session_token_from_transcript "${TRANSCRIPT_PATH}")"
fi
[ -z "$_SESSION_TOKEN" ] && [ -f "${HOME}/.claude/.skill-session-token" ] && \
    _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
[ -z "$_SESSION_TOKEN" ] && exit 0

MARKER="${HOME}/.claude/.skill-compact-pending-${_SESSION_TOKEN}"
[ -f "$MARKER" ] || exit 0    # another session's marker — not ours to consume

# Stale marker (>24h): a crashed session must not inject into a much later
# one that reuses the token. Consume silently. Numerics validated before
# arithmetic (Bash 3.2 quoted-operand gotcha).
_NOW="$(date +%s 2>/dev/null)" || _NOW=""
_MTIME="$(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null)" || _MTIME=""
if [[ "$_NOW" =~ ^[0-9]+$ ]] && [[ "$_MTIME" =~ ^[0-9]+$ ]]; then
    _AGE=$(( _NOW - _MTIME ))
    if [ "$_AGE" -gt 86400 ]; then
        rm -f "$MARKER" 2>/dev/null
        exit 0
    fi
fi

_TRIGGER="$(sed -n '1s/.*trigger=//p' "$MARKER" 2>/dev/null)" || _TRIGGER=""
rm -f "$MARKER" 2>/dev/null || true

BLOCK=""
if [ -f "${PLUGIN_ROOT}/hooks/lib/compact-recovery-render.sh" ]; then
    # shellcheck source=lib/compact-recovery-render.sh
    . "${PLUGIN_ROOT}/hooks/lib/compact-recovery-render.sh" 2>/dev/null || true
    command -v render_compact_recovery >/dev/null 2>&1 && \
        BLOCK="$(render_compact_recovery "$_SESSION_TOKEN" "$_TRIGGER" 2>/dev/null)" || BLOCK=""
fi
[ -z "$BLOCK" ] && exit 0

_JSON="$(printf '%s' "$BLOCK" | jq -Rs .)" || exit 0
[ -n "$_JSON" ] || exit 0
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
    "$_JSON"

# Telemetry: same log the auto-compact drift was detected in.
printf '%s event=post_compact_prompt trigger=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_TRIGGER:-unknown}" \
    >> "${HOME}/.claude/.compact-events.log" 2>/dev/null || true
exit 0

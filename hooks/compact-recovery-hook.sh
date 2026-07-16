#!/bin/bash
# compact-recovery-hook.sh — Re-inject critical state after compaction
# Runs as SessionStart hook with matcher "compact".
# stdout is injected into Claude's fresh context.

trap 'exit 0' ERR

# --- PATH discovery ---
if ! command -v cozempic >/dev/null 2>&1; then
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
fi

# --- Read the payload FIRST (issue #51) ---
# Token resolution must be payload-first, so stdin is drained before any token
# use (this hook previously read the singleton here and stdin only at the end).
INPUT=""
if [ ! -t 0 ]; then
    INPUT="$(cat 2>/dev/null)" || INPUT=""
fi
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)" || TRANSCRIPT_PATH=""

# --- Reset depth counter (fresh context after compaction) ---
# Payload-first token resolution (issue #51): the singleton races across
# concurrent sessions; our own payload names our conversation.
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
if [ -f "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh"
    _SESSION_TOKEN="$(resolve_session_token_from_transcript "${TRANSCRIPT_PATH}")"
else
    [ -f "${HOME}/.claude/.skill-session-token" ] && _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
if [ -n "$_SESSION_TOKEN" ]; then
    printf '0' > "${HOME}/.claude/.skill-prompt-count-${_SESSION_TOKEN}" 2>/dev/null || true
fi

# --- Consume the pending marker (prompt-carrier coordination; see
# openspec/changes/compact-recovery-prompt-carrier) ---
_TRIGGER=""
if [ -n "$_SESSION_TOKEN" ]; then
    _MARKER="${HOME}/.claude/.skill-compact-pending-${_SESSION_TOKEN}"
    if [ -f "$_MARKER" ]; then
        _TRIGGER="$(sed -n '1s/.*trigger=//p' "$_MARKER" 2>/dev/null)" || _TRIGGER=""
        rm -f "$_MARKER" 2>/dev/null || true
    fi
fi

# --- Re-inject recovery state (shared renderer: team checkpoint,
# composition chain, confirmed intent, active OpenSpec changes) ---
if [ -f "${_PLUGIN_ROOT}/hooks/lib/compact-recovery-render.sh" ]; then
    # shellcheck source=lib/compact-recovery-render.sh
    . "${_PLUGIN_ROOT}/hooks/lib/compact-recovery-render.sh" 2>/dev/null || true
    command -v render_compact_recovery >/dev/null 2>&1 && \
        render_compact_recovery "$_SESSION_TOKEN" "$_TRIGGER" 2>/dev/null
fi

# --- Log post-compaction event ---
# (INPUT and TRANSCRIPT_PATH were extracted at the top, before token use.)
LOG_FILE="$HOME/.claude/.compact-events.log"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    FILE_SIZE=$(stat -f%z "$TRANSCRIPT_PATH" 2>/dev/null || stat -c%s "$TRANSCRIPT_PATH" 2>/dev/null || echo "unknown")
    printf '%s event=post_compact size_bytes=%s path=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$FILE_SIZE" "$TRANSCRIPT_PATH" >> "$LOG_FILE" 2>/dev/null
fi

exit 0

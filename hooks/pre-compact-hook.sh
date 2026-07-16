#!/bin/bash
# pre-compact-hook.sh — log compaction, arm the recovery marker, then
# checkpoint/prune via cozempic (optional dependency).
# Runs on both auto and manual compaction. Fail-open: errors exit 0.
#
# Called by Claude Code PreCompact hook. stdin receives JSON with:
#   session_id, transcript_path, trigger ("auto"|"manual"), cwd
#
# ORDER MATTERS: logging + marker MUST precede the cozempic dependency
# check — auto-compaction recovery rides the marker (prompt-carrier; see
# openspec/changes/compact-recovery-prompt-carrier) and must work on
# machines without cozempic.

set -o pipefail

# --- Read hook input ---
INPUT="$(cat)" || INPUT=""
TRANSCRIPT_PATH=""
TRIGGER="unknown"
if command -v jq >/dev/null 2>&1; then
    # Single jq fork: join transcript_path + trigger on \x1f, split in bash.
    _JQ_OUT="$(printf '%s' "$INPUT" | jq -r '[.transcript_path // "", .trigger // "unknown"] | join("\u001f")' 2>/dev/null)" || _JQ_OUT=""
    if [ -n "$_JQ_OUT" ]; then
        TRANSCRIPT_PATH="${_JQ_OUT%%$'\x1f'*}"
        TRIGGER="${_JQ_OUT#*$'\x1f'}"
    fi
fi

# --- Log compaction event (for future adaptive calibration) ---
LOG_FILE="$HOME/.claude/.compact-events.log"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    FILE_SIZE=$(stat -f%z "$TRANSCRIPT_PATH" 2>/dev/null || stat -c%s "$TRANSCRIPT_PATH" 2>/dev/null || echo "unknown")
    printf '%s trigger=%s size_bytes=%s path=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TRIGGER" "$FILE_SIZE" "$TRANSCRIPT_PATH" >> "$LOG_FILE" 2>/dev/null
fi

# --- Arm the post-compaction recovery marker (prompt-carrier) ---
# Payload-first token resolution (issue #51); singleton fallback.
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
# Payload-first (issue #51): derive the token from THIS payload's own
# transcript_path. The shared singleton (~/.claude/.skill-session-token) has
# last-writer-wins semantics across concurrent sessions, so it must only be
# consulted as a fallback — resolve_session_token_from_transcript already
# does that internally when transcript-derivation is empty.
if [ -f "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_session_token_from_transcript >/dev/null 2>&1 && \
        _SESSION_TOKEN="$(resolve_session_token_from_transcript "${TRANSCRIPT_PATH}")"
fi
# Last-resort fallback if the lib itself was unavailable/unsourceable.
if [ -z "$_SESSION_TOKEN" ] && [ -f "${HOME}/.claude/.skill-session-token" ]; then
    _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
if [ -n "$_SESSION_TOKEN" ]; then
    printf '%s trigger=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TRIGGER" \
        > "${HOME}/.claude/.skill-compact-pending-${_SESSION_TOKEN}" 2>/dev/null || true
fi

# --- cozempic checkpoint + prune (optional; PATH discovery as before) ---
if ! command -v cozempic >/dev/null 2>&1; then
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
fi
if command -v cozempic >/dev/null 2>&1; then
    cozempic checkpoint 2>/dev/null
    cozempic treat current -rx standard --execute 2>/dev/null
fi

exit 0

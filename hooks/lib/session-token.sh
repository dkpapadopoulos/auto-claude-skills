#!/bin/bash
# session-token.sh — shared session-token derivation/resolution.
#
# The token format `session-<transcript-basename>` is defined HERE and only
# here; the SessionStart writer and every hook reader source this file so the
# two can never drift.
#
# Payload-first contract (issue #51): ~/.claude/.skill-session-token is a
# shared singleton with last-writer-wins semantics across concurrent sessions.
# Hooks that receive a stdin payload MUST derive their token from their own
# payload's transcript_path and treat the singleton as fallback only.
#
# Bash 3.2 compatible. Fail-open: functions echo an empty string on failure.

# session_token_from_transcript <transcript_path>
# Echoes session-<basename .jsonl>; echoes nothing on empty/invalid input.
session_token_from_transcript() {
    local _tp="${1:-}" _conv=""
    [ -z "${_tp}" ] && return 0
    _conv="$(basename -- "${_tp}" .jsonl 2>/dev/null)" || _conv=""
    [ -z "${_conv}" ] && return 0
    printf 'session-%s' "${_conv}"
}

# resolve_session_token_from_transcript <transcript_path>
# For hooks that already extracted transcript_path (batched jq call).
# Payload-derived token when possible; singleton fallback; empty on total failure.
resolve_session_token_from_transcript() {
    local _token=""
    _token="$(session_token_from_transcript "${1:-}")"
    if [ -z "${_token}" ]; then
        _token="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)" || _token=""
    fi
    printf '%s' "${_token}"
}

# resolve_session_token <stdin-json>
# Extracts transcript_path itself (one jq fork). Prefer the
# *_from_transcript variant when the caller already has a jq call to batch into.
resolve_session_token() {
    local _json="${1:-}" _tp=""
    if [ -n "${_json}" ] && command -v jq >/dev/null 2>&1; then
        _tp="$(printf '%s' "${_json}" | jq -r '.transcript_path // empty' 2>/dev/null)" || _tp=""
    fi
    resolve_session_token_from_transcript "${_tp}"
}

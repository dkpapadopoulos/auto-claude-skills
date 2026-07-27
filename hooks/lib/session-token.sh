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

# resolve_own_session_token
# For writers running in the MODEL's Bash turn (phase_attest, verify-and-record):
# they have no hook payload, and the singleton is last-writer-wins across
# concurrent sessions — so reading it back names a DIFFERENT conversation and
# the write scatters into a token file the payload-first reader never opens
# (issues #151, #156). CLAUDE_CODE_SESSION_ID names THIS conversation and IS
# the transcript basename readers derive their token from, so the two resolve
# identically. The env value is trusted only when a transcript for it exists at
# ~/.claude/projects/*/<id>.jsonl: that rejects stale, foreign, and injected
# values, and keeps synthetic-HOME sandboxes (this repo's own tests included)
# on the singleton path. Path-unsafe ids are rejected on charset first.
# Falls back to the singleton — never to a locally re-derived shape.
#
# KNOWN LIMIT (subagent identity): a Task subagent gets its own
# CLAUDE_CODE_SESSION_ID and its own transcript on disk, so a writer called
# INSIDE a subagent resolves to the SUBAGENT's token, which the main session's
# UserPromptSubmit-side readers never open. Pre-#156 the singleton happened to
# cover that case, since the main session re-stamps it on every prompt. This is
# still the right trade: the singleton's coverage was accidental and cost
# correctness under concurrent sessions, the far more common case. State that
# must reach the main session's readers should be written from the main turn,
# not delegated to a subagent.
resolve_own_session_token() {
    local _id="${CLAUDE_CODE_SESSION_ID:-}" _t="" _tok=""
    case "${_id}" in
        ""|*[!A-Za-z0-9_-]*) ;;
        *)
            for _t in "${HOME}"/.claude/projects/*/"${_id}.jsonl"; do
                [ -f "${_t}" ] || continue
                # An empty derive falls through to the singleton like every
                # other leg here — returning success with no output would
                # surface to callers as "no session token" instead.
                _tok="$(session_token_from_transcript "${_t}")"
                [ -n "${_tok}" ] && { printf '%s' "${_tok}"; return 0; }
                break
            done
            ;;
    esac
    cat "${HOME}/.claude/.skill-session-token" 2>/dev/null
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

#!/bin/bash
# phase-attest.sh — explicit skip-attestation for composition-chain steps.
# phase_attest <step> <reason> records a logged, review-surfaced skip in
# ~/.claude/.skill-phase-attest-<token>. Gating milestones are NEVER
# attestable: the writer refuses them here AND every reader re-checks
# (two independent locks, like the max_iterations role-allowlist).
# Spec: openspec/changes/phase-enforcement (Scenario 2, 3).

PHASE_ATTEST_GATING_EXCLUDE="requesting-code-review verification-before-completion"

# session-token.sh owns the `session-<transcript-basename>` format ("defined
# HERE and only here") — source it rather than re-deriving the shape below.
# Guarded: if it is unavailable, token resolution degrades to the singleton.
_PHASE_ATTEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "${_PHASE_ATTEST_DIR}/session-token.sh" ] && . "${_PHASE_ATTEST_DIR}/session-token.sh" 2>/dev/null || true

# _phase_attest_token: resolve OUR conversation's token the same way every
# reader does (payload-first, issue #51) rather than trusting the singleton.
# attest runs in the model's Bash turn, which has no hook payload — but it does
# carry CLAUDE_CODE_SESSION_ID, and the reader-side token is
# session-<transcript basename> where that basename IS the session id, so the
# two resolve identically. The singleton is last-writer-wins across concurrent
# sessions and regularly names a DIFFERENT conversation: pre-fix, three attests
# minutes apart in one session landed in three token files and the gate — which
# resolves payload-first — saw none of them (issue #151, reproduced live).
# The resolution itself lives in session-token.sh (which owns the token format
# and is shared with the other Bash-turn writer, issue #156); when that lib is
# unavailable this degrades to the singleton, never to a locally re-derived
# shape that could drift from the readers'.
_phase_attest_token() {
    if command -v resolve_own_session_token >/dev/null 2>&1; then
        resolve_own_session_token
        return 0
    fi
    cat "${HOME}/.claude/.skill-session-token" 2>/dev/null
}

phase_attest() {
    local step="${1:-}" reason="${2:-}"
    [ -z "$step" ] && { echo "[phase-attest] usage: phase_attest <step> <reason>" >&2; return 1; }
    [ -z "$reason" ] && { echo "[phase-attest] a reason is required — attestation is an auditable decision" >&2; return 1; }
    local ex
    for ex in $PHASE_ATTEST_GATING_EXCLUDE; do
        if [ "$step" = "$ex" ]; then
            echo "[phase-attest] REFUSED: '$step' is a gating milestone and cannot be attested away (invoke the real skill)" >&2
            return 1
        fi
    done
    command -v jq >/dev/null 2>&1 || { echo "[phase-attest] jq required" >&2; return 1; }
    local token; token="$(_phase_attest_token)"
    [ -z "$token" ] && { echo "[phase-attest] no session token" >&2; return 1; }
    local f="${HOME}/.claude/.skill-phase-attest-${token}" tmp
    local base
    base="$(jq -c 'if type=="object" then . else {} end' "$f" 2>/dev/null)" || base=""
    [ -z "$base" ] && base="{}"
    tmp="$(printf '%s' "$base" | jq --arg s "$step" --arg r "$reason" \
        '. + {($s): {reason: $r, ts: (now | todate)}}' 2>/dev/null)" || return 1
    [ -z "$tmp" ] && { echo "[phase-attest] internal: merge produced no output" >&2; return 1; }
    printf '%s\n' "$tmp" > "${f}.tmp.$$" 2>/dev/null && mv "${f}.tmp.$$" "$f" 2>/dev/null || return 1
    # Token is logged and echoed: a scattered write is then visible in the
    # telemetry and to the model, instead of failing silently at the gate (#151).
    printf '%s gate=attest decision=recorded step=%s token=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$step" "$token" \
        >> "${HOME}/.claude/.phase-gate-events.log" 2>/dev/null || true
    echo "[phase-attest] recorded skip of '$step' under ${token} — visible at REVIEW" >&2
    return 0
}

# phase_attested <token> <step> — 0 iff attested AND not a gating milestone.
phase_attested() {
    local token="${1:-}" step="${2:-}" ex
    [ -z "$token" ] || [ -z "$step" ] && return 1
    for ex in $PHASE_ATTEST_GATING_EXCLUDE; do
        [ "$step" = "$ex" ] && return 1
    done
    command -v jq >/dev/null 2>&1 || return 1
    local f="${HOME}/.claude/.skill-phase-attest-${token}"
    [ -f "$f" ] || return 1
    jq -e --arg s "$step" 'has($s)' "$f" >/dev/null 2>&1
}

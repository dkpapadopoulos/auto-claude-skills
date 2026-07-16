#!/bin/bash
# phase-attest.sh — explicit skip-attestation for composition-chain steps.
# phase_attest <step> <reason> records a logged, review-surfaced skip in
# ~/.claude/.skill-phase-attest-<token>. Gating milestones are NEVER
# attestable: the writer refuses them here AND every reader re-checks
# (two independent locks, like the max_iterations role-allowlist).
# Spec: openspec/changes/phase-enforcement (Scenario 2, 3).

PHASE_ATTEST_GATING_EXCLUDE="requesting-code-review verification-before-completion"

# _phase_attest_token: singleton read (attest is invoked from the model's
# Bash turn, which has no hook payload; the singleton was re-stamped by the
# activation hook this prompt — issue #51 narrowing applies).
_phase_attest_token() {
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
    local base="{}"
    [ -f "$f" ] && jq empty "$f" >/dev/null 2>&1 && base="$(cat "$f")"
    tmp="$(printf '%s' "$base" | jq --arg s "$step" --arg r "$reason" \
        '. + {($s): {reason: $r, ts: (now | todate)}}' 2>/dev/null)" || return 1
    [ -z "$tmp" ] && return 1
    printf '%s\n' "$tmp" > "${f}.tmp.$$" 2>/dev/null && mv "${f}.tmp.$$" "$f" 2>/dev/null || return 1
    printf '%s gate=attest decision=recorded step=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$step" \
        >> "${HOME}/.claude/.phase-gate-events.log" 2>/dev/null || true
    echo "[phase-attest] recorded skip of '$step' — visible at REVIEW" >&2
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

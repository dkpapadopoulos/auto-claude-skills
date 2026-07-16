#!/bin/bash
# skill-gate.sh — PreToolUse ^Skill$ sequencing gate (phase-enforcement C1).
# Denies invoking a composition-chain member while a required predecessor
# lacks evidence (invocation record OR branch ledger OR attestation —
# NEVER the walker-writable .completed, codex #2). Deny only on
# positive violation evidence; ANY infrastructure failure allows (exit 0,
# no output) — the deliberate inversion of the push gate's fail-closed
# posture (design.md Trade-offs). Human ! commands never reach this hook.
# Spec: openspec/changes/phase-enforcement (Scenarios 1, 2, 4).

trap 'exit 0' ERR

INPUT=""
if [ ! -t 0 ]; then INPUT="$(cat 2>/dev/null)" || INPUT=""; fi
[ -z "$INPUT" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

_F="$(printf '%s' "$INPUT" | jq -r '[(.tool_input.skill // .tool_input.name // ""), (.transcript_path // "")] | join("\u001f")' 2>/dev/null)" || _F=""
_RAW_SKILL="${_F%%$'\x1f'*}"
_TRANSCRIPT="${_F#*$'\x1f'}"
[ -z "$_RAW_SKILL" ] && exit 0
_SKILL="${_RAW_SKILL##*:}"

# Token: payload-first (issue #51), singleton fallback.
_SESSION_TOKEN=""
if [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_session_token_from_transcript >/dev/null 2>&1 && \
        _SESSION_TOKEN="$(resolve_session_token_from_transcript "${_TRANSCRIPT}")"
fi
[ -z "$_SESSION_TOKEN" ] && [ -f "${HOME}/.claude/.skill-session-token" ] && \
    _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
[ -z "$_SESSION_TOKEN" ] && exit 0

_COMP="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
[ -f "$_COMP" ] || exit 0
jq empty "$_COMP" >/dev/null 2>&1 || exit 0

# Invoked skill's chain index. Implementation-slot aliasing (codex #3): if
# the bare name is not a literal member but IS an implementation-slot skill
# and the chain contains a sibling, use the sibling's index — invoking
# agent-team-execution when the chain rendered executing-plans must not
# bypass sequencing. Requires phase-evidence.sh (sourced below) for
# _phase_alias_candidates; source it BEFORE membership resolution.
[ -f "${PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" ] || exit 0
# shellcheck source=lib/phase-evidence.sh
. "${PLUGIN_ROOT}/hooks/lib/phase-evidence.sh" 2>/dev/null || true
command -v phase_step_satisfied >/dev/null 2>&1 || exit 0

_IDX=-1
for _cand in $(_phase_alias_candidates "$_SKILL"); do
    _CI="$(jq -r --arg s "$_cand" '(.chain // []) | index($s) // -1' "$_COMP" 2>/dev/null)" || exit 0
    [[ "$_CI" =~ ^[0-9]+$ ]] && [ "$_CI" -ge 0 ] && { _IDX="$_CI"; break; }
done
[[ "$_IDX" =~ ^-?[0-9]+$ ]] || exit 0
[ "$_IDX" -le 0 ] && exit 0

_PROJ_ROOT="${SKILL_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# First unsatisfied strict predecessor -> violation.
_MISSING=""
_j=0
while [ "$_j" -lt "$_IDX" ]; do
    _STEP="$(jq -r --argjson i "$_j" '(.chain // [])[$i] // empty' "$_COMP" 2>/dev/null)" || exit 0
    [ -z "$_STEP" ] && break
    if ! phase_step_satisfied "$_SESSION_TOKEN" "$_STEP" "$_PROJ_ROOT"; then
        _MISSING="$_STEP"
        break
    fi
    _j=$(( _j + 1 ))
done
if [ -z "$_MISSING" ]; then
    phase_gate_log "skill-seq" "allow" "$_SKILL" "-"
    exit 0
fi

# Mode: deny | warn | off. Default: deny ONLY in the plugin's own source repo
# (identity via plugin manifest name, codex #8 — a generic
# config/default-triggers.json path would false-deny unrelated external
# repos that happen to ship that file); warn everywhere else.
_MODE=""
[ -f "${HOME}/.claude/skill-config.json" ] && \
    _MODE="$(jq -r '.phase_enforcement.skill_sequencing // empty' "${HOME}/.claude/skill-config.json" 2>/dev/null)" || _MODE=""
if [ -z "$_MODE" ]; then
    _REPO_ID="$(jq -r '.name // empty' "${_PROJ_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)" || _REPO_ID=""
    if [ "$_REPO_ID" = "auto-claude-skills" ]; then _MODE="deny"; else _MODE="warn"; fi
fi
[ "$_MODE" = "off" ] && exit 0

_MSG="PHASE GATE — Step '${_MISSING}' has no invocation evidence, but Skill(${_RAW_SKILL}) comes after it in the composition chain. Do now (one of): (1) invoke the missing step: Skill(${_MISSING}); (2) record an explicit, review-surfaced skip: source \"\$CLAUDE_PLUGIN_ROOT/hooks/lib/phase-attest.sh\" && phase_attest ${_MISSING} \"<reason>\"; (3) human bypass: run the action yourself with the ! prefix. Gating milestones (requesting-code-review, verification-before-completion) accept only real invocations."
if [ "$_MODE" = "warn" ]; then
    phase_gate_log "skill-seq" "warn" "$_SKILL" "$_MISSING"
    jq -n --arg msg "PHASE GATE (advisory): $_MSG" '{"systemMessage":$msg}'
    exit 0
fi
phase_gate_log "skill-seq" "deny" "$_SKILL" "$_MISSING"
jq -n --arg msg "$_MSG" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
exit 0

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
# --- Diagnostic capture (issue #177) — OFF the decision path ----------------
# Two Skill() calls were denied live while replaying this file on disk ALLOWED
# every time, and nothing recorded which file actually ran. This is the
# Skill-gate analogue of the push gate's #127 instrument.
#
# NEVER SOURCED: a source-time failure would trip the fail-open `trap 'exit 0'
# ERR` above and skip enforcement entirely. It fires an external subprocess from
# a hardened EXIT trap, which disarms both traps first so a failing capture
# command cannot re-enter them, and redirects the subshell so it cannot leak a
# byte into the one-JSON-object contract.
#
# Armed HERE rather than at the deny site: most exits in this gate are early
# `exit 0`s, and a record only for denies would leave the log with no
# denominator — the same incompleteness the push-gate log documents.
_SG_DECISION="allow"
if [ "${SKILL_GATE_CAPTURE_DISABLE:-}" != "1" ]; then
    # No "is capture still active?" flag here. The trap is installed only inside
    # this branch, so it cannot fire with capture disabled — a guard for that
    # state would be unreachable, and unreachable code in a gate reads as
    # coverage it does not provide (the same reason the token/jq re-checks were
    # removed from the implement-leg probe). If a future path needs to suppress
    # capture after arming, `trap - EXIT` is the honest way to say so.
    _sg_capture_on_exit() {
        trap - ERR
        trap - EXIT
        (
            exec </dev/null >/dev/null 2>&1
            SGC_DECISION="${_SG_DECISION:-allow}" SGC_SKILL="${_RAW_SKILL:-}" \
            SGC_SESSION_TOKEN="${_SESSION_TOKEN:-}" SGC_TRANSCRIPT="${_TRANSCRIPT:-}" \
            SGC_GATE_PATH="${BASH_SOURCE:-$0}" SGC_INPUT="${INPUT:-}" \
            "${PLUGIN_ROOT}/scripts/skill-gate-capture.sh"
        ) || true
        return 0
    }
    trap '_sg_capture_on_exit' EXIT
fi

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
# Validate enum: invalid config values fall back to default (computed above).
case "$_MODE" in deny|warn|off) ;; *) _MODE=""; [ -f "${_PROJ_ROOT}/.claude-plugin/plugin.json" ] && \
    _REPO_ID="$(jq -r '.name // empty' "${_PROJ_ROOT}/.claude-plugin/plugin.json" 2>/dev/null)" || _REPO_ID=""; \
    if [ "$_REPO_ID" = "auto-claude-skills" ]; then _MODE="deny"; else _MODE="warn"; fi ;; esac

# Positive "reached the decision point" sentinel for the capture replay (#177).
# Placed BEFORE the branch, so an ALLOW emits it too — with it only on the deny
# path, a genuine allow would replay as `incomplete` and every allow would look
# like a crash. The replayed gate is itself fail-open, so empty stdout cannot
# distinguish "allowed" from "died early"; this is what makes the distinction
# POSITIVE rather than inferred from silence.
#
# Under the replay flag ONLY. Live operation emits exactly the one JSON object
# it always did — the harness contract is one object, and a stray line would
# break it.
[ "${SKILL_GATE_CAPTURE_REPLAY:-}" = "1" ] && printf '__SGC_EVALUATED__\n'

if [ "$_MODE" = "off" ]; then
    phase_gate_log "skill-seq" "off" "$_SKILL" "$_MISSING"
    exit 0
fi

# The attestation remedy names the RESOLVED plugin root (#248). It previously
# offered `$(git rev-parse --show-toplevel)/hooks/lib/...` || `$CLAUDE_PLUGIN_ROOT/...`
# and both halves fail outside this repo: the first is the USER's repo root,
# which has no hooks/lib, and CLAUDE_PLUGIN_ROOT is unset in the model's shell.
# This hook already resolved PLUGIN_ROOT; telling an agent how to find this
# hook's own libs, while holding that path, was the avoidable indirection.
# SINGLE-quoted on purpose: this text is pasted into a shell, and a double
# quoted path expands `$…` and EXECUTES backticks (measured, both shells).
# PAIRED with openspec-guard.sh::_attest_remedy and the {{PLUGIN_ROOT}}
# substitution in skill-activation-hook.sh — three renderings, one shape.
# The path goes into the message inside literal single quotes, so a `'` in it
# would close the quote and break the pasted command (measured: an install path
# of /tmp/od'd/plug emitted `source '/tmp/od'd/...'`, an unterminated string).
# openspec-guard.sh escapes via _shq and skill-activation-hook.sh via the same
# pattern; this was the one unescaped site of the three. Fork-free, because
# inside double quotes `\'` is NOT an escape — it is a backslash and a quote —
# so the replacement is built from single-character variables.
_SQ="'" ; _BS='\' ; _PR_SQ="${PLUGIN_ROOT//${_SQ}/${_SQ}${_BS}${_SQ}${_SQ}}"
_MSG="PHASE GATE — Step '${_MISSING}' has no invocation evidence, but Skill(${_RAW_SKILL}) comes after it in the composition chain. Do now (one of): (1) invoke the missing step: Skill(${_MISSING}); (2) record an explicit, review-surfaced skip: source '${_PR_SQ}/hooks/lib/phase-attest.sh'; phase_attest ${_MISSING} \"<reason>\"; (3) human bypass: run the action yourself with the ! prefix. Gating milestones (requesting-code-review, verification-before-completion) accept only real invocations."
if [ "$_MODE" = "warn" ]; then
    phase_gate_log "skill-seq" "warn" "$_SKILL" "$_MISSING"
    jq -n --arg msg "PHASE GATE (advisory): $_MSG" '{"systemMessage":$msg}'
    exit 0
fi
phase_gate_log "skill-seq" "deny" "$_SKILL" "$_MISSING"
# permissionDecisionReason is the ONLY field Claude Code shows the MODEL on a
# deny; systemMessage is shown to the user and never to Claude (#254). The
# remediation above is useless in a channel the model cannot read, so both
# carry the same text: the user sees it, and the agent can act on it.
_SG_DECISION="deny"
jq -n --arg msg "$_MSG" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$msg},"systemMessage":$msg}'
exit 0

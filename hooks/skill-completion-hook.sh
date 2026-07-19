#!/bin/bash
# skill-completion-hook.sh — PostToolUse on ^Skill$
# Advances composition-state .completed when a chain-member Skill tool
# returns successfully. Bash 3.2 compatible. Exits 0 always (fail-open).
#
# Closes the chain-walker blind spot: the walker (skill-activation-hook.sh)
# only advances .completed on UserPromptSubmit trigger matches, so skill
# invocations inside a single assistant turn never update state. This hook
# is the second writer — same file, same merge shape, narrower scope.
#
# Design: docs/plans/2026-04-19-skill-completion-hook-design.md

trap 'exit 0' ERR
set -uo pipefail

_INPUT="$(cat 2>/dev/null)"
[ -z "${_INPUT}" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0

# Batch transcript + is_error + skill name into ONE jq fork (was two) —
# \x1f-joined, controlled fields only.
_FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[.transcript_path // "", (.tool_response.is_error // false | tostring), (.tool_input.name // .tool_input.skill // "")] | join("\u001f")' 2>/dev/null)" || _FIELDS=""
_TRANSCRIPT="${_FIELDS%%$'\x1f'*}"
_REST="${_FIELDS#*$'\x1f'}"
_IS_ERROR="${_REST%%$'\x1f'*}"
_RAW="${_REST#*$'\x1f'}"

# Resolve session token payload-first (issue #51): the singleton is shared
# across concurrent sessions (last-writer-wins) and may name ANOTHER session.
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
if [ -f "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh"
    _SESSION_TOKEN="$(resolve_session_token_from_transcript "${_TRANSCRIPT}")"
else
    [ -f "${HOME}/.claude/.skill-session-token" ] && \
        _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
[ -z "${_SESSION_TOKEN}" ] && exit 0

[ "${_IS_ERROR}" = "true" ] && exit 0
[ -z "${_RAW}" ] && exit 0

_BARE="${_RAW##*:}"
[ -z "${_BARE}" ] && exit 0

# --- Append-only invocation record (phase-enforcement provenance split).
# The gates trust THIS file, never the walker-writable .completed: a
# successful Skill return is the only writer path (codex #2). Runs for ANY
# successful skill return (chain member or not) — a later chain re-anchor
# must still be able to find pre-anchor evidence. Deliberately evaluated
# BEFORE the composition-state checks below (moved up from its original
# position): roughly a third of skills never trigger composition-state
# creation, so gating this write on the state file's existence made real
# invocations invisible to phase_step_satisfied (review HIGH finding).
_INVOC="${HOME}/.claude/.skill-invocation-evidence-${_SESSION_TOKEN}"
_IBASE="[]"
[ -f "${_INVOC}" ] && jq empty "${_INVOC}" >/dev/null 2>&1 && _IBASE="$(cat "${_INVOC}")"
_ITMP="$(printf '%s' "${_IBASE}" | jq --arg s "${_BARE}" 'if index($s) == null then . + [$s] else . end' 2>/dev/null)" || _ITMP=""
if [ -n "${_ITMP}" ]; then
    printf '%s\n' "${_ITMP}" > "${_INVOC}.tmp.$$" 2>/dev/null && \
        mv "${_INVOC}.tmp.$$" "${_INVOC}" 2>/dev/null || rm -f "${_INVOC}.tmp.$$" 2>/dev/null || true
fi

# ---- Durable gating-milestone ledger (push-gate readiness, branch-scoped) ----
# Record review/verify completion to a per-(repo+branch) ledger so the push gate
# survives composition chain re-anchors that reset .completed. Fail-open.
# STATE-INDEPENDENT (issue #131): evaluated BEFORE the composition-state gate
# below — under concurrent-session token scattering the state file may not
# exist for this hook's resolved token, and the ledger is the documented
# cross-session carrier, so a real gating-Skill return must always record
# (same rationale as the invocation record's earlier move).
# Review-embedding skills (subagent-driven-development, agent-team-execution,
# agent-team-review) each carry a mandated internal review, so they credit the
# canonical `requesting-code-review` milestone — the same "skill-ran" proxy the
# gate already trusts for the literal review skill.
_record_gating_milestone() {
    [ -f "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" ] || return 0
    # shellcheck source=lib/branch-ledger.sh
    # `|| true` so a non-zero source cannot trip `trap ERR` and skip the rest.
    . "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null || true
    command -v branch_ledger_record >/dev/null 2>&1 || return 0
    branch_ledger_record "$1" 2>/dev/null || true
}
# PAIRED: these milestone names are also excluded from the walker's back-fill
# prefix (skill-activation-hook.sh gating-milestone filter), checked by
# openspec-guard.sh, and the proxy list is mirrored by the guard's
# invocation-evidence review leg — a third gated milestone must be added in
# all of them.
case "${_BARE}" in
    requesting-code-review|verification-before-completion)
        _record_gating_milestone "${_BARE}" ;;
    subagent-driven-development|agent-team-execution|agent-team-review)
        # subagent-driven-development's review mandate lives in the EXTERNAL
        # superpowers plugin ("review after each task" in its SKILL.md) — not
        # verifiable from this repo; re-check if superpowers drops that step.
        # The two agent-team-* skills are owned here (skills/<name>/SKILL.md).
        _record_gating_milestone "requesting-code-review" ;;
esac

# ---- Composition-state-dependent sections below (chain .completed merge,
# per-chain-step ledger, C1 telemetry). All require the state file to exist
# and be valid JSON — same early-exit gate as before restructuring, just
# evaluated after the state-independent invocation record and
# gating-milestone ledger writes above.
_STATE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
[ -f "${_STATE}" ] || exit 0
jq empty "${_STATE}" >/dev/null 2>&1 || exit 0

_TMP="$(jq --arg s "${_BARE}" '
  if ((.chain // []) | index($s)) != null
     and (((.completed // []) | index($s)) == null)
  then
    .completed = ((.completed // []) + [$s])
    | .current = (
        (.chain // [])[(((.chain // []) | index($s)) + 1)] // .current
      )
  else . end
' "${_STATE}" 2>/dev/null)" || exit 0

[ -z "${_TMP}" ] && exit 0
printf '%s\n' "${_TMP}" > "${_STATE}.tmp.$$" 2>/dev/null && \
    mv "${_STATE}.tmp.$$" "${_STATE}" 2>/dev/null || exit 0

[ -n "${SKILL_EXPLAIN:-}" ] && \
    printf '[skill-hook]   [completion] %s → completed\n' "${_BARE}" >&2

# ---- Durable per-branch ledger for ALL chain-step returns (codex #4) ----
# Re-anchors reset session .completed state but must not erase evidence that
# a chain step already ran. Scoped to chain members (mirrors the
# gating-milestone ledger above) — distinct from the invocation record above,
# which records every successful skill return regardless of chain membership.
if jq -e --arg s "${_BARE}" '(.chain // []) | index($s) != null' "${_STATE}" >/dev/null 2>&1; then
    [ -f "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" ] && \
        . "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null || true
    command -v branch_ledger_record >/dev/null 2>&1 && \
        branch_ledger_record "${_BARE}" "" 2>/dev/null || true
fi

# ---- C1: passive advisory-lens telemetry ----
# Append one JSONL line per Skill completion. Fail-open: any error is silently
# dropped. Schema is intentionally minimal — no labels, no counterfactual
# claims. Substrate for evidence-based trim decisions in 30+ days.
_TELEMETRY_LOG="${HOME}/.claude/.advisory-lens-log.jsonl"
_TELEMETRY_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
# Hashed token: sha256 first 12 hex chars. Pattern from PR #36
# (project_serena_pnp_and_measurement memory).
_TELEMETRY_HASH=""
if command -v shasum >/dev/null 2>&1; then
    _TELEMETRY_HASH="$(printf '%s' "${_SESSION_TOKEN}" | shasum -a 256 2>/dev/null | cut -c1-12)"
elif command -v sha256sum >/dev/null 2>&1; then
    _TELEMETRY_HASH="$(printf '%s' "${_SESSION_TOKEN}" | sha256sum 2>/dev/null | cut -c1-12)"
fi

# finding_count_estimate: line count of tool_response.content. Coarse proxy
# only — distinguishes "no findings" (~0 lines) from "many findings" (50+ lines).
_TELEMETRY_LINES="$(printf '%s' "${_INPUT}" | jq -r '
    .tool_response.content // .tool_response.output // ""
' 2>/dev/null | wc -l 2>/dev/null | tr -d '[:space:]')"
[ -z "${_TELEMETRY_LINES}" ] && _TELEMETRY_LINES="0"

jq -nc \
    --arg ts "${_TELEMETRY_TS}" \
    --arg skill "${_BARE}" \
    --argjson count "${_TELEMETRY_LINES}" \
    --arg hash "${_TELEMETRY_HASH}" \
    '{ts: $ts, skill: $skill, finding_count_estimate: $count, session_token_hashed: $hash}' \
    >> "${_TELEMETRY_LOG}" 2>/dev/null || true
# ---- end C1 ----

exit 0

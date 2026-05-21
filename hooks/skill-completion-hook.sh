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

[ -f "${HOME}/.claude/.skill-session-token" ] || exit 0
_SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
[ -z "${_SESSION_TOKEN}" ] && exit 0

_STATE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
[ -f "${_STATE}" ] || exit 0
jq empty "${_STATE}" >/dev/null 2>&1 || exit 0

_IS_ERROR="$(printf '%s' "${_INPUT}" | jq -r '.tool_response.is_error // false' 2>/dev/null)"
[ "${_IS_ERROR}" = "true" ] && exit 0

_RAW="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.name // .tool_input.skill // ""' 2>/dev/null)"
[ -z "${_RAW}" ] && exit 0

_BARE="${_RAW##*:}"
[ -z "${_BARE}" ] && exit 0

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

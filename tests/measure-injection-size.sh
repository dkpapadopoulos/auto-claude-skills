#!/usr/bin/env bash
# Phase 0: measure the token savings of the lean injection tier vs the full tier.
# Deterministic — no model invocation. Builds the real registry from repo config
# in a temp HOME so it does not touch the user's ~/.claude.
set -u

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
SESSION_START="${PROJECT_ROOT}/hooks/session-start-hook.sh"
PROMPT="${1:-build a secure frontend component and review it for security}"
GATE_TOKENS=200   # pre-committed: proceed to Phase 1 only if savings >= this

TMP_HOME="$(mktemp -d)"
trap 'rm -rf "${TMP_HOME}"' EXIT
mkdir -p "${TMP_HOME}/.claude"

# Build the real registry from repo config into the temp HOME.
HOME="${TMP_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    bash "${SESSION_START}" >/dev/null 2>&1 || true

run() {  # $1 = extra env assignment ("" or "SKILL_LEAN_TIER=1")
    local extra="$1"
    rm -f "${TMP_HOME}/.claude/.skill-prompt-count-"* "${TMP_HOME}/.claude/.skill-session-token" 2>/dev/null
    jq -n --arg p "${PROMPT}" '{"prompt":$p}' | \
        env HOME="${TMP_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ${extra} \
        bash "${HOOK}" 2>/dev/null | \
        jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

FULL="$(run "")"
LEAN="$(run "SKILL_LEAN_TIER=1")"

full_b="$(printf '%s' "${FULL}" | wc -c | tr -d ' ')"
lean_b="$(printf '%s' "${LEAN}" | wc -c | tr -d ' ')"
delta_b=$(( full_b - lean_b ))
full_t=$(( full_b / 4 )); lean_t=$(( lean_b / 4 )); delta_t=$(( delta_b / 4 ))
pct=0; [[ "${full_b}" -gt 0 ]] && pct=$(( delta_b * 100 / full_b ))

echo "Prompt:        ${PROMPT}"
echo "Full tier:     ${full_b} bytes (~${full_t} tokens)"
echo "Lean tier:     ${lean_b} bytes (~${lean_t} tokens)"
echo "Savings:       ${delta_b} bytes (~${delta_t} tokens, ${pct}%)"
echo "Gate (>=${GATE_TOKENS} tokens): $([[ "${delta_t}" -ge "${GATE_TOKENS}" ]] && echo "PROCEED to Phase 1" || echo "STOP — not worth Phase 1")"

# Sanity: fail loudly if the full tier never rendered (registry build failed)
if [[ "${full_b}" -lt 50 ]]; then
    echo "WARN: full tier output suspiciously small — registry may not have built; verdict unreliable." >&2
    exit 3
fi

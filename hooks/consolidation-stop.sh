#!/bin/bash
# Consolidation stop hook — reminds about memory consolidation when session ends
# and writes learn baselines for any shipped features with hypotheses.
# Stop hook. Bash 3.2 compatible. Exits 0 always (advisory, fail-open).
trap 'exit 0' ERR

# Resolve session token payload-first (issue #51); Stop hooks receive a JSON
# payload with transcript_path on stdin. Empty-token exit preserves the prior
# missing-singleton behavior (skip everything, fail-open).
_INPUT=""
if [ ! -t 0 ]; then
    _INPUT="$(cat 2>/dev/null)" || _INPUT=""
fi
_PLUGIN_ROOT_TOK="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
if [ -f "${_PLUGIN_ROOT_TOK}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT_TOK}/hooks/lib/session-token.sh"
    _SESSION_TOKEN="$(resolve_session_token "${_INPUT}")"
else
    [ -f "${HOME}/.claude/.skill-session-token" ] && _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
[ -z "${_SESSION_TOKEN}" ] && exit 0

_proj_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- Learn baseline write (safety net for hypothesis loop) ---
# Iterates change slugs with non-empty hypotheses; the helper skips when no ship
# signal (no archived_at and no openspec/changes/archive/<slug>/), so this is
# idempotent and harmless when nothing has shipped.
if [ -n "${_SESSION_TOKEN}" ] && command -v jq >/dev/null 2>&1; then
    _STATE_FILE="${HOME}/.claude/.skill-openspec-state-${_SESSION_TOKEN}"
    if [ -f "${_STATE_FILE}" ]; then
        _PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
        _HELPER_LIB="${_PLUGIN_ROOT}/hooks/lib/openspec-state.sh"
        if [ -f "${_HELPER_LIB}" ]; then
            # shellcheck source=lib/openspec-state.sh
            . "${_HELPER_LIB}"
            _SLUGS="$(jq -r '.changes | to_entries[] | select(.value.hypotheses != null and (.value.hypotheses | length) > 0) | .key' "${_STATE_FILE}" 2>/dev/null)"
            for _slug in ${_SLUGS}; do
                openspec_state_write_learn_baseline "${_SESSION_TOKEN}" "${_slug}" 2>/dev/null || true
            done
        fi
    fi
fi

# Check consolidation marker freshness
# Marker path is keyed off git remote URL (stable across worktrees/clones of
# the same repo); path-based fallback when no remote is configured. Must match
# openspec-guard.sh and the ship-and-learn consolidation recipe.
_PLUGIN_ROOT_LIB="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ -f "${_PLUGIN_ROOT_LIB}/hooks/lib/consol-marker.sh" ]; then
    # shellcheck source=lib/consol-marker.sh
    . "${_PLUGIN_ROOT_LIB}/hooks/lib/consol-marker.sh"
    _consol_marker="$(consol_marker_path "${_proj_root}")"
else
    _proj_hash="$(printf '%s' "${_proj_root}" | shasum | cut -d' ' -f1)"
    _consol_marker="${HOME}/.claude/.context-stack-consolidated-${_proj_hash}"
fi

if [ -f "${_consol_marker}" ]; then
    _marker_time="$(stat -f %m "${_consol_marker}" 2>/dev/null || stat -c %Y "${_consol_marker}" 2>/dev/null || echo 0)"
    _last_commit="$(git -C "${_proj_root}" log -1 --format=%ct 2>/dev/null || echo 0)"
    [ "${_marker_time}" -ge "${_last_commit}" ] && exit 0
fi

# Marker is stale or missing — build tier-specific guidance
_CACHE="${HOME}/.claude/.skill-registry-cache.json"
_GUIDANCE="Append findings to docs/learnings.md before ending the session."

if [ -f "${_CACHE}" ] && command -v jq >/dev/null 2>&1; then
    _fm="$(jq -r '.context_capabilities.forgetful_memory // false' "${_CACHE}" 2>/dev/null)" || true
    _chub="$(jq -r '.context_capabilities.context_hub_cli // false' "${_CACHE}" 2>/dev/null)" || true
    if [ "${_fm}" = "true" ]; then
        _GUIDANCE="Use discover_forgetful_tools then execute_forgetful_tool to store architectural learnings from this session."
    elif [ "${_chub}" = "true" ]; then
        _GUIDANCE="Use chub annotate to record API workarounds discovered."
    fi
fi

_MSG="CONSOLIDATION: Session ending. Before you stop, enumerate the durable, team-relevant learnings from this session, route each to the correct backend (auto-memory for project-local facts; .claude/knowledge for durable team gotchas/decisions/conventions; Forgetful for cross-session architecture), and persist them now. Skip transient or personal context. ${_GUIDANCE}"
if command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "${_MSG}" '{"stopReason":$msg}'
else
    printf '{"stopReason":"%s"}\n' "${_MSG}"
fi
exit 0

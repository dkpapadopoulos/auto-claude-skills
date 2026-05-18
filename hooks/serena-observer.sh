#!/bin/bash
# Serena observer — silent PreToolUse hook on Read|Glob|Edit. Logs candidate
# missed-opportunity classes to ~/.claude/.serena-nudge-telemetry. Never emits
# user-visible additionalContext. Used to gather evidence for the parked-matcher
# revival criteria documented in
# docs/plans/archive/2026-05-07-serena-triggering-redesign-design.md
# (also captured in openspec/specs/skill-routing/spec.md).
# Telemetry schema: see hooks/serena-nudge.sh (canonical reference). $5 is the
# class field — the join key across nudge / observe / followup records.
#
# Bash 3.2 compatible. Fail-open (exit 0 on any error). jq required; no-op when
# jq is unavailable.
trap 'exit 0' ERR

[ "${SERENA_TELEMETRY:-1}" = "0" ] && exit 0

_INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

_TOOL="$(printf '%s' "${_INPUT}" | jq -r '.tool_name // empty' 2>/dev/null)"
case "${_TOOL}" in
    Read|Glob|Edit) ;;
    *) exit 0 ;;
esac

_CACHE="${HOME}/.claude/.skill-registry-cache.json"
[ -f "${_CACHE}" ] || exit 0
_SERENA="$(jq -r '.context_capabilities.serena // false' "${_CACHE}" 2>/dev/null)"
[ "${_SERENA}" = "true" ] || exit 0

_TELEM="${HOME}/.claude/.serena-nudge-telemetry"
_TS="$(date +%s 2>/dev/null || echo 0)"
# Hash CLAUDE_SESSION_TOKEN to a 12-char hex prefix for telemetry. Raw token
# stays in env; only the hash is persisted. Fail-open: if sha256sum is
# unavailable, fall back to the raw token.
_TOKEN_RAW="${CLAUDE_SESSION_TOKEN:-unknown}"
if [ "${_TOKEN_RAW}" = "unknown" ] || ! command -v sha256sum >/dev/null 2>&1; then
    _TOKEN="${_TOKEN_RAW}"
else
    _TOKEN="$(printf '%s' "${_TOKEN_RAW}" | sha256sum 2>/dev/null | cut -c1-12)"
    [ -n "${_TOKEN}" ] || _TOKEN="${_TOKEN_RAW}"
fi
_TURN="${CLAUDE_TURN_ID:-0}"

_log() {
    local class="$1" detail="${2:-}"
    printf '%s\t%s\t%s\tobserve\t%s\t%s\n' "${_TS}" "${_TOKEN}" "${_TURN}" "${class}" "${detail}" >>"${_TELEM}" 2>/dev/null || true
}

_is_source_path() {
    case "$1" in
        *.ts|*.tsx|*.js|*.jsx|*.py|*.go|*.rs|*.java|*.kt|*.scala|*.rb|*.cs|*.cpp|*.cc|*.c|*.h|*.hpp|*.swift|*.m|*.mm) return 0 ;;
    esac
    return 1
}

case "${_TOOL}" in
    Read)
        _PATH="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
        [ -n "${_PATH}" ] || exit 0
        _OFFSET="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.offset // empty' 2>/dev/null)"
        _LIMIT="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.limit // empty' 2>/dev/null)"
        [ -n "${_OFFSET}" ] && exit 0
        [ -n "${_LIMIT}" ] && exit 0
        _is_source_path "${_PATH}" || exit 0
        [ -f "${_PATH}" ] || exit 0
        _LINES="$(wc -l <"${_PATH}" 2>/dev/null || echo 0)"
        [ "${_LINES}" -gt 500 ] || exit 0
        _log "read_large_source" "${_PATH}"
        ;;

    Glob)
        _PATTERN="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.pattern // empty' 2>/dev/null)"
        [ -n "${_PATTERN}" ] || exit 0
        # Reject explicit non-source / enumeration globs first.
        case "${_PATTERN}" in
            *.md*|*.json*|*.yaml*|*.yml*|*.lock*|*.test.*|*.spec.*) exit 0 ;;
        esac
        # Definition-hunt heuristic: pattern contains a CamelCase token between wildcards.
        if printf '%s' "${_PATTERN}" | grep -qE '\*[^*/]*[A-Z][a-zA-Z0-9]+[^*/]*\*' 2>/dev/null; then
            _log "glob_definition_hunt" "${_PATTERN}"
        fi
        ;;

    Edit)
        _PATH="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
        _OLD="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.old_string // empty' 2>/dev/null)"
        _NEW="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.new_string // empty' 2>/dev/null)"
        [ -n "${_PATH}" ] && [ -n "${_OLD}" ] && [ -n "${_NEW}" ] || exit 0
        _is_source_path "${_PATH}" || exit 0
        case "${_OLD}" in *$'\n'*) exit 0 ;; esac
        case "${_NEW}" in *$'\n'*) exit 0 ;; esac
        printf '%s' "${_OLD}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' 2>/dev/null || exit 0
        printf '%s' "${_NEW}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' 2>/dev/null || exit 0
        [ "${_OLD}" != "${_NEW}" ] || exit 0
        _log "edit_symbol_token" "${_OLD}->${_NEW}"
        ;;
esac

exit 0

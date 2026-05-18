#!/bin/bash
# Serena nudge — hints when Grep is used for symbol lookups while serena=true
# PreToolUse hook. Bash 3.2 compatible. Exits 0 always (hint only, fail-open).
#
# Design choice: Serena v1.1+ ships its own `serena-hooks remind` PreToolUse hook
# that fires on ALL tool calls and tracks consecutive non-Serena usage. We keep
# this plugin-native hook instead because:
#   1. It checks registry state (serena=true) — safe when Serena is not installed.
#   2. It only fires on Grep with symbol-like patterns — lower overhead.
#   3. Serena's hooks require `serena-hooks` binary; plugin hooks must work for all users.
# Users wanting broader drift protection can add `serena-hooks remind` via /setup.
trap 'exit 0' ERR

_INPUT="$(cat)"

# Fast path: only care about Grep (matcher should handle this, but double-check)
_TOOL_NAME=""
if command -v jq >/dev/null 2>&1; then
    _TOOL_NAME="$(printf '%s' "${_INPUT}" | jq -r '.tool_name // empty' 2>/dev/null)" || true
fi
[ "${_TOOL_NAME}" = "Grep" ] || exit 0

# Check serena availability from cached registry
_CACHE="${HOME}/.claude/.skill-registry-cache.json"
[ -f "${_CACHE}" ] || exit 0
_SERENA="$(jq -r '.context_capabilities.serena // false' "${_CACHE}" 2>/dev/null)" || true
[ "${_SERENA}" = "true" ] || exit 0

# Check if pattern looks like a symbol lookup
_PATTERN="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.pattern // empty' 2>/dev/null)" || true
[ -n "${_PATTERN}" ] || exit 0

# Classify the pattern. Empty class means "do not fire".
_CLASS=""

# 1. Definition prefix — works for both literal and regex variants.
case "${_PATTERN}" in
    *"class "*|*"def "*|*"function "*|*"func "*|*"interface "*|*"struct "*|*"import "*|*"type "*)
        _CLASS="definition_prefix"
        ;;
esac

# 2. Plain CamelCase / snake_case (legacy class).
if [ -z "${_CLASS}" ]; then
    if printf '%s' "${_PATTERN}" | grep -qE '^[A-Z][a-zA-Z0-9]+$' 2>/dev/null; then
        _CLASS="camelcase"
    elif printf '%s' "${_PATTERN}" | grep -qE '^[a-z_][a-z0-9_]+$' 2>/dev/null; then
        _CLASS="snake_case"
    fi
fi

# 3. Word-boundary symbol — \bIdentifier\b or ^Identifier$.
if [ -z "${_CLASS}" ]; then
    if printf '%s' "${_PATTERN}" | grep -qE '^\\b[A-Za-z_][A-Za-z0-9_]*\\b$' 2>/dev/null; then
        _CLASS="word_boundary"
    elif printf '%s' "${_PATTERN}" | grep -qE '^\^[A-Za-z_][A-Za-z0-9_]*\$$' 2>/dev/null; then
        _CLASS="word_boundary"
    fi
fi

# 4. Dotted / qualified member access — Foo\.bar or Foo::bar (one level).
if [ -z "${_CLASS}" ]; then
    if printf '%s' "${_PATTERN}" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*(\\\.|::)[A-Za-z_][A-Za-z0-9_]*$' 2>/dev/null; then
        _CLASS="dotted_qualified"
    fi
fi

# 5. Suppress on patterns that are clearly not symbol shapes:
#    - heavy alternation (3+ alternatives)
#    - lookaround
#    - broad character classes containing whitespace
# Suppressors are authoritative — definition-prefix wrapped in heavy alternation
# is treated as a free-text grep, not a symbol lookup, per the spec MUST NOT.
if [ -n "${_CLASS}" ]; then
    if printf '%s' "${_PATTERN}" | grep -qE '\|.*\|.*\|' 2>/dev/null; then
        _CLASS=""
    elif printf '%s' "${_PATTERN}" | grep -qE '\(\?[=!<]' 2>/dev/null; then
        _CLASS=""
    elif printf '%s' "${_PATTERN}" | grep -qE '\[[^]]* [^]]*\]' 2>/dev/null; then
        _CLASS=""
    fi
fi

[ -n "${_CLASS}" ] || exit 0

_MSG="Serena is available. Consider find_symbol or get_symbols_overview for symbol lookups instead of Grep."
if command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":$msg}}'
else
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "${_MSG}"
fi

# Telemetry — append-only TSV. Disabled by SERENA_TELEMETRY=0.
# Schema: <ts>\t<token>\t<turn>\t<kind>\t<class>\t<detail>
#   - kind ∈ {nudge, observe, followup}
#   - class ∈ pattern class for nudge (camelcase, snake_case, word_boundary,
#     dotted_qualified, definition_prefix), observation class for observe
#     (read_large_source, glob_definition_hunt, edit_symbol_token), or the
#     class carried from the original record for followup.
#   - detail = matcher source name (grep_extension) for nudge, path/pattern
#     for observe, Serena tool short name for followup.
# This keeps $5 = class consistently across all kinds, so the followthrough
# correlator and the rolling-window report can join on a single field.
if [ "${SERENA_TELEMETRY:-1}" != "0" ]; then
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
    printf '%s\t%s\t%s\tnudge\t%s\tgrep_extension\n' "${_TS}" "${_TOKEN}" "${_TURN}" "${_CLASS}" >>"${_TELEM}" 2>/dev/null || true
fi

exit 0

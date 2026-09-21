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
# THE POPULATION MOVED (#124). This hook required tool_name == "Grep", while
# agents increasingly search with grep/rg through the BASH tool — sessions are
# instructed to work that way. Measured 2026-09-19: 5 telemetry records, all
# "observe", not one "nudge", across 38 days.
#
# That is why #124's kill criterion could not be applied. Its secondary signal
# says to delete the broadened matcher as dead code if it fires ~0 times — and
# acting on that would have deleted a demonstrably working matcher on the
# strength of a number measuring TOOL ROUTING, not matcher quality. Zero
# firings is fully explained by a population that never reaches the hook.
# Repairing the channel is the precondition for that evaluation, not a
# substitute for it.
case "${_TOOL_NAME}" in
    Grep|Bash) ;;
    *) exit 0 ;;
esac

# Check serena availability from cached registry
_CACHE="${HOME}/.claude/.skill-registry-cache.json"
[ -f "${_CACHE}" ] || exit 0
_SERENA="$(jq -r '.context_capabilities.serena // false' "${_CACHE}" 2>/dev/null)" || true
[ "${_SERENA}" = "true" ] || exit 0

# Pattern extraction is the ONLY tool-specific part; the classifier below is
# shared, which is why this extends rather than duplicates.
#
# The Bash extractor is deliberately narrow and says so. This repo has been
# bitten repeatedly by shell-syntax enumerations that looked complete, and a
# nudge is advisory — so the safe failure is SILENCE, never a wrong nudge.
# Recognised: a command whose first word is grep/rg/ag (after an optional
# `env`). A quoted run wins, because naive word-splitting truncates it and the
# classifier needs whole phrases: `grep -rE 'class Foo' .` splits to `class`,
# which matches no definition prefix (they carry a trailing space) and silently
# loses the nudge. Pipelines into grep, a pattern from a variable, and xargs
# all yield nothing and simply do not fire.
_PATTERN=""
if [ "${_TOOL_NAME}" = "Grep" ]; then
    _PATTERN="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.pattern // empty' 2>/dev/null)" || true
else
    _CMD="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.command // empty' 2>/dev/null)" || true
    # Cheap reject first: this hook now sees EVERY Bash call, so a non-search
    # must cost almost nothing.
    case "${_CMD}" in
        grep\ *|rg\ *|ag\ *|env\ grep\ *|env\ rg\ *|env\ ag\ *)
            _Q="${_CMD#*[\'\"]}"
            if [ "${_Q}" != "${_CMD}" ]; then
                _PATTERN="${_Q%%[\'\"]*}"
            fi
            if [ -z "${_PATTERN}" ]; then
                # shellcheck disable=SC2086
                set -- ${_CMD}
                [ "$1" = "env" ] && shift
                shift
                while [ "$#" -gt 0 ]; do
                    case "$1" in
                        -e|-f|-m|--max-count|--include|--exclude|--glob|-g)
                            shift; shift 2>/dev/null || break ;;
                        -*) shift ;;
                        *) _PATTERN="$1"; break ;;
                    esac
                done
            fi
            ;;
    esac
fi
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
    # stays in env; only the hash is persisted. Fail-open: if neither sha256sum
    # (Linux) nor shasum (macOS default) is available, fall back to the raw token.
    _TOKEN_RAW="${CLAUDE_SESSION_TOKEN:-unknown}"
    if [ "${_TOKEN_RAW}" = "unknown" ]; then
        _TOKEN="${_TOKEN_RAW}"
    elif command -v sha256sum >/dev/null 2>&1; then
        _TOKEN="$(printf '%s' "${_TOKEN_RAW}" | sha256sum 2>/dev/null | cut -c1-12)"
        [ -n "${_TOKEN}" ] || _TOKEN="${_TOKEN_RAW}"
    elif command -v shasum >/dev/null 2>&1; then
        _TOKEN="$(printf '%s' "${_TOKEN_RAW}" | shasum -a 256 2>/dev/null | cut -c1-12)"
        [ -n "${_TOKEN}" ] || _TOKEN="${_TOKEN_RAW}"
    else
        _TOKEN="${_TOKEN_RAW}"
    fi
    _TURN="${CLAUDE_TURN_ID:-0}"
    printf '%s\t%s\t%s\tnudge\t%s\tgrep_extension\n' "${_TS}" "${_TOKEN}" "${_TURN}" "${_CLASS}" >>"${_TELEM}" 2>/dev/null || true
fi

exit 0

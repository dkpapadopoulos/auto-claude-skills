#!/bin/bash
# Serena follow-through correlator — PostToolUse on ^mcp__serena__.
# When a Serena MCP tool returns successfully, scans recent telemetry lines from
# the same session and appends a `followup` record for each unmarked nudge or
# observation within 3 turns. Used to compute follow-through % per matcher class.
# Telemetry schema: see hooks/serena-nudge.sh (canonical reference). $5 is the
# class field — the join key across nudge / observe / followup records.
# Bash 3.2 compatible. Fail-open. jq required; no-op when unavailable.
trap 'exit 0' ERR

[ "${SERENA_TELEMETRY:-1}" = "0" ] && exit 0

_INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

_TOOL="$(printf '%s' "${_INPUT}" | jq -r '.tool_name // empty' 2>/dev/null)"
case "${_TOOL}" in
    mcp__serena__*) ;;
    *) exit 0 ;;
esac

# Skip on errored tool result.
_ERR="$(printf '%s' "${_INPUT}" | jq -r '.tool_response.is_error // .tool_response.error // empty' 2>/dev/null)"
case "${_ERR}" in
    ""|null|false) ;;
    *) exit 0 ;;
esac

_TELEM="${HOME}/.claude/.serena-nudge-telemetry"
[ -f "${_TELEM}" ] || exit 0

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
_TS="$(date +%s 2>/dev/null || echo 0)"
_SERENA_TOOL_SHORT="${_TOOL#mcp__serena__}"

# Filter telemetry by this session's token first, then take the most recent
# 200 lines. Filtering before tail prevents concurrent sessions from evicting
# our own nudges out of the last-200 window in a multi-session environment.
_RECENT="$(awk -F'\t' -v tok="${_TOKEN}" '$2==tok' "${_TELEM}" 2>/dev/null | tail -200)"
[ -n "${_RECENT}" ] || exit 0

# Build the (turn, matcher) set of already-correlated entries. Use tab as the
# composite key delimiter — matcher class names cannot contain tabs (TSV
# invariant), so collisions are impossible by construction.
_SEEN="$(printf '%s\n' "${_RECENT}" | awk -F'\t' '$4=="followup"{print $3"\t"$5}')"

# Find candidate (turn, matcher) pairs to correlate now.
# Use a temp file to capture pairs across the awk subshell boundary.
_TMP="$(mktemp 2>/dev/null || printf '%s/serena-ft-%s-%s' "${TMPDIR:-/tmp}" "$$" "${RANDOM}")"
printf '%s\n' "${_RECENT}" | awk -F'\t' \
    -v cur="${_TURN}" \
    -v seen="${_SEEN}" \
    'BEGIN { n = split(seen, arr, "\n"); for (i=1;i<=n;i++) seen_set[arr[i]] = 1 }
     ($4=="nudge" || $4=="observe") {
         delta = cur - $3;
         if (delta < 0 || delta > 3) next;
         key = $3 "\t" $5;
         if (key in seen_set) next;
         print $3 "\t" $5;
         seen_set[key] = 1;
     }' >"${_TMP}" 2>/dev/null

while IFS=$'\t' read -r turn matcher; do
    [ -n "${turn}" ] && [ -n "${matcher}" ] || continue
    printf '%s\t%s\t%s\tfollowup\t%s\t%s\n' "${_TS}" "${_TOKEN}" "${turn}" "${matcher}" "${_SERENA_TOOL_SHORT}" >>"${_TELEM}" 2>/dev/null || true
done <"${_TMP}"

rm -f "${_TMP}"
exit 0

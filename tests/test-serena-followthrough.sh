#!/usr/bin/env bash
# test-serena-followthrough.sh — Verify hooks/serena-followthrough.sh appends a
# `followup` line when a Serena MCP tool runs within 3 turns of an unmarked nudge
# or observation in the same session.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/serena-followthrough.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env
TELEM="${HOME}/.claude/.serena-nudge-telemetry"
mkdir -p "${HOME}/.claude"

_invoke_followthrough() {
    local tool="$1" turn="$2" token="${3:-tok-A}"
    local input
    input="$(jq -n --arg t "${tool}" '{tool_name:$t, tool_input:{}, tool_response:{ok:true}}')"
    printf '%s' "${input}" | env CLAUDE_SESSION_TOKEN="${token}" CLAUDE_TURN_ID="${turn}" bash "${HOOK}" 2>/dev/null
}

# The hooks now hash CLAUDE_SESSION_TOKEN to a 12-char hex prefix before
# writing to telemetry. Seeded fixture rows must use the hashed value so
# followthrough's `$2==tok` filter (which sees the hashed _TOKEN) matches.
_hash_tok() {
    if command -v sha256sum >/dev/null 2>&1; then
        printf '%s' "$1" | sha256sum | cut -c1-12
    else
        printf '%s' "$1"
    fi
}
H_A="$(_hash_tok tok-A)"
H_B="$(_hash_tok tok-B)"
H_C="$(_hash_tok tok-C)"
H_E="$(_hash_tok tok-E)"
H_F="$(_hash_tok tok-F)"
H_OUR="$(_hash_tok tok-OUR)"
H_NOISY="$(_hash_tok tok-NOISY)"

# Seed: a nudge at turn 5 in session tok-A.
printf '1700000000\t%s\t5\tnudge\tword_boundary\tgrep_extension\n' "${H_A}" >>"${TELEM}"

# Serena call at turn 6 — within 3 turns → should produce a followup line.
_invoke_followthrough mcp__serena__find_symbol 6 tok-A >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_contains "Serena call within 3 turns appends followup" "followup" "${LAST}"
assert_contains "followup carries original class word_boundary" "word_boundary" "${LAST}"
assert_contains "followup names the serena tool find_symbol" "find_symbol" "${LAST}"

# Already-correlated nudge → no double-followup on second Serena call.
_LINES_BEFORE="$(wc -l <"${TELEM}" | tr -d ' ')"
_invoke_followthrough mcp__serena__get_symbols_overview 6 tok-A >/dev/null
_LINES_AFTER="$(wc -l <"${TELEM}" | tr -d ' ')"
assert_equals "no double-followup once nudge correlated" "${_LINES_BEFORE}" "${_LINES_AFTER}"

# Far-apart Serena call (turn 5 nudge + turn 12 Serena call) → no followup.
rm -f "${TELEM}"
printf '1700000000\t%s\t5\tnudge\tword_boundary\tgrep_extension\n' "${H_B}" >>"${TELEM}"
_invoke_followthrough mcp__serena__find_symbol 12 tok-B >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_not_contains "no followup beyond 3 turns" "followup" "${LAST}"

# Different session token → no followup.
rm -f "${TELEM}"
printf '1700000000\t%s\t5\tnudge\tword_boundary\tgrep_extension\n' "${H_C}" >>"${TELEM}"
_invoke_followthrough mcp__serena__find_symbol 6 tok-D >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_not_contains "no followup across sessions" "followup" "${LAST}"

# Observation — also correlates to followup.
rm -f "${TELEM}"
printf '1700000000\t%s\t10\tobserve\tread_large_source\tsrc/big.ts\n' "${H_E}" >>"${TELEM}"
_invoke_followthrough mcp__serena__get_symbols_overview 11 tok-E >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_contains "observation correlates to followup" "followup" "${LAST}"
assert_contains "observation followup carries read_large_source" "read_large_source" "${LAST}"

# Multi-session safety: a busy concurrent session writing 250 lines must not
# evict our own session's nudge out of the lookup window.
rm -f "${TELEM}"
printf '1700000000\t%s\t5\tnudge\tword_boundary\tgrep_extension\n' "${H_OUR}" >>"${TELEM}"
i=1
while [ "${i}" -le 250 ]; do
    printf '1700000001\t%s\t%d\tobserve\tread_large_source\tsrc/x.ts\n' "${H_NOISY}" "${i}" >>"${TELEM}"
    i=$((i+1))
done
_invoke_followthrough mcp__serena__find_symbol 6 tok-OUR >/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_contains "concurrent session noise does not evict our nudge from the window" "followup" "${LAST}"
assert_contains "followup carries our session token (hashed)" "${H_OUR}" "${LAST}"

# Errored Serena tool result → no followup.
rm -f "${TELEM}"
printf '1700000000\t%s\t5\tnudge\tword_boundary\tgrep_extension\n' "${H_F}" >>"${TELEM}"
err_input="$(jq -n '{tool_name:"mcp__serena__find_symbol", tool_input:{}, tool_response:{is_error:true}}')"
printf '%s' "${err_input}" | env CLAUDE_SESSION_TOKEN=tok-F CLAUDE_TURN_ID=6 bash "${HOOK}" 2>/dev/null
LAST="$(tail -1 "${TELEM}")"
assert_not_contains "no followup on errored tool result" "followup" "${LAST}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0

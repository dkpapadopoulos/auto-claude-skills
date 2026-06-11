#!/usr/bin/env bash
# test-session-token-race.sh — Regression: token resolution MUST be payload-first.
#
# Root cause (issue #51): ~/.claude/.skill-session-token is a shared singleton
# with last-writer-wins semantics. Concurrent sessions overwrite it; any hook
# that resolves "my token" by reading it back evaluates ANOTHER session's
# composition state. Observed live: the push gate denied a legitimate push
# because the singleton pointed at a different conversation's incomplete chain.
#
# Fix under test: hooks derive the token from their own stdin payload's
# transcript_path (hooks/lib/session-token.sh); the singleton is fallback only.
#
# Bash 3.2 compatible. Sources test-helpers.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${PROJECT_ROOT}/hooks/lib/session-token.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
ACTIVATION="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
COMPLETION="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-session-token-race.sh ==="

# Payload-first resolution is jq-gated. Honor the repo's "jq optional at
# runtime" contract: without jq the hooks fall back to the singleton, so the
# race scenarios cannot be exercised — skip rather than fail.
if ! command -v jq >/dev/null 2>&1; then
    _record_pass "jq unavailable — payload-first resolution is jq-gated; skipping"
    print_summary
    exit 0
fi

# ---------------------------------------------------------------------------
# U1–U4: lib unit checks
# ---------------------------------------------------------------------------
echo "--- U: session-token.sh unit checks ---"
setup_test_env
mkdir -p "${HOME}/.claude"
if [ -f "${LIB}" ]; then
    # shellcheck source=../hooks/lib/session-token.sh
    . "${LIB}"
    U1="$(session_token_from_transcript "/tmp/proj/conv-ALPHA.jsonl")"
    assert_equals "U1: session_token_from_transcript format" "session-conv-ALPHA" "${U1}"
    U2="$(session_token_from_transcript "")"
    assert_equals "U2: empty transcript -> empty token" "" "${U2}"
    printf '%s' "singleton-token" > "${HOME}/.claude/.skill-session-token"
    U3="$(resolve_session_token '{"transcript_path":"/tmp/proj/conv-ALPHA.jsonl"}')"
    assert_equals "U3: payload beats singleton" "session-conv-ALPHA" "${U3}"
    U4="$(resolve_session_token '{"session_id":"no-transcript-here"}')"
    assert_equals "U4: no transcript_path -> singleton fallback" "singleton-token" "${U4}"
else
    _record_fail "U1: hooks/lib/session-token.sh exists" "missing ${LIB}"
fi
teardown_test_env

print_summary

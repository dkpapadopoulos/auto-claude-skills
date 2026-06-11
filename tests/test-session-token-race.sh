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
    # Dash-leading basenames must not be parsed as basename options (BSD errors,
    # GNU prints help text) — `--` pins identical fail-safe output on both.
    U5="$(session_token_from_transcript "-A.jsonl")"
    assert_equals "U5: dash-leading transcript basename handled via --" "session--A" "${U5}"
else
    _record_fail "U1: hooks/lib/session-token.sh exists" "missing ${LIB}"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# G1–G3: openspec-guard keys to the payload token, not the singleton
# ---------------------------------------------------------------------------
echo "--- G: push gate vs foreign singleton ---"

# write_comp_state <token> <completed-json-array>
write_comp_state() {
    jq -n --argjson done "$2" '{
        chain: ["requesting-code-review","verification-before-completion"],
        completed: $done, current_index: 0
    }' > "${HOME}/.claude/.skill-composition-state-$1"
}

# run_guard_with <payload-json> — echoes guard stdout
run_guard_with() {
    printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null
}

PUSH_A='{"transcript_path":"/tmp/proj/conv-A.jsonl","tool_input":{"command":"git push origin main"}}'

# G1: A incomplete, singleton points at B (complete) -> must DENY from A state
setup_test_env
mkdir -p "${HOME}/.claude"
write_comp_state "session-conv-A" '[]'
write_comp_state "session-conv-B" '["requesting-code-review","verification-before-completion"]'
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
G1_OUT="$(run_guard_with "${PUSH_A}")"
assert_contains "G1: guard denies from OWN (payload) state despite foreign singleton" '"permissionDecision": "deny"' "${G1_OUT}"
teardown_test_env

# G2: A complete, singleton points at B (incomplete) -> must ALLOW (no deny)
setup_test_env
mkdir -p "${HOME}/.claude"
write_comp_state "session-conv-A" '["requesting-code-review","verification-before-completion"]'
write_comp_state "session-conv-B" '[]'
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
G2_OUT="$(run_guard_with "${PUSH_A}")"
if printf '%s' "${G2_OUT}" | grep -q '"permissionDecision": "deny"'; then
    _record_fail "G2: guard allows when OWN chain complete (foreign singleton incomplete)" "got deny: ${G2_OUT}"
else
    _record_pass "G2: guard allows when OWN chain complete (foreign singleton incomplete)"
fi
teardown_test_env

# G3: payload without transcript_path -> singleton fallback still gates
setup_test_env
mkdir -p "${HOME}/.claude"
write_comp_state "session-conv-B" '[]'
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
G3_OUT="$(run_guard_with '{"tool_input":{"command":"git push origin main"}}')"
assert_contains "G3: no transcript_path -> singleton fallback still denies" '"permissionDecision": "deny"' "${G3_OUT}"
teardown_test_env

# ---------------------------------------------------------------------------
# A1–A2: activation hook keys state to payload token and re-stamps singleton
# ---------------------------------------------------------------------------
echo "--- A: activation hook payload keying + re-stamp ---"
setup_test_env
mkdir -p "${HOME}/.claude"
# Registry must exist for routing; the repo fallback registry is sufficient.
cp "${PROJECT_ROOT}/config/fallback-registry.json" "${HOME}/.claude/.skill-registry-cache.json"
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
printf '%s' '{"transcript_path":"/tmp/proj/conv-A.jsonl","prompt":"let us brainstorm a new feature design"}' | \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${TEST_TMPDIR}" /bin/bash "${ACTIVATION}" >/dev/null 2>&1 || true
A1_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
assert_equals "A1: singleton re-stamped to payload-derived token" "session-conv-A" "${A1_TOKEN}"
if [ -f "${HOME}/.claude/.skill-prompt-count-session-conv-A" ]; then
    _record_pass "A2: per-prompt state keyed to payload token, not foreign singleton"
else
    _record_fail "A2: per-prompt state keyed to payload token, not foreign singleton" \
        "$(ls "${HOME}/.claude" 2>/dev/null | tr '\n' ' ')"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# C1: completion hook advances OWN state despite foreign singleton
# ---------------------------------------------------------------------------
echo "--- C: completion hook payload keying ---"
setup_test_env
mkdir -p "${HOME}/.claude"
write_comp_state "session-conv-A" '[]'
write_comp_state "session-conv-B" '[]'
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
printf '%s' '{"transcript_path":"/tmp/proj/conv-A.jsonl","tool_input":{"skill":"superpowers:requesting-code-review"},"tool_response":{"content":"ok"}}' | \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${COMPLETION}" >/dev/null 2>&1 || true
C1_A="$(jq -r '.completed | index("requesting-code-review") != null' "${HOME}/.claude/.skill-composition-state-session-conv-A" 2>/dev/null)"
C1_B="$(jq -r '.completed | index("requesting-code-review") != null' "${HOME}/.claude/.skill-composition-state-session-conv-B" 2>/dev/null)"
assert_equals "C1: own (payload) state advanced" "true" "${C1_A}"
assert_equals "C1: foreign (singleton) state untouched" "false" "${C1_B}"
teardown_test_env

# ---------------------------------------------------------------------------
# S1: compact-recovery resets the counter for the PAYLOAD token
# ---------------------------------------------------------------------------
echo "--- S: compact-recovery payload keying ---"
setup_test_env
mkdir -p "${HOME}/.claude"
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
printf '%s' '{"transcript_path":"/tmp/proj/conv-A.jsonl"}' | \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${PROJECT_ROOT}/hooks/compact-recovery-hook.sh" >/dev/null 2>&1 || true
if [ -f "${HOME}/.claude/.skill-prompt-count-session-conv-A" ]; then
    _record_pass "S1: compact-recovery keyed to payload token"
else
    _record_fail "S1: compact-recovery keyed to payload token" \
        "$(ls -a "${HOME}/.claude" 2>/dev/null | tr '\n' ' ')"
fi
teardown_test_env

# ---------------------------------------------------------------------------
# ST1: consolidation-stop writes the learn baseline under the PAYLOAD token
# ---------------------------------------------------------------------------
echo "--- ST: consolidation-stop payload keying ---"
setup_test_env
mkdir -p "${HOME}/.claude"
# shellcheck source=../hooks/lib/openspec-state.sh
. "${PROJECT_ROOT}/hooks/lib/openspec-state.sh"
# Openspec state with hypotheses lives under A (the payload token); the
# singleton points at B. The baseline write must key off A.
ST_HYPS='[{"id":"H1","description":"x","metric":"m","baseline":null,"target":null,"window":null}]'
openspec_state_set_hypotheses "session-conv-A" "shipped-feature" "${ST_HYPS}"
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
ST_PROJ="${TEST_TMPDIR}/repo"
mkdir -p "${ST_PROJ}/openspec/changes/archive/shipped-feature"
( cd "${ST_PROJ}" && git init -q && git commit --allow-empty -q -m init 2>/dev/null
  _proj_hash="$(printf '%s' "$(git rev-parse --show-toplevel)" | shasum | cut -d' ' -f1)"
  touch "${HOME}/.claude/.context-stack-consolidated-${_proj_hash}"
  printf '%s' '{"transcript_path":"/tmp/proj/conv-A.jsonl"}' | \
      CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${PROJECT_ROOT}/hooks/consolidation-stop.sh" >/dev/null 2>&1 || true )
if [ -f "${HOME}/.claude/.skill-learn-baselines/shipped-feature.json" ]; then
    _record_pass "ST1: consolidation-stop keyed to payload token"
else
    _record_fail "ST1: consolidation-stop keyed to payload token" \
        "$(ls -a "${HOME}/.claude" 2>/dev/null | tr '\n' ' ')"
fi
teardown_test_env

print_summary

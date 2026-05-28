#!/usr/bin/env bash
# test-context-economy.sh — Tests for scripts/setup-managed-settings.sh
#
# Spec: openspec/changes/context-economy-defaults/specs/context-economy/spec.md
# Scenarios covered (Tasks A/B/C/D):
#   Task A — Truncation defaults
#     A1. First-time /setup writes both keys
#     A2. Re-running /setup is idempotent
#     A3. User-customized value preserved without --force
#     A4. Restart notice emitted
#   Task B — Observability preset (opt-in)
#     B1. Opt-in flag enables observability
#     B2. Bare /setup leaves observability untouched
#   Task C — Context-hygiene preset (opt-in)
#     C1. Template emitted when absent
#     C2. Existing .claudeignore preserved
#     C3. Subdir launch warning fires
#   Task D — Model-routing preset (opt-in, default-OFF)
#     D1. Opt-in flag writes both keys
#     D2. Bare /setup does NOT enable routing
#
# Bash 3.2 compatible. Requires jq for assertions (consistent with project).

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SETUP_SCRIPT="${PROJECT_ROOT}/scripts/setup-managed-settings.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-context-economy.sh ==="

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Read a value out of the user's settings.json `env` block.
# Args: $1 = key
get_env_value() {
    local key="$1"
    jq -r --arg k "$key" '.env[$k] // empty' "${HOME}/.claude/settings.json" 2>/dev/null
}

# Read whole settings.json file into stdout.
dump_settings() {
    cat "${HOME}/.claude/settings.json" 2>/dev/null
}

# Run the setup script with given args; capture stdout into $LAST_STDOUT.
# Also capture exit code into $LAST_RC so callers can assert on it.
LAST_STDOUT=""
LAST_RC=0
run_setup() {
    LAST_STDOUT="$(bash "${SETUP_SCRIPT}" "$@" 2>&1)"
    LAST_RC=$?
}

# Tweak an A1 helper assertion: A1 must also assert rc=0.

# ---------------------------------------------------------------------------
# A1 — First-time /setup writes both truncation keys
# ---------------------------------------------------------------------------
echo "--- A1: First-time /setup writes both truncation keys ---"
setup_test_env
# No existing settings.json; the script must create it.
run_setup

A1_BASH="$(get_env_value BASH_MAX_OUTPUT_LENGTH)"
A1_MCP="$(get_env_value MAX_MCP_OUTPUT_TOKENS)"
assert_equals "A1: BASH_MAX_OUTPUT_LENGTH=20000" "20000" "${A1_BASH}"
assert_equals "A1: MAX_MCP_OUTPUT_TOKENS=10000" "10000" "${A1_MCP}"
assert_json_valid "A1: settings.json is valid JSON" "${HOME}/.claude/settings.json"
assert_equals "A1: setup exited successfully (rc=0)" "0" "${LAST_RC}"
teardown_test_env

# ---------------------------------------------------------------------------
# A2 — Re-running /setup is idempotent (byte-equivalent)
# ---------------------------------------------------------------------------
echo "--- A2: Re-running /setup is idempotent ---"
setup_test_env
run_setup
FIRST_SNAPSHOT="$(dump_settings)"
run_setup
SECOND_SNAPSHOT="$(dump_settings)"
assert_equals "A2: second run produces byte-equivalent settings.json" \
    "${FIRST_SNAPSHOT}" "${SECOND_SNAPSHOT}"
teardown_test_env

# ---------------------------------------------------------------------------
# A3 — User-customized value preserved without --force
# ---------------------------------------------------------------------------
echo "--- A3: User-customized value preserved without --force ---"
setup_test_env
mkdir -p "${HOME}/.claude"
# Pre-seed a user-set BASH_MAX_OUTPUT_LENGTH=50000.
echo '{"env":{"BASH_MAX_OUTPUT_LENGTH":"50000"}}' > "${HOME}/.claude/settings.json"
run_setup
A3_BASH="$(get_env_value BASH_MAX_OUTPUT_LENGTH)"
A3_MCP="$(get_env_value MAX_MCP_OUTPUT_TOKENS)"
assert_equals "A3: user-set BASH_MAX_OUTPUT_LENGTH preserved (50000)" "50000" "${A3_BASH}"
assert_equals "A3: missing MAX_MCP_OUTPUT_TOKENS now defaulted (10000)" "10000" "${A3_MCP}"
assert_contains "A3: stdout emits preservation notice (review I1)" \
    "preserved user value for BASH_MAX_OUTPUT_LENGTH" "${LAST_STDOUT}"
teardown_test_env

# ---------------------------------------------------------------------------
# A5 — Malformed existing settings.json: refuse to overwrite (review C1/#1)
# ---------------------------------------------------------------------------
echo "--- A5: malformed settings.json is preserved, script exits non-zero ---"
setup_test_env
mkdir -p "${HOME}/.claude"
GARBAGE='this is not json {{{ malformed }}}'
printf '%s' "${GARBAGE}" > "${HOME}/.claude/settings.json"
run_setup
A5_AFTER="$(cat "${HOME}/.claude/settings.json")"
# script MUST NOT clobber the file
assert_equals "A5: malformed settings preserved verbatim" "${GARBAGE}" "${A5_AFTER}"
# script MUST exit non-zero
case "${LAST_RC}" in
    0) _record_fail "A5: setup exited non-zero on malformed JSON" "got rc=0" ;;
    *) _record_pass "A5: setup exited non-zero on malformed JSON" ;;
esac
# script MUST NOT print the restart notice
assert_not_contains "A5: no restart notice when refusing to write" \
    "restart Claude to apply" "${LAST_STDOUT}"
teardown_test_env

# ---------------------------------------------------------------------------
# A6 — Write failure to read-only file: no restart notice, exit non-zero (review C2/#2)
# ---------------------------------------------------------------------------
echo "--- A6: read-only settings.json reports failure, no restart notice ---"
setup_test_env
mkdir -p "${HOME}/.claude"
echo '{}' > "${HOME}/.claude/settings.json"
chmod 444 "${HOME}/.claude/settings.json"
run_setup
case "${LAST_RC}" in
    0) _record_fail "A6: setup exited non-zero when write blocked" "got rc=0" ;;
    *) _record_pass "A6: setup exited non-zero when write blocked" ;;
esac
assert_not_contains "A6: no restart notice when writes failed" \
    "restart Claude to apply" "${LAST_STDOUT}"
chmod 644 "${HOME}/.claude/settings.json" 2>/dev/null || true
teardown_test_env

# ---------------------------------------------------------------------------
# A7 — Non-object .env type: refuse with clear error (review #6)
# ---------------------------------------------------------------------------
echo "--- A7: non-object .env refuses cleanly ---"
setup_test_env
mkdir -p "${HOME}/.claude"
echo '{"env":"not-an-object"}' > "${HOME}/.claude/settings.json"
BEFORE="$(cat "${HOME}/.claude/settings.json")"
run_setup
AFTER="$(cat "${HOME}/.claude/settings.json")"
assert_equals "A7: settings file unchanged when .env is non-object" "${BEFORE}" "${AFTER}"
case "${LAST_RC}" in
    0) _record_fail "A7: setup exited non-zero on bad .env type" "got rc=0" ;;
    *) _record_pass "A7: setup exited non-zero on bad .env type" ;;
esac
assert_contains "A7: stderr/stdout mentions the .env type problem" \
    ".env" "${LAST_STDOUT}"
teardown_test_env

# ---------------------------------------------------------------------------
# A8 — Explicitly empty-string user value preserved via has() check (review I2)
# ---------------------------------------------------------------------------
echo "--- A8: explicit empty-string user value is preserved ---"
setup_test_env
mkdir -p "${HOME}/.claude"
echo '{"env":{"BASH_MAX_OUTPUT_LENGTH":""}}' > "${HOME}/.claude/settings.json"
run_setup
A8_BASH="$(get_env_value BASH_MAX_OUTPUT_LENGTH)"
# After fix: empty string user value preserved (not overwritten)
assert_equals "A8: explicit empty BASH_MAX_OUTPUT_LENGTH preserved" "" "${A8_BASH}"
# MAX_MCP_OUTPUT_TOKENS is absent → gets the default.
A8_MCP="$(get_env_value MAX_MCP_OUTPUT_TOKENS)"
assert_equals "A8: absent MAX_MCP_OUTPUT_TOKENS defaulted" "10000" "${A8_MCP}"
teardown_test_env

# ---------------------------------------------------------------------------
# A4 — Restart notice emitted as final stdout
# ---------------------------------------------------------------------------
echo "--- A4: Restart notice emitted ---"
setup_test_env
run_setup
assert_contains "A4: stdout mentions 'restart Claude to apply'" \
    "restart Claude to apply" "${LAST_STDOUT}"
teardown_test_env

# ---------------------------------------------------------------------------
# B1 — Opt-in --observability flag enables observability
# ---------------------------------------------------------------------------
echo "--- B1: Opt-in flag enables observability ---"
setup_test_env
run_setup --observability
B1_TELEM="$(get_env_value CLAUDE_CODE_ENABLE_TELEMETRY)"
B1_MX="$(get_env_value OTEL_METRICS_EXPORTER)"
B1_LX="$(get_env_value OTEL_LOGS_EXPORTER)"
assert_equals "B1: CLAUDE_CODE_ENABLE_TELEMETRY=1" "1" "${B1_TELEM}"
assert_equals "B1: OTEL_METRICS_EXPORTER=otlp" "otlp" "${B1_MX}"
assert_equals "B1: OTEL_LOGS_EXPORTER=otlp" "otlp" "${B1_LX}"
teardown_test_env

# ---------------------------------------------------------------------------
# B2 — Bare /setup leaves observability untouched
# ---------------------------------------------------------------------------
echo "--- B2: Bare /setup does NOT enable observability ---"
setup_test_env
run_setup
B2_TELEM="$(get_env_value CLAUDE_CODE_ENABLE_TELEMETRY)"
B2_MX="$(get_env_value OTEL_METRICS_EXPORTER)"
assert_equals "B2: CLAUDE_CODE_ENABLE_TELEMETRY absent" "" "${B2_TELEM}"
assert_equals "B2: OTEL_METRICS_EXPORTER absent" "" "${B2_MX}"
teardown_test_env

# ---------------------------------------------------------------------------
# C1 — Template emitted when .claudeignore absent
# ---------------------------------------------------------------------------
echo "--- C1: claudeignore template emitted when absent ---"
setup_test_env
TEST_REPO="${TEST_TMPDIR}/repo"
mkdir -p "${TEST_REPO}"
LAST_STDOUT="$(cd "${TEST_REPO}" && bash "${SETUP_SCRIPT}" --context-hygiene 2>&1)"
LAST_RC=$?
assert_file_exists "C1: .claudeignore exists at repo root" "${TEST_REPO}/.claudeignore"
C1_BODY="$(cat "${TEST_REPO}/.claudeignore" 2>/dev/null)"
assert_contains "C1: claudeignore contains node_modules/" "node_modules/" "${C1_BODY}"
assert_contains "C1: claudeignore contains dist/" "dist/" "${C1_BODY}"
assert_contains "C1: claudeignore contains security disclaimer" \
    "not a security boundary" "${C1_BODY}"
teardown_test_env

# ---------------------------------------------------------------------------
# C2 — Existing .claudeignore preserved
# ---------------------------------------------------------------------------
echo "--- C2: existing .claudeignore preserved ---"
setup_test_env
TEST_REPO="${TEST_TMPDIR}/repo"
mkdir -p "${TEST_REPO}"
echo "# user-custom" > "${TEST_REPO}/.claudeignore"
LAST_STDOUT="$(cd "${TEST_REPO}" && bash "${SETUP_SCRIPT}" --context-hygiene 2>&1)"
LAST_RC=$?
C2_BODY="$(cat "${TEST_REPO}/.claudeignore" 2>/dev/null)"
assert_equals "C2: existing .claudeignore unmodified" "# user-custom" "${C2_BODY}"
assert_contains "C2: stdout emits preservation notice (review I1)" \
    "preserved existing .claudeignore" "${LAST_STDOUT}"
teardown_test_env

# ---------------------------------------------------------------------------
# C3 — Subdir launch warning fires when above package manifest dirs
# ---------------------------------------------------------------------------
echo "--- C3: subdir warning fires from above manifest dirs ---"
setup_test_env
TEST_REPO="${TEST_TMPDIR}/repo"
mkdir -p "${TEST_REPO}/frontend" "${TEST_REPO}/backend"
echo '{}' > "${TEST_REPO}/frontend/package.json"
echo '[tool.poetry]' > "${TEST_REPO}/backend/pyproject.toml"
DETECT_SCRIPT="${PROJECT_ROOT}/scripts/detect-monorepo-subdir.sh"
C3_OUT="$(cd "${TEST_REPO}" && bash "${DETECT_SCRIPT}" 2>&1)"
assert_contains "C3: warning mentions monorepo subdir detection" \
    "Monorepo subdirectory detected" "${C3_OUT}"
assert_contains "C3: warning recommends cd into subdir" \
    "cd " "${C3_OUT}"
# Inside a manifest dir — should be silent.
C3_QUIET="$(cd "${TEST_REPO}/frontend" && bash "${DETECT_SCRIPT}" 2>&1)"
assert_equals "C3: silent when launched from inside manifest dir" "" "${C3_QUIET}"
# Suppress via env var.
C3_SUPPRESSED="$(cd "${TEST_REPO}" && ACSM_QUIET_SUBDIR=1 bash "${DETECT_SCRIPT}" 2>&1)"
assert_equals "C3: ACSM_QUIET_SUBDIR=1 silences the hint" "" "${C3_SUPPRESSED}"
teardown_test_env

# ---------------------------------------------------------------------------
# C3.deepest — Spec wording "deepest relevant subdirectory" (review C3)
# ---------------------------------------------------------------------------
echo "--- C3.deepest: deepest manifest wins, not lex-first ---"
setup_test_env
TEST_REPO="${TEST_TMPDIR}/repo"
# Two manifests at different depths. lex-first under "shallow/" alphabetically
# precedes "deeper/", so a head-1 implementation picks the shallow one.
mkdir -p "${TEST_REPO}/shallow"
mkdir -p "${TEST_REPO}/deeper/sub"
echo '{}' > "${TEST_REPO}/shallow/package.json"
echo '{}' > "${TEST_REPO}/deeper/sub/package.json"
DETECT_SCRIPT="${PROJECT_ROOT}/scripts/detect-monorepo-subdir.sh"
C3D_OUT="$(cd "${TEST_REPO}" && bash "${DETECT_SCRIPT}" 2>&1)"
assert_contains "C3.deepest: recommends cd into deeper/sub" \
    "deeper/sub" "${C3D_OUT}"
assert_not_contains "C3.deepest: does NOT recommend the shallow lex-first match" \
    "cd shallow" "${C3D_OUT}"
teardown_test_env

# ---------------------------------------------------------------------------
# D1 — Opt-in --model-routing flag writes both keys
# ---------------------------------------------------------------------------
echo "--- D1: Opt-in flag writes routing keys ---"
setup_test_env
run_setup --model-routing
D1_MODEL="$(get_env_value CLAUDE_CODE_SUBAGENT_MODEL)"
D1_EFFORT="$(get_env_value CLAUDE_CODE_EFFORT_LEVEL)"
assert_equals "D1: CLAUDE_CODE_SUBAGENT_MODEL=haiku" "haiku" "${D1_MODEL}"
assert_equals "D1: CLAUDE_CODE_EFFORT_LEVEL=medium" "medium" "${D1_EFFORT}"
assert_contains "D1: stdout warns about overriding pinned models" \
    "overrides" "${LAST_STDOUT}"
teardown_test_env

# ---------------------------------------------------------------------------
# D2 — Bare /setup does NOT enable routing
# ---------------------------------------------------------------------------
echo "--- D2: Bare /setup does NOT enable routing ---"
setup_test_env
run_setup
D2_MODEL="$(get_env_value CLAUDE_CODE_SUBAGENT_MODEL)"
D2_EFFORT="$(get_env_value CLAUDE_CODE_EFFORT_LEVEL)"
assert_equals "D2: CLAUDE_CODE_SUBAGENT_MODEL absent" "" "${D2_MODEL}"
assert_equals "D2: CLAUDE_CODE_EFFORT_LEVEL absent" "" "${D2_EFFORT}"
teardown_test_env

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary

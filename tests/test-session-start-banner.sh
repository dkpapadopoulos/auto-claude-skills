#!/usr/bin/env bash
# test-session-start-banner.sh — Verify the SessionStart banner names the v1.3.0
# Serena retrieval tools (find_declaration, find_implementations) when serena=true,
# does NOT propagate guidance to subagents (Serena MCP usually unavailable in
# subagents), and does NOT mention the diagnostics tool get_diagnostics_for_file
# (which lives in the unified-context-stack phase docs instead, to keep the
# always-on banner succinct).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK_FILE="${REPO_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

# This is a content-level test: we grep the source for the specific banner copy
# rather than execute the full hook, because session-start has heavy capability
# discovery and would require stubbing the entire MCP/registry pipeline.

assert_file_exists "session-start hook source exists" "${HOOK_FILE}"

# Read the source for inspection.
SRC="$(cat "${HOOK_FILE}")"

assert_contains "Serena banner mentions mcp__serena__ tools" "mcp__serena__" "${SRC}"
assert_contains "Serena banner names find_declaration (v1.3.0)" "find_declaration" "${SRC}"
assert_contains "Serena banner names find_implementations (v1.3.0)" "find_implementations" "${SRC}"
assert_not_contains "Serena banner does NOT propagate to subagents (Serena MCP often unavailable in subagents)" "Task tool" "${SRC}"
assert_not_contains "Serena banner does NOT use 'Serena available' propagation phrase" "Serena available" "${SRC}"
assert_contains "LSP banner still names mcp__ide__getDiagnostics" "mcp__ide__getDiagnostics" "${SRC}"
assert_not_contains "banner does NOT mention get_diagnostics_for_file (kept in phase docs)" "get_diagnostics_for_file" "${SRC}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0

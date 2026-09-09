#!/usr/bin/env bash
# test-install.sh — Validation tests for installed plugin structure
# These tests verify that all required files exist and are valid.

set -euo pipefail

# Set SCRIPT_DIR for portability
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use CLAUDE_PLUGIN_ROOT if set, otherwise fallback to parent directory
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "${SCRIPT_DIR}")}"

# Source test helpers for assert functions
source "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo "Install Validation Tests"
echo "======================="
echo "Plugin root: ${PLUGIN_ROOT}"
echo ""

# Test 1: config/default-triggers.json exists and is valid JSON
assert_file_exists \
    "config/default-triggers.json exists" \
    "${PLUGIN_ROOT}/config/default-triggers.json"

assert_json_valid \
    "config/default-triggers.json is valid JSON" \
    "${PLUGIN_ROOT}/config/default-triggers.json"

# Test 2: config/fallback-registry.json exists and is valid JSON
assert_file_exists \
    "config/fallback-registry.json exists" \
    "${PLUGIN_ROOT}/config/fallback-registry.json"

assert_json_valid \
    "config/fallback-registry.json is valid JSON" \
    "${PLUGIN_ROOT}/config/fallback-registry.json"

# Test 3: hooks/skill-activation-hook.sh exists and is executable
assert_file_exists \
    "hooks/skill-activation-hook.sh exists" \
    "${PLUGIN_ROOT}/hooks/skill-activation-hook.sh"

if [ -x "${PLUGIN_ROOT}/hooks/skill-activation-hook.sh" ]; then
    _record_pass "hooks/skill-activation-hook.sh is executable"
else
    _record_fail "hooks/skill-activation-hook.sh is executable" \
        "file is not executable"
fi

# Test 4: hooks/session-start-hook.sh exists and is executable
assert_file_exists \
    "hooks/session-start-hook.sh exists" \
    "${PLUGIN_ROOT}/hooks/session-start-hook.sh"

if [ -x "${PLUGIN_ROOT}/hooks/session-start-hook.sh" ]; then
    _record_pass "hooks/session-start-hook.sh is executable"
else
    _record_fail "hooks/session-start-hook.sh is executable" \
        "file is not executable"
fi

# Test 5: hooks/fix-plugin-manifests.sh exists and is executable
assert_file_exists \
    "hooks/fix-plugin-manifests.sh exists" \
    "${PLUGIN_ROOT}/hooks/fix-plugin-manifests.sh"

if [ -x "${PLUGIN_ROOT}/hooks/fix-plugin-manifests.sh" ]; then
    _record_pass "hooks/fix-plugin-manifests.sh is executable"
else
    _record_fail "hooks/fix-plugin-manifests.sh is executable" \
        "file is not executable"
fi

# Test 6: hooks/hooks.json exists, is valid JSON, and references both hooks
assert_file_exists \
    "hooks/hooks.json exists" \
    "${PLUGIN_ROOT}/hooks/hooks.json"

assert_json_valid \
    "hooks/hooks.json is valid JSON" \
    "${PLUGIN_ROOT}/hooks/hooks.json"

# Verify hooks.json references session-start-hook.sh
HOOKS_CONTENT=$(cat "${PLUGIN_ROOT}/hooks/hooks.json")
assert_contains \
    "hooks.json references session-start-hook.sh" \
    "session-start-hook.sh" \
    "${HOOKS_CONTENT}"

# Verify hooks.json references skill-activation-hook.sh
assert_contains \
    "hooks.json references skill-activation-hook.sh" \
    "skill-activation-hook.sh" \
    "${HOOKS_CONTENT}"

# Test 7: hooks/teammate-idle-guard.sh exists and is executable
assert_file_exists \
    "hooks/teammate-idle-guard.sh exists" \
    "${PLUGIN_ROOT}/hooks/teammate-idle-guard.sh"

if [ -x "${PLUGIN_ROOT}/hooks/teammate-idle-guard.sh" ]; then
    _record_pass "hooks/teammate-idle-guard.sh is executable"
else
    _record_fail "hooks/teammate-idle-guard.sh is executable" \
        "file is not executable"
fi

# Verify hooks.json references teammate-idle-guard.sh
assert_contains \
    "hooks.json references teammate-idle-guard.sh" \
    "teammate-idle-guard.sh" \
    "${HOOKS_CONTENT}"

# Test: hooks/openspec-guard.sh exists and is executable
assert_file_exists \
    "hooks/openspec-guard.sh exists" \
    "${PLUGIN_ROOT}/hooks/openspec-guard.sh"

if [ -x "${PLUGIN_ROOT}/hooks/openspec-guard.sh" ]; then
    _record_pass "hooks/openspec-guard.sh is executable"
else
    _record_fail "hooks/openspec-guard.sh is executable" \
        "file is not executable"
fi

# Verify hooks.json references openspec-guard.sh
assert_contains \
    "hooks.json references openspec-guard.sh" \
    "openspec-guard.sh" \
    "${HOOKS_CONTENT}"

# Test 8: hooks.json registers all required hook events
for event in SessionStart UserPromptSubmit PreToolUse PostToolUse PreCompact Stop TeammateIdle; do
    if printf '%s' "${HOOKS_CONTENT}" | jq -e ".hooks.${event}" >/dev/null 2>&1; then
        _record_pass "hooks.json registers ${event} event"
    else
        _record_fail "hooks.json registers ${event} event" \
            "event not found in hooks.json"
    fi
done

# Verify cozempic wrapper hooks are present
assert_contains \
    "hooks.json uses cozempic-wrapper.sh for checkpoint" \
    "cozempic-wrapper.sh checkpoint" \
    "${HOOKS_CONTENT}"

assert_contains \
    "hooks.json uses cozempic-wrapper.sh for guard" \
    "cozempic-wrapper.sh guard" \
    "${HOOKS_CONTENT}"

# Test: cozempic-wrapper.sh exists and is executable
assert_file_exists \
    "hooks/cozempic-wrapper.sh exists" \
    "${PLUGIN_ROOT}/hooks/cozempic-wrapper.sh"

if [ -x "${PLUGIN_ROOT}/hooks/cozempic-wrapper.sh" ]; then
    _record_pass "hooks/cozempic-wrapper.sh is executable"
else
    _record_fail "hooks/cozempic-wrapper.sh is executable" \
        "file is not executable"
fi

# Test 9: the named bundled skills still exist on disk (deletion guard).
#
# The README half of this test was REMOVED. It asserted README<->skills/ sync
# from a hardcoded 18-name list, which drifted: the list omitted 5 owned skills
# and was the origin of the stale "18 skills" prose. That invariant now lives in
# tests/test-readme-inventory.sh, which DERIVES the population and asserts both
# directions, so a hardcoded list here is a second, silently-staler authority for
# the same thing. This loop keeps only the deletion guard.
for skill_name in \
    agent-safety-review \
    agent-team-execution \
    agent-team-review \
    alert-hygiene \
    batch-scripting \
    deploy-gate \
    design-debate \
    implementation-drift-check \
    incident-analysis \
    incident-trend-analyzer \
    openspec-ship \
    outcome-review \
    product-discovery \
    prototype-lab \
    runtime-validation \
    security-scanner \
    skill-scaffold \
    unified-context-stack
do
    assert_file_exists \
        "skills/${skill_name}/SKILL.md exists" \
        "${PLUGIN_ROOT}/skills/${skill_name}/SKILL.md"
done

# Test 10: .claude-plugin/plugin.json exists and is valid JSON
assert_file_exists \
    ".claude-plugin/plugin.json exists" \
    "${PLUGIN_ROOT}/.claude-plugin/plugin.json"

assert_json_valid \
    ".claude-plugin/plugin.json is valid JSON" \
    "${PLUGIN_ROOT}/.claude-plugin/plugin.json"

# Test: fallback registry has plugins and phase_compositions sections
echo "-- test: fallback has plugins key --"
FALLBACK="${PLUGIN_ROOT}/config/fallback-registry.json"

has_plugins="$(jq 'has("plugins")' "${FALLBACK}" 2>/dev/null)"
assert_equals "fallback has plugins key" "true" "${has_plugins}"

echo "-- test: fallback has phase_compositions key --"
has_pc="$(jq 'has("phase_compositions")' "${FALLBACK}" 2>/dev/null)"
assert_equals "fallback has phase_compositions key" "true" "${has_pc}"

# Test: session-start-hook.sh does NOT auto-install packages
echo "-- test: no auto-install in session-start --"
HOOK_SRC="$(cat "${PLUGIN_ROOT}/hooks/session-start-hook.sh")"

# Check for actual install commands (exclude warning/message strings)
if printf '%s' "${HOOK_SRC}" | grep -v 'printf\|MSG=' | grep -q 'pip install'; then
    _record_fail "no pip install command in session-start" "found pip install outside of warning message"
else
    _record_pass "no pip install command in session-start"
fi

if printf '%s' "${HOOK_SRC}" | grep -v 'printf\|MSG=' | grep -q 'brew install'; then
    _record_fail "no brew install command in session-start" "found brew install outside of warning message"
else
    _record_pass "no brew install command in session-start"
fi

if printf '%s' "${HOOK_SRC}" | grep -v 'printf\|MSG=' | grep -q 'apt-get install'; then
    _record_fail "no apt-get install command in session-start" "found apt-get install outside of warning message"
else
    _record_pass "no apt-get install command in session-start"
fi

# ---------------------------------------------------------------------------
# Print summary and exit with appropriate code
# ---------------------------------------------------------------------------
print_summary

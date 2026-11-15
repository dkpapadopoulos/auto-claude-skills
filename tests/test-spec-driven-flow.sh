#!/usr/bin/env bash
# test-spec-driven-flow.sh — End-to-end verification of spec-driven mode
# 1. Preset file has openspec_first: true
# 2. Session-start with spec-driven preset announces the mode and rewrites no hint
# 3. Session-start without preset does not announce it
# 4. openspec-ship SKILL.md has pre-flight check content
# 5. design-debate SKILL.md has both mode outputs
#
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-spec-driven-flow.sh ==="

# ---------------------------------------------------------------------------
# Phase 1: Preset file has the flag
# ---------------------------------------------------------------------------
echo "-- Phase 1: preset file --"
preset_file="${PROJECT_ROOT}/config/presets/spec-driven.json"
assert_file_exists "spec-driven preset exists" "$preset_file"
flag="$(jq -r '.openspec_first // false' "$preset_file")"
assert_equals "openspec_first is true" "true" "$flag"

# ---------------------------------------------------------------------------
# Phase 2: Session-start with spec-driven preset announces the mode
# ---------------------------------------------------------------------------
# The preset used to rewrite three DESIGN/PLAN phase hints. The shipped phase hints
# were removed (openspec/changes/registered-hint-cut), so the preset now announces the
# mode once per session and rewrites nothing.
_SD_NOTICE="spec-driven mode active: design intent persisted to openspec/changes/ (committed)"
_hint_shape() { jq -r --arg p "$2" '.phase_compositions[$p].hints | "\(type):\(length)"' "$1" 2>/dev/null; }

echo "-- Phase 2: session-start announces spec-driven mode --"
setup_test_env
mkdir -p "${HOME}/.claude"
printf '{"preset":"spec-driven"}' > "${HOME}/.claude/skill-config.json"

sd_out="$(CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    bash "${HOOK}" 2>/dev/null < /dev/null)"

cache_file="${HOME}/.claude/.skill-registry-cache.json"
assert_file_exists "cache file exists" "$cache_file"
assert_contains "spec-driven: the mode is announced" "${_SD_NOTICE}" "$sd_out"
assert_equals "spec-driven: no DESIGN hint is written" "array:0" "$(_hint_shape "$cache_file" DESIGN)"
assert_equals "spec-driven: no PLAN hint is written" "array:0" "$(_hint_shape "$cache_file" PLAN)"

teardown_test_env

# ---------------------------------------------------------------------------
# Phase 3: Session-start without preset does not announce it
# ---------------------------------------------------------------------------
echo "-- Phase 3: no preset, no announcement --"
setup_test_env
# No skill-config.json → no preset
def_out="$(CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    bash "${HOOK}" 2>/dev/null < /dev/null)"

cache_file="${HOME}/.claude/.skill-registry-cache.json"
assert_file_exists "cache file exists (default mode)" "$cache_file"
assert_not_contains "default mode: spec-driven is not announced" "spec-driven mode active" "$def_out"
assert_equals "default mode: no DESIGN hint is written" "array:0" "$(_hint_shape "$cache_file" DESIGN)"
teardown_test_env

# ---------------------------------------------------------------------------
# Phase 4: openspec-ship has idempotent pre-flight check content
# ---------------------------------------------------------------------------
echo "-- Phase 4: openspec-ship content --"
ship_content="$(cat "${PROJECT_ROOT}/skills/openspec-ship/SKILL.md")"
assert_contains "pre-flight check documented" "Pre-flight check" "$ship_content"
assert_contains "spec-driven mode path documented" "change folder already exists" "$ship_content"
assert_contains "new-capability warning documented" "NEW CAPABILITY" "$ship_content"

# ---------------------------------------------------------------------------
# Phase 5: design-debate has dual-mode output template
# ---------------------------------------------------------------------------
echo "-- Phase 5: design-debate content --"
debate_content="$(cat "${PROJECT_ROOT}/skills/design-debate/SKILL.md")"
assert_contains "design-debate: spec-driven section" "Spec-driven mode" "$debate_content"
assert_contains "design-debate: solo section" "Solo mode" "$debate_content"

print_summary
exit $?

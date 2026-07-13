#!/usr/bin/env bash
# test-validation-skill-content.sh — Content-contract assertions for
# runtime-validation and implementation-drift-check skills.
# Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-validation-skill-content.sh ==="

setup_test_env

# ---------------------------------------------------------------------------
# runtime-validation content assertions
# ---------------------------------------------------------------------------
RV_SKILL="${PROJECT_ROOT}/skills/runtime-validation/SKILL.md"
RV_CONTENT="$(cat "${RV_SKILL}")"

# Frontmatter
assert_contains "rv: has name frontmatter" "name: runtime-validation" "$RV_CONTENT"

# Three execution paths
assert_contains "rv: browser path documented" "Browser" "$RV_CONTENT"
assert_contains "rv: API path documented" "API" "$RV_CONTENT"
assert_contains "rv: CLI path documented" "CLI" "$RV_CONTENT"

# Playwright detection
assert_contains "rv: playwright detection" "playwright" "$RV_CONTENT"

# axe-core / a11y
assert_contains "rv: a11y checks documented" "axe" "$RV_CONTENT"

# Graceful degradation
assert_contains "rv: graceful degradation documented" "no interactive validation tools" "$RV_CONTENT"

# Report contract
assert_contains "rv: unified report heading" "Validation Report" "$RV_CONTENT"
assert_contains "rv: coverage gaps section" "Coverage Gaps" "$RV_CONTENT"
assert_contains "rv: manual checks section" "Manual Checks" "$RV_CONTENT"

# Fix-rescan loop
assert_contains "rv: fix-rescan loop" "Max 3" "$RV_CONTENT"

# Session marker
assert_contains "rv: session marker" "validation-ran" "$RV_CONTENT"

# Ad-hoc script temp location
assert_contains "rv: mktemp for ad-hoc scripts" "mktemp" "$RV_CONTENT"

# Webapp-testing registry check
assert_contains "rv: registry-based webapp-testing check" "skill-registry-cache" "$RV_CONTENT"

# Eval pack consumption
assert_contains "rv: eval pack consumption" "fixtures/evals" "$RV_CONTENT"

# Expectation provenance (validation-contract-hardening)
assert_contains "rv: expectation provenance heading" "Expectation Provenance" "$RV_CONTENT"
assert_contains "rv: provenance MUST rule" "MUST NOT define what counts as correct" "$RV_CONTENT"
assert_contains "rv: provenance source enum" 'eval-pack`, `intent-truth`, or `generic-smoke' "$RV_CONTENT"
assert_contains "rv: untraceable expectation never PASS" "do not report it as PASS" "$RV_CONTENT"

# ---------------------------------------------------------------------------
# implementation-drift-check content assertions
# ---------------------------------------------------------------------------
DC_SKILL="${PROJECT_ROOT}/skills/implementation-drift-check/SKILL.md"
DC_CONTENT="$(cat "${DC_SKILL}")"

# Frontmatter
assert_contains "dc: has name frontmatter" "name: implementation-drift-check" "$DC_CONTENT"

# Two report modes
assert_contains "dc: full drift mode" "Implementation Drift Check" "$DC_CONTENT"
assert_contains "dc: assumptions-only mode" "Assumptions & Gaps" "$DC_CONTENT"

# Comparison sources — canonical paths first
assert_contains "dc: openspec changes source" "openspec/changes" "$DC_CONTENT"
assert_contains "dc: canonical plans source" "docs/plans/" "$DC_CONTENT"
assert_contains "dc: canonical spec source" "openspec/specs" "$DC_CONTENT"
assert_contains "dc: legacy superpowers fallback" "docs/superpowers/" "$DC_CONTENT"
assert_contains "dc: eval pack source" "fixtures/evals" "$DC_CONTENT"

# Drift dimensions
assert_contains "dc: spec drift" "Spec Alignment" "$DC_CONTENT"
assert_contains "dc: plan drift" "Plan Alignment" "$DC_CONTENT"
assert_contains "dc: review-induced drift" "Review-Induced" "$DC_CONTENT"

# Flags
assert_contains "dc: implemented-as-specified flag" "implemented-as-specified" "$DC_CONTENT"
assert_contains "dc: added-without-spec flag" "added-without-spec" "$DC_CONTENT"

# Session marker
assert_contains "dc: session marker" "drift-check-ran" "$DC_CONTENT"

# Auto-co-selection guard explanation
assert_contains "dc: artifact-presence gate" "artifact-presence" "$DC_CONTENT"

# Persistence
assert_contains "dc: post-implementation notes" "Post-Implementation Notes" "$DC_CONTENT"

teardown_test_env

echo ""
echo "=== Validation Skill Content Results ==="
echo "  Total: ${TESTS_RUN}"
echo "  Passed: ${TESTS_PASSED}"
echo "  Failed: ${TESTS_FAILED}"
[ "${TESTS_FAILED}" -eq 0 ] || exit 1

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
# Situational detail lives in references/ (openspec/changes/skill-reattach-budget);
# negative checks scan the core AND every reference, since the model reads both.
RV_REFS_DIR="${PROJECT_ROOT}/skills/runtime-validation/references"
RV_ALL_CONTENT="$(cat "${RV_SKILL}" "${RV_REFS_DIR}"/*.md)"

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
# Dead session marker removed (openspec: state-scripts-injection-cut). It wrote
# ~/.skill-validation-ran-<token> that NO code ever read, using the forbidden
# singleton-token incantation, under a false "checked by the SHIP phase gate"
# claim. Pin it stays gone so it cannot be reintroduced.
assert_not_contains "rv: dead session marker removed" "validation-ran" "$RV_ALL_CONTENT"
assert_contains "rv: unified report heading" "Validation Report" "$RV_CONTENT"
assert_contains "rv: coverage gaps section" "Coverage Gaps" "$RV_CONTENT"
assert_contains "rv: manual checks section" "Manual Checks" "$RV_CONTENT"
# The report template itself moved to references/report-template.md.
RV_REPORT_CONTENT="$(cat "${RV_REFS_DIR}/report-template.md" 2>/dev/null)"
assert_contains "rv: template has report heading" "## Validation Report" "$RV_REPORT_CONTENT"
assert_contains "rv: template has coverage gaps section" "### Coverage Gaps" "$RV_REPORT_CONTENT"
assert_contains "rv: template has manual checks section" "### Manual Checks Recommended" "$RV_REPORT_CONTENT"
assert_contains "rv: core points Step 4 at the template" 'Read `references/report-template.md` before writing the report' "$RV_CONTENT"

# References index: every references/*.md is named from SKILL.md, and every
# references/*.md SKILL.md names exists. A file the core never names is never Read.
_rv_n=0
for _f in "${RV_REFS_DIR}"/*.md; do
    [ -f "${_f}" ] || continue
    _rv_n=$((_rv_n + 1))
    _base="$(basename "${_f}")"
    assert_contains "rv: SKILL.md names references/${_base}" "references/${_base}" "$RV_CONTENT"
done
assert_equals "rv: references/ holds the three moved files" "3" "${_rv_n}"
for _named in $(grep -oE 'references/[A-Za-z0-9_-]+\.md' "${RV_SKILL}" | sort -u); do
    assert_file_exists "rv: named ${_named} exists" "${PROJECT_ROOT}/skills/runtime-validation/${_named}"
done

# Fix-rescan loop
assert_contains "rv: fix-rescan loop" "Max 3" "$RV_CONTENT"


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
# Dead session marker removed (openspec: state-scripts-injection-cut) — see the
# rv note above; same dead-write + false-claim pattern. Pin it stays gone.
assert_not_contains "dc: dead session marker removed" "drift-check-ran" "$DC_CONTENT"
# The suppression it claimed (session-marker gate) never worked (marker written
# under the singleton, hook reads payload-first) and its writer is deleted — the
# SKILL.md must not claim automatic SHIP suppression, and no config may carry the
# dead session-marker gate. Pinned after a PR review caught the false claim.
assert_not_contains "dc: no false SHIP-suppression claim" "SHIP entry is suppressed" "$DC_CONTENT"
assert_not_contains "dc: no session-marker-gate claim"    "session-marker gate"       "$DC_CONTENT"
_DT="$(cat "${PROJECT_ROOT}/config/default-triggers.json")"
_FB="$(cat "${PROJECT_ROOT}/config/fallback-registry.json")"
assert_not_contains "default-triggers: dead session-marker gate removed" "session-marker" "$_DT"
assert_not_contains "fallback-registry: dead session-marker gate removed" "session-marker" "$_FB"

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

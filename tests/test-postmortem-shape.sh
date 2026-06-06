#!/usr/bin/env bash
# test-postmortem-shape.sh — Regression test for postmortem schema contract.
# Validates the canonical 8-section schema in incident-analysis and
# heading-text matching compatibility in incident-trend-analyzer.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-postmortem-shape.sh ==="

ANALYSIS_SKILL="${PROJECT_ROOT}/skills/incident-analysis/SKILL.md"
TREND_SKILL="${PROJECT_ROOT}/skills/incident-trend-analyzer/SKILL.md"
ANALYSIS_CONTENT="$(cat "${ANALYSIS_SKILL}")"
TREND_CONTENT="$(cat "${TREND_SKILL}")"

# ---------------------------------------------------------------------------
# Test 1: Canonical 8-section schema — all headings present in template
# ---------------------------------------------------------------------------

# Extract the built-in default schema block. Prefer the reference file (post-extraction);
# fall back to inline SKILL.md block (pre-extraction layout).
TEMPLATE_REF="${PROJECT_ROOT}/skills/incident-analysis/references/postmortem-template.md"
if [ -f "${TEMPLATE_REF}" ]; then
    SCHEMA_BLOCK="$(cat "${TEMPLATE_REF}")"
else
    SCHEMA_START=$(grep -n "Built-in default schema" "${ANALYSIS_SKILL}" | head -1 | cut -d: -f1)
    if [ -n "${SCHEMA_START}" ]; then
        SCHEMA_BLOCK="$(tail -n +"${SCHEMA_START}" "${ANALYSIS_SKILL}" | sed -n '/^```$/,/^```$/p')"
    else
        SCHEMA_BLOCK=""
    fi
fi

assert_contains "canonical: Summary heading" "Summary" "${SCHEMA_BLOCK}"
assert_contains "canonical: Impact heading" "Impact" "${SCHEMA_BLOCK}"
assert_contains "canonical: Action Items heading" "Action Items" "${SCHEMA_BLOCK}"
assert_contains "canonical: Root Cause heading" "Root Cause" "${SCHEMA_BLOCK}"
assert_contains "canonical: Timeline heading" "Timeline" "${SCHEMA_BLOCK}"
assert_contains "canonical: Contributing Factors heading" "Contributing Factors" "${SCHEMA_BLOCK}"
assert_contains "canonical: Lessons Learned heading" "Lessons Learned" "${SCHEMA_BLOCK}"
assert_contains "canonical: Investigation Notes heading" "Investigation Notes" "${SCHEMA_BLOCK}"

# ---------------------------------------------------------------------------
# Test 1b: Action Items declare a Type field with the three phase values (#8)
# ---------------------------------------------------------------------------
assert_contains "action items: Type field present" "type" "${SCHEMA_BLOCK}"
assert_contains "action items: Detect value defined" "Detect" "${SCHEMA_BLOCK}"
assert_contains "action items: Prevent value defined" "Prevent" "${SCHEMA_BLOCK}"
assert_contains "action items: Mitigate value defined" "Mitigate" "${SCHEMA_BLOCK}"

# ---------------------------------------------------------------------------
# Test 2: Canonical schema ordering — Action Items before Timeline
# ---------------------------------------------------------------------------

ACTION_LINE=$(printf '%s' "${SCHEMA_BLOCK}" | grep -n "Action Items" | head -1 | cut -d: -f1)
TIMELINE_LINE=$(printf '%s' "${SCHEMA_BLOCK}" | grep -n "Timeline" | head -1 | cut -d: -f1)

if [ -n "${ACTION_LINE}" ] && [ -n "${TIMELINE_LINE}" ] && [ "${ACTION_LINE}" -lt "${TIMELINE_LINE}" ]; then
    _record_pass "canonical: Action Items before Timeline"
else
    _record_fail "canonical: Action Items before Timeline" "Action Items at line ${ACTION_LINE:-?}, Timeline at line ${TIMELINE_LINE:-?}"
fi

# ---------------------------------------------------------------------------
# Test 3: No stale "Resolution and Recovery" as a top-level section in schema
# ---------------------------------------------------------------------------

if printf '%s' "${SCHEMA_BLOCK}" | grep -q "Resolution and Recovery"; then
    _record_fail "canonical: no Resolution section" "stale 'Resolution and Recovery' found in schema block"
else
    _record_pass "canonical: no Resolution section"
fi

# ---------------------------------------------------------------------------
# Test 4: No stale "7 section" language in incident-analysis
# ---------------------------------------------------------------------------

if printf '%s' "${ANALYSIS_CONTENT}" | grep -qi "7 section headers\|seven section"; then
    _record_fail "stale: no 7-section language" "found '7 section headers' or 'seven section' in incident-analysis"
else
    _record_pass "stale: no 7-section language"
fi

# ---------------------------------------------------------------------------
# Test 5: Trend analyzer uses heading-text matching, not ordinal
# ---------------------------------------------------------------------------

assert_contains "trend: heading text matching" "heading text" "${TREND_CONTENT}"

# Trend analyzer must NOT contain hardcoded ordinal section refs like "## 3. Timeline"
if printf '%s' "${TREND_CONTENT}" | grep -qE '## [0-9]+\. (Timeline|Summary|Root Cause|Action Items)'; then
    _record_fail "trend: no ordinal section refs" "found hardcoded ordinal section reference in trend analyzer"
else
    _record_pass "trend: no ordinal section refs"
fi

# ---------------------------------------------------------------------------
# Test 6: Trend analyzer legacy compatibility — accepts both schemas
# ---------------------------------------------------------------------------

assert_contains "trend: legacy 7-section mentioned" "legacy" "${TREND_CONTENT}"
assert_contains "trend: canonical 8-section mentioned" "canonical" "${TREND_CONTENT}"

# Root Cause matching accepts both forms
if printf '%s' "${TREND_CONTENT}" | grep -q "Root Cause & Trigger" && \
   printf '%s' "${TREND_CONTENT}" | grep -q '"Root Cause"'; then
    _record_pass "trend: Root Cause flexible matching"
else
    _record_fail "trend: Root Cause flexible matching" "trend analyzer should accept both 'Root Cause & Trigger' and 'Root Cause'"
fi

# ---------------------------------------------------------------------------
# Test 7: Contract consistency — both skills agree on canonical headings
# ---------------------------------------------------------------------------

for heading in "Summary" "Impact" "Action Items" "Root Cause" "Timeline" "Contributing Factors" "Lessons Learned" "Investigation Notes"; do
    if printf '%s' "${ANALYSIS_CONTENT}" | grep -q "${heading}" && \
       printf '%s' "${TREND_CONTENT}" | grep -q "${heading}"; then
        _record_pass "contract: ${heading} in both skills"
    else
        _record_fail "contract: ${heading} in both skills" "${heading} missing from one or both skills"
    fi
done

# ---------------------------------------------------------------------------
# Test 8: No stale "7 section" language in the spec
# ---------------------------------------------------------------------------
SPEC_FILE="${PROJECT_ROOT}/openspec/specs/incident-analysis/spec.md"
if [ -f "${SPEC_FILE}" ]; then
    SPEC_CONTENT="$(cat "${SPEC_FILE}")"
    if printf '%s' "${SPEC_CONTENT}" | grep -qi "7 section headers\|seven section"; then
        _record_fail "spec: no 7-section language" "found '7 section headers' or 'seven section' in spec.md"
    else
        _record_pass "spec: no 7-section language"
    fi
else
    _record_pass "spec: no 7-section language (spec file not present, skip)"
fi

print_summary

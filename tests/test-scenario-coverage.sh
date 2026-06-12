#!/usr/bin/env bash
# test-scenario-coverage.sh — Tests for scripts/scenario-coverage.sh logic.
# Uses a controlled temp --root fixture so assertions don't depend on live
# repo state (which changes as packs are added). Bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

REPORT="${PROJECT_ROOT}/scripts/scenario-coverage.sh"

echo "=== test-scenario-coverage.sh ==="

# Build a temp root with four capabilities exercising each classification path.
_make_root() {
    local root="$1"
    # 1. exec-uncovered: SKILL.md + >=3 probabilistic THEN clauses + NO pack
    mkdir -p "${root}/skills/exec-uncovered" "${root}/openspec/specs/exec-uncovered"
    printf 'x\n' > "${root}/skills/exec-uncovered/SKILL.md"
    {
        echo "#### Scenario: a"; echo "Then it recommends an action";
        echo "#### Scenario: b"; echo "Then it explains the cause";
        echo "#### Scenario: c"; echo "Then it classifies the failure";
        echo "#### Scenario: d"; echo "Then it falls back to manual review";
    } > "${root}/openspec/specs/exec-uncovered/spec.md"

    # 2. exec-covered: same, but WITH a behavioral pack
    mkdir -p "${root}/skills/exec-covered" "${root}/openspec/specs/exec-covered" \
             "${root}/tests/fixtures/exec-covered/evals"
    printf 'x\n' > "${root}/skills/exec-covered/SKILL.md"
    cp "${root}/openspec/specs/exec-uncovered/spec.md" "${root}/openspec/specs/exec-covered/spec.md"
    printf '[{"id":"c1","prompt":"p","expected_behavior":"e","assertions":[{"text":"x","description":"d"}]}]\n' \
        > "${root}/tests/fixtures/exec-covered/evals/behavioral.json"

    # 3. infra-cap: spec has probabilistic THENs but NO SKILL.md -> out of scope
    mkdir -p "${root}/openspec/specs/infra-cap"
    cp "${root}/openspec/specs/exec-uncovered/spec.md" "${root}/openspec/specs/infra-cap/spec.md"

    # 4. thin-skill: SKILL.md present but < threshold probabilistic THENs -> skipped
    mkdir -p "${root}/skills/thin-skill" "${root}/openspec/specs/thin-skill"
    printf 'x\n' > "${root}/skills/thin-skill/SKILL.md"
    { echo "#### Scenario: only-one"; echo "Then it recommends one thing"; } \
        > "${root}/openspec/specs/thin-skill/spec.md"
}

# ---------------------------------------------------------------------------
test_classification() {
    echo "-- test: classification of each capability path --"
    local root out
    root="$(mktemp -d)"
    _make_root "${root}"
    out="$(/bin/bash "${REPORT}" --root "${root}" 2>&1)"

    assert_contains "exec-uncovered flagged UNCOVERED" "exec-uncovered" "${out}"
    assert_contains "uncovered summary header present" "uncovered (no behavioral eval pack):" "${out}"
    # exec-covered must show has-pack, never UNCOVERED on its row
    assert_contains "exec-covered present" "exec-covered" "${out}"
    assert_contains "exec-covered has-pack" "has-pack" "${out}"
    # infra-cap (no SKILL.md) and thin-skill (below threshold) must be absent
    assert_not_contains "infra-cap excluded (no SKILL.md)" "infra-cap" "${out}"
    assert_not_contains "thin-skill excluded (below threshold)" "thin-skill" "${out}"

    rm -rf "${root}"
}
test_classification

# ---------------------------------------------------------------------------
test_advisory_exit_zero() {
    echo "-- test: advisory mode exits 0 even with uncovered gaps --"
    local root rc
    root="$(mktemp -d)"
    _make_root "${root}"
    /bin/bash "${REPORT}" --root "${root}" >/dev/null 2>&1
    rc=$?
    assert_equals "advisory run exits 0 despite uncovered" "0" "${rc}"
    rm -rf "${root}"
}
test_advisory_exit_zero

# ---------------------------------------------------------------------------
test_strict_nonzero_on_uncovered() {
    echo "-- test: --strict exits 1 when an uncovered gap exists --"
    local root rc
    root="$(mktemp -d)"
    _make_root "${root}"
    /bin/bash "${REPORT}" --root "${root}" --strict >/dev/null 2>&1
    rc=$?
    assert_equals "strict run exits 1 on uncovered gap" "1" "${rc}"
    rm -rf "${root}"
}
test_strict_nonzero_on_uncovered

# ---------------------------------------------------------------------------
test_strict_zero_when_all_covered() {
    echo "-- test: --strict exits 0 when no uncovered gaps --"
    local root rc
    root="$(mktemp -d)"
    # Only the covered capability present.
    mkdir -p "${root}/skills/exec-covered" "${root}/openspec/specs/exec-covered" \
             "${root}/tests/fixtures/exec-covered/evals"
    printf 'x\n' > "${root}/skills/exec-covered/SKILL.md"
    {
        echo "Then it recommends an action"; echo "Then it explains the cause";
        echo "Then it classifies the failure";
    } > "${root}/openspec/specs/exec-covered/spec.md"
    printf '[{"id":"c1","prompt":"p","expected_behavior":"e","assertions":[{"text":"x","description":"d"}]}]\n' \
        > "${root}/tests/fixtures/exec-covered/evals/behavioral.json"
    /bin/bash "${REPORT}" --root "${root}" --strict >/dev/null 2>&1
    rc=$?
    assert_equals "strict run exits 0 when all covered" "0" "${rc}"
    rm -rf "${root}"
}
test_strict_zero_when_all_covered

# ---------------------------------------------------------------------------
test_fail_open_no_specs_dir() {
    echo "-- test: fail-open when no specs directory exists --"
    local root rc out
    root="$(mktemp -d)"
    out="$(/bin/bash "${REPORT}" --root "${root}" 2>&1)"
    rc=$?
    assert_equals "missing specs dir exits 0 (fail-open)" "0" "${rc}"
    assert_contains "reports nothing-to-report" "no specs directory" "${out}"
    rm -rf "${root}"
}
test_fail_open_no_specs_dir

# ---------------------------------------------------------------------------
test_backfilled_packs_are_covered() {
    echo "-- test: real security-scanner + incident-trend-analyzer show has-pack --"
    local out
    out="$(/bin/bash "${REPORT}" --root "${PROJECT_ROOT}" 2>&1)"
    # Regression guard: the two backfilled packs in THIS change must be covered.
    assert_contains "security-scanner row present" "security-scanner" "${out}"
    assert_contains "incident-trend-analyzer row present" "incident-trend-analyzer" "${out}"
    local uncovered_line
    uncovered_line="$(printf '%s\n' "${out}" | grep 'uncovered (no behavioral')"
    assert_not_contains "security-scanner not in uncovered list" "security-scanner" "${uncovered_line}"
    assert_not_contains "incident-trend-analyzer not in uncovered list" "incident-trend-analyzer" "${uncovered_line}"
}
test_backfilled_packs_are_covered

print_summary

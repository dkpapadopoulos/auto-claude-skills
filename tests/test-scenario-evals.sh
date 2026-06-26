#!/usr/bin/env bash
# test-scenario-evals.sh — Suite-level behavioral evaluation for auto-claude-skills
# Tests routing judgment, not just mechanics. Validates that the right skills fire
# for the right prompts and that guardrails intercept unsafe patterns.
# Bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures/scenarios"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-scenario-evals.sh ==="

# ---------------------------------------------------------------------------
# Helper: run the hook with a given prompt, return stdout
# ---------------------------------------------------------------------------
run_hook() {
    local prompt="$1"
    jq -n --arg p "${prompt}" '{"prompt":$p}' | \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        bash "${HOOK}" 2>/dev/null
}

# Helper: extract the additionalContext text from hook JSON output
extract_context() {
    local output="$1"
    printf '%s' "${output}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

# ---------------------------------------------------------------------------
# Install the full registry including Wave 1 skills
# ---------------------------------------------------------------------------
install_scenario_registry() {
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "${cache_file}")"
    # Build from fallback-registry.json, then patch all skills to available:true
    # to simulate a real session where session-start has discovered all plugins.
    # Without this, superpowers skills (verification-before-completion, etc.) are
    # available:false in the fallback and adversarial guardrail prompts find no match.
    jq '.skills = [.skills[] | .available = true]' \
        "${PROJECT_ROOT}/config/fallback-registry.json" > "${cache_file}"
    # Clear any skill state files from prior test runs to ensure clean routing
    rm -f "${HOME}/.claude/.skill-last-invoked-"* 2>/dev/null
    rm -f "${HOME}/.claude/.skill-composition-state-"* 2>/dev/null
    rm -f "${HOME}/.claude/.skill-prompt-count-"* 2>/dev/null
    rm -f "${HOME}/.claude/.skill-session-token" 2>/dev/null
    rm -f "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Run a single scenario from a fixture file
# ---------------------------------------------------------------------------
run_scenario() {
    local fixture_file="$1"
    local name prompt
    name="$(jq -r '.name' "$fixture_file")"
    prompt="$(jq -r '.prompt' "$fixture_file")"

    echo "-- scenario: ${name} --"

    local output context
    output="$(run_hook "${prompt}")"
    context="$(extract_context "${output}")"

    # Check expected phase
    local expected_phase
    expected_phase="$(jq -r '.expected_phase // empty' "$fixture_file")"
    if [ -n "${expected_phase}" ]; then
        assert_contains "${name}: expected phase '${expected_phase}'" "Phase: [${expected_phase}]" "${context}"
    fi

    # Check expected skills are present
    local expected_count
    expected_count="$(jq -r '.expected_skills | length' "$fixture_file")"
    local i=0
    while [ "$i" -lt "$expected_count" ]; do
        local expected_skill
        expected_skill="$(jq -r ".expected_skills[$i]" "$fixture_file")"
        assert_contains "${name}: expected skill '${expected_skill}'" "${expected_skill}" "${context}"
        i=$((i + 1))
    done

    # Check expected_in_composition skills appear in the composition chain
    local comp_count
    comp_count="$(jq -r '.expected_in_composition // [] | length' "$fixture_file")"
    local k=0
    while [ "$k" -lt "$comp_count" ]; do
        local comp_skill
        comp_skill="$(jq -r ".expected_in_composition[$k]" "$fixture_file")"
        assert_contains "${name}: composition includes '${comp_skill}'" "${comp_skill}" "${context}"
        k=$((k + 1))
    done

    # Check must_not_match patterns are absent
    local must_not_count
    must_not_count="$(jq -r '.must_not_match | length' "$fixture_file")"
    local j=0
    while [ "$j" -lt "$must_not_count" ]; do
        local must_not
        must_not="$(jq -r ".must_not_match[$j]" "$fixture_file")"
        assert_not_contains "${name}: must not contain '${must_not}'" "${must_not}" "${context}"
        j=$((j + 1))
    done

    # Check must_match patterns are present
    local must_count
    must_count="$(jq -r '.must_match // [] | length' "$fixture_file")"
    local m=0
    while [ "$m" -lt "$must_count" ]; do
        local must
        must="$(jq -r ".must_match[$m]" "$fixture_file")"
        assert_contains "${name}: must contain '${must}'" "${must}" "${context}"
        m=$((m + 1))
    done
}

# ---------------------------------------------------------------------------
# Main: run all scenario fixtures
# ---------------------------------------------------------------------------
setup_test_env
install_scenario_registry

for fixture in "${FIXTURES_DIR}"/*.json; do
    [ -f "$fixture" ] || continue
    run_scenario "$fixture"
done

teardown_test_env

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Scenario Eval Results ==="
echo "  Total: ${TESTS_RUN}"
echo "  Passed: ${TESTS_PASSED}"
echo "  Failed: ${TESTS_FAILED}"

if [ -n "${FAIL_MESSAGES}" ]; then
    echo ""
    echo "Failures:"
    printf '%s\n' "${FAIL_MESSAGES}"
fi

if [ "${TESTS_FAILED}" -gt 0 ]; then
    exit 1
fi

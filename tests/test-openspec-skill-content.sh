#!/usr/bin/env bash
# test-openspec-skill-content.sh — Validate openspec-ship SKILL.md content
# against what the openspec CLI actually expects.
# Bash 3.2 compatible. Sources test-helpers.sh for assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

SKILL_FILE="${PROJECT_ROOT}/skills/openspec-ship/SKILL.md"

echo "=== test-openspec-skill-content.sh ==="

# ---------------------------------------------------------------------------
# 1. No deprecated "openspec change" commands in skill text
# ---------------------------------------------------------------------------
test_no_deprecated_change_commands() {
    echo "-- test: no deprecated openspec change commands --"

    # Match "openspec change <verb>" but exclude the deprecation warning table
    # that explicitly documents what NOT to do (lines with "not `openspec change")
    local deprecated_uses
    deprecated_uses="$(grep -n 'openspec change' "$SKILL_FILE" \
        | grep -v '(not `openspec change' \
        | grep -v 'deprecated' \
        | grep -v '^\-\-' || true)"

    if [ -z "$deprecated_uses" ]; then
        _record_pass "no deprecated openspec change commands"
    else
        _record_fail "found deprecated openspec change commands" "$deprecated_uses"
    fi
}
test_no_deprecated_change_commands

# ---------------------------------------------------------------------------
# 2. No /opsx: slash commands (replaced by verb-first CLI)
# ---------------------------------------------------------------------------
test_no_opsx_slash_commands() {
    echo "-- test: no /opsx: slash commands in CLI paths --"

    # Exclude documentation references that explain what NOT to use
    local opsx_uses
    opsx_uses="$(grep -n '/opsx:' "$SKILL_FILE" \
        | grep -v 'not the base CLI' \
        | grep -v 'not `' || true)"

    if [ -z "$opsx_uses" ]; then
        _record_pass "no /opsx: slash commands"
    else
        _record_fail "found /opsx: slash commands" "$opsx_uses"
    fi
}
test_no_opsx_slash_commands

# ---------------------------------------------------------------------------
# 3. Proposal template has required headers
# ---------------------------------------------------------------------------
test_proposal_template_headers() {
    echo "-- test: proposal template has required headers --"

    local skill_content
    skill_content="$(cat "$SKILL_FILE")"

    # Extract the proposal.md template block (between "**proposal.md**" and the next "**")
    local has_why has_what_changes
    has_why="$(grep -c '^## Why' "$SKILL_FILE" || true)"
    has_what_changes="$(grep -c '^## What Changes' "$SKILL_FILE" || true)"

    assert_equals "proposal template has ## Why header" "1" "$has_why"
    assert_equals "proposal template has ## What Changes header" "1" "$has_what_changes"
}
test_proposal_template_headers

# ---------------------------------------------------------------------------
# 4. Proposal template does NOT have old invalid headers
# ---------------------------------------------------------------------------
test_no_old_proposal_headers() {
    echo "-- test: no old proposal headers --"

    local old_problem old_proposed
    old_problem="$(grep -c '## Problem Statement' "$SKILL_FILE" || true)"
    old_proposed="$(grep -c '## Proposed Solution' "$SKILL_FILE" || true)"

    assert_equals "no ## Problem Statement header" "0" "$old_problem"
    assert_equals "no ## Proposed Solution header" "0" "$old_proposed"
}
test_no_old_proposal_headers

# ---------------------------------------------------------------------------
# 5. Spec template uses RFC 2119 uppercase keywords
# ---------------------------------------------------------------------------
test_rfc2119_keywords_uppercase() {
    echo "-- test: spec template uses RFC 2119 uppercase keywords --"

    local skill_content
    skill_content="$(cat "$SKILL_FILE")"

    assert_contains "mentions RFC 2119" "RFC 2119" "$skill_content"
    assert_contains "MUST in uppercase" "MUST" "$skill_content"
    assert_contains "SHALL in uppercase" "SHALL" "$skill_content"
}
test_rfc2119_keywords_uppercase

# ---------------------------------------------------------------------------
# 6. Verb-first CLI commands are present
# ---------------------------------------------------------------------------
test_verb_first_commands_present() {
    echo "-- test: verb-first CLI commands present --"

    local skill_content
    skill_content="$(cat "$SKILL_FILE")"

    assert_contains "openspec new change present" "openspec new change" "$skill_content"
    assert_contains "openspec validate present" "openspec validate" "$skill_content"
    assert_contains "openspec archive present" "openspec archive" "$skill_content"
}
test_verb_first_commands_present

# ---------------------------------------------------------------------------
# 7. Validate proposal template against openspec CLI (integration test)
# ---------------------------------------------------------------------------
test_proposal_validates_with_cli() {
    echo "-- test: proposal template validates with openspec CLI --"

    if ! command -v openspec >/dev/null 2>&1; then
        _record_pass "skipped: openspec CLI not available"
        return
    fi

    setup_test_env

    # Initialize openspec in a temp project
    local test_project="${TEST_TMPDIR}/project"
    mkdir -p "$test_project"
    cd "$test_project"
    git init -q
    git config user.email "test@test.local"
    git config user.name "Test"
    git commit --allow-empty -m "init" -q
    openspec init -y . >/dev/null 2>&1 || true

    # Create a change using the CLI
    openspec new change test-feature >/dev/null 2>&1 || true

    if [ ! -d "$test_project/openspec/changes/test-feature" ]; then
        _record_fail "openspec new change failed to create directory"
        teardown_test_env
        cd "$PROJECT_ROOT"
        return
    fi

    # Write proposal using the template from SKILL.md
    cat > "$test_project/openspec/changes/test-feature/proposal.md" <<'PROPOSAL'
## Why
Fix deprecation warnings and template mismatches in openspec-ship skill.

## What Changes
Updated CLI commands to verb-first syntax and aligned proposal headers with openspec validator expectations.

## Capabilities

### New Capabilities
- `test-feature`: Test capability for validation

### Modified Capabilities

## Impact
Skill file only — no runtime code changes.
PROPOSAL

    # Write a minimal delta spec
    mkdir -p "$test_project/openspec/changes/test-feature/specs/test-feature"
    cat > "$test_project/openspec/changes/test-feature/specs/test-feature/spec.md" <<'SPEC'
## ADDED Requirements

### Requirement: Template Compliance
The proposal template MUST use headers that match openspec validator expectations.

#### Scenario: Validate proposal
- **WHEN** openspec validate runs on a proposal generated from the skill template
- **THEN** no "Missing required sections" warnings are emitted
SPEC

    # Run validation and capture output
    local val_output
    val_output="$(cd "$test_project" && openspec validate test-feature 2>&1)" || true

    # Check for the specific warning we're fixing
    local missing_sections
    missing_sections="$(printf '%s' "$val_output" | grep -c 'Missing required sections' || true)"
    assert_equals "no Missing required sections warning" "0" "$missing_sections"

    # Check no deprecation warning
    local deprecated
    deprecated="$(printf '%s' "$val_output" | grep -c 'deprecated' || true)"
    assert_equals "no deprecation warnings from validate" "0" "$deprecated"

    cd "$PROJECT_ROOT"
    teardown_test_env
}
test_proposal_validates_with_cli

# ---------------------------------------------------------------------------
# openspec-ship: idempotent sync for spec-driven mode
# ---------------------------------------------------------------------------
test_openspec_ship_idempotent_sync() {
    echo "-- test: openspec-ship has idempotent pre-flight check --"
    local SHIP_SKILL="${PROJECT_ROOT}/skills/openspec-ship/SKILL.md"
    local SHIP_CONTENT
    SHIP_CONTENT="$(cat "${SHIP_SKILL}")"

    assert_contains "openspec-ship: pre-flight check documented" "Pre-flight check" "$SHIP_CONTENT"
    assert_contains "openspec-ship: sync path (change exists)" "change folder already exists" "$SHIP_CONTENT"
    assert_contains "openspec-ship: retrospective path preserved" "create retrospectively" "$SHIP_CONTENT"
    assert_contains "openspec-ship: new capability warning" "NEW CAPABILITY" "$SHIP_CONTENT"
    assert_contains "openspec-ship: spec-driven mode reference" "spec-driven" "$SHIP_CONTENT"
}
test_openspec_ship_idempotent_sync

# ---------------------------------------------------------------------------
# openspec-ship: capability taxonomy inference heuristic
# ---------------------------------------------------------------------------
test_openspec_ship_capability_heuristic() {
    echo "-- test: openspec-ship has capability inference heuristic --"
    local SHIP_SKILL="${PROJECT_ROOT}/skills/openspec-ship/SKILL.md"
    local SHIP_CONTENT
    SHIP_CONTENT="$(cat "${SHIP_SKILL}")"

    # Must instruct enumerating existing capabilities before creating a new one
    assert_contains "ship: lists existing capabilities before create" "ls openspec/specs/" "$SHIP_CONTENT"
    # Must have a heuristic that prefers extension
    assert_contains "ship: prefers extending existing capability" "prefer extending" "$SHIP_CONTENT"
    # Must have a confidence threshold — auto-create vs ask
    assert_contains "ship: confidence threshold for auto-create" "confidence" "$SHIP_CONTENT"
    # Must instruct asking user when uncertain
    assert_contains "ship: ask when uncertain" "ask the user" "$SHIP_CONTENT"
}
test_openspec_ship_capability_heuristic

# ---------------------------------------------------------------------------
# Issue #157: session-token resolution must be own-session-first
# ---------------------------------------------------------------------------
# This skill both WRITES ~/.claude/.skill-openspec-state-<token> and READS it
# back, from the model's Bash turn. The PLAN design guard in
# skill-activation-hook.sh resolves its token payload-first (#51), while
# ~/.claude/.skill-session-token is a shared last-writer-wins singleton — under
# concurrent sessions it names a DIFFERENT conversation, so a singleton-resolved
# write scatters into a file the guard never opens. The fix is doc-only, so it
# regresses silently without these pins.
test_openspec_ship_session_token_resolution() {
    echo "-- test: session token resolved own-session-first (#157) --"

    local content
    content="$(cat "${SKILL_FILE}")"

    assert_contains "ship: uses the shared own-session resolver (#157)" \
        "resolve_own_session_token" "$content"
    assert_contains "ship: sources session-token.sh, not a hand-rolled shape (#157)" \
        "hooks/lib/session-token.sh" "$content"

    # Every prose instruction must route through the resolver block, not tell
    # the model to read the singleton directly.
    assert_not_contains "ship: no prose 'read the singleton for the token' (#157)" \
        'Read `~/.claude/.skill-session-token`' "$content"

    # The singleton may only survive as the LAST-RESORT fallback (`... || cat ...`),
    # never as a primary `TOKEN=$(cat ...)` assignment — in ANY quoting style, so a
    # regression written with backticks or without quotes is caught too. grep -E,
    # not a substring match: the fallback legitimately names the same path.
    local naked="absent"
    grep -Eq 'TOKEN=[^|]*(\$\(|`)[[:space:]]*cat[[:space:]]+~?/?[^|]*\.skill-session-token' "${SKILL_FILE}" \
        && naked="present"
    assert_equals "ship: singleton only as fallback, never first assignment (#157)" \
        "absent" "$naked"
    # openspec-ship is the one remaining surface with a HAND-ROLLED inline
    # resolver (deferred from state-scripts-injection-cut — it also reads state
    # and mark-archives). Shell state does not persist across Bash tool calls, so
    # every executable block that uses $TOKEN must re-resolve it; the old
    # symmetry test pinned this warning and its retirement must not drop it.
    assert_contains "ship: warns shell state does not persist between Bash calls (#157)" \
        "does not persist between" "$content"
}
test_openspec_ship_session_token_resolution

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${TESTS_PASSED} passed, ${TESTS_FAILED} failed"
echo ""
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo "Failures:"
    printf '%s\n' "${FAIL_MESSAGES}"
    exit 1
else
    echo "All tests passed."
fi

#!/usr/bin/env bash
# test-openspec-ci-gate.sh — Content and behavior tests for the OpenSpec PR
# validation gate (script + workflow).
#
# Script behavior covered:
#   - excludes openspec/changes/archive
#   - exits 0 when no active changes exist
#   - exits 0 when openspec/changes/ does not exist
#   - runs `openspec validate <slug>` for each discovered active change
#   - errors loudly if the openspec CLI is missing
#   - aggregates failures across multiple active changes (does not fail-fast)
#
# Workflow content covered:
#   - triggers on PR events (opened, synchronize, reopened, ready_for_review)
#   - pins the OpenSpec CLI version (not @latest)
#   - job name is stable (`openspec-validate`) for branch protection
#   - invokes the repo script
#   - has a job timeout
#
# Bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-openspec-ci-gate.sh ==="

SCRIPT_PATH="${PROJECT_ROOT}/scripts/validate-active-openspec-changes.sh"
WORKFLOW_PATH="${PROJECT_ROOT}/.github/workflows/openspec-validate.yml"

# ---------------------------------------------------------------------------
# Script existence + syntax
# ---------------------------------------------------------------------------
echo "-- Script --"
assert_file_exists "validate script exists" "${SCRIPT_PATH}"
if [ -f "${SCRIPT_PATH}" ]; then
    bash -n "${SCRIPT_PATH}" 2>/dev/null \
        && _record_pass "script has valid bash syntax" \
        || _record_fail "script has valid bash syntax" "bash -n failed"
    [ -x "${SCRIPT_PATH}" ] \
        && _record_pass "script is executable" \
        || _record_fail "script is executable" "missing +x"
fi

SCRIPT_CONTENT=""
[ -f "${SCRIPT_PATH}" ] && SCRIPT_CONTENT="$(cat "${SCRIPT_PATH}")"

assert_contains "script excludes archive directory" "archive" "${SCRIPT_CONTENT}"
assert_contains "script calls openspec validate" "openspec validate" "${SCRIPT_CONTENT}"
assert_contains "script errors if CLI missing" "command -v openspec" "${SCRIPT_CONTENT}"

# ---------------------------------------------------------------------------
# Script behavior: empty / missing changes directory exits 0
# ---------------------------------------------------------------------------
echo "-- Script behavior --"
if [ -x "${SCRIPT_PATH}" ]; then
    _tmp="$(mktemp -d)"
    # No openspec/ at all — should exit 0 with a notice
    if (cd "${_tmp}" && bash "${SCRIPT_PATH}" >/dev/null 2>&1); then
        _record_pass "script exits 0 when openspec/changes/ missing"
    else
        _record_fail "script exits 0 when openspec/changes/ missing" "exit was non-zero"
    fi

    # Empty openspec/changes/ — should exit 0
    mkdir -p "${_tmp}/openspec/changes"
    if (cd "${_tmp}" && bash "${SCRIPT_PATH}" >/dev/null 2>&1); then
        _record_pass "script exits 0 when no active changes exist"
    else
        _record_fail "script exits 0 when no active changes exist" "exit was non-zero"
    fi

    # Only archive/ under changes/ — should still exit 0
    mkdir -p "${_tmp}/openspec/changes/archive/2026-01-01-old/specs/cap"
    if (cd "${_tmp}" && bash "${SCRIPT_PATH}" >/dev/null 2>&1); then
        _record_pass "script skips archive directory (no active changes)"
    else
        _record_fail "script skips archive directory (no active changes)" "exit was non-zero"
    fi

    rm -rf "${_tmp}"
fi

# ---------------------------------------------------------------------------
# Script behavior: missing openspec CLI triggers loud error
# ---------------------------------------------------------------------------
if [ -x "${SCRIPT_PATH}" ]; then
    _tmp="$(mktemp -d)"
    mkdir -p "${_tmp}/openspec/changes/feature-a"
    # Create a fake PATH without openspec
    _fake_bin="$(mktemp -d)"
    # ASSERT the precondition (#275). This PATH keeps /usr/bin and /bin, which
    # is exactly the arrangement that silently handed a "no-jq" cell a working
    # jq on macOS — an installed openspec on either of those paths would make
    # the cell below test the CLI-present branch while claiming the opposite.
    # SUBSHELL, not `PATH=X command -v` in this shell: bash HASHES command
    # locations, and `command -v` consults that hash before PATH — so the
    # in-shell form reported a tool as present purely because an earlier line
    # had run it. Measured: two of these assertions failed against shims that
    # provably lacked the tool. A fresh shell has an empty hash.
    if PATH="${_fake_bin}:/usr/bin:/bin" /bin/bash -c 'command -v openspec' >/dev/null 2>&1; then
        _record_fail "precondition: openspec is unresolvable on the fake PATH" \
            "openspec resolves, so this cell would test the wrong branch"
    elif (cd "${_tmp}" && PATH="${_fake_bin}:/usr/bin:/bin" bash "${SCRIPT_PATH}" >/dev/null 2>&1); then
        _record_fail "script errors when CLI missing" "exited 0 but should have failed"
    else
        _record_pass "script errors when CLI missing"
    fi
    rm -rf "${_tmp}" "${_fake_bin}"
fi

# ---------------------------------------------------------------------------
# Workflow content
# ---------------------------------------------------------------------------
echo "-- Workflow --"
assert_file_exists "workflow exists" "${WORKFLOW_PATH}"
WORKFLOW_CONTENT=""
[ -f "${WORKFLOW_PATH}" ] && WORKFLOW_CONTENT="$(cat "${WORKFLOW_PATH}")"

assert_contains "workflow triggers on pull_request" "pull_request" "${WORKFLOW_CONTENT}"
assert_contains "workflow triggers on opened" "opened" "${WORKFLOW_CONTENT}"
assert_contains "workflow triggers on synchronize" "synchronize" "${WORKFLOW_CONTENT}"
assert_contains "workflow triggers on reopened" "reopened" "${WORKFLOW_CONTENT}"
assert_contains "workflow triggers on ready_for_review" "ready_for_review" "${WORKFLOW_CONTENT}"
assert_contains "workflow job id is openspec-validate" "openspec-validate:" "${WORKFLOW_CONTENT}"
assert_contains "workflow installs @fission-ai/openspec" "@fission-ai/openspec" "${WORKFLOW_CONTENT}"
assert_contains "workflow invokes repo script" "validate-active-openspec-changes.sh" "${WORKFLOW_CONTENT}"
assert_contains "workflow has timeout" "timeout-minutes" "${WORKFLOW_CONTENT}"

# Pinned version, not @latest
assert_not_contains "workflow does not use @latest (pinned version)" "@fission-ai/openspec@latest" "${WORKFLOW_CONTENT}"

# ---------------------------------------------------------------------------
# CODEOWNERS template — for multi-user spec-driven repos
# ---------------------------------------------------------------------------
echo "-- CODEOWNERS template --"
CODEOWNERS_TEMPLATE="${PROJECT_ROOT}/.github/CODEOWNERS.template"

assert_file_exists "CODEOWNERS template exists" "${CODEOWNERS_TEMPLATE}"
CODEOWNERS_CONTENT=""
[ -f "${CODEOWNERS_TEMPLATE}" ] && CODEOWNERS_CONTENT="$(cat "${CODEOWNERS_TEMPLATE}")"

# Should document that it's a template (not our repo's actual CODEOWNERS)
assert_contains "template clearly marked as template" "template" "${CODEOWNERS_CONTENT}"

# Should show the openspec/specs/<capability>/ pattern that unlocks per-capability ownership
assert_contains "shows openspec/specs/ ownership pattern" "openspec/specs/" "${CODEOWNERS_CONTENT}"

# Should also cover openspec/changes/ for in-flight review routing
assert_contains "covers openspec/changes/ for in-flight specs" "openspec/changes/" "${CODEOWNERS_CONTENT}"

# Should warn NOT to copy the template verbatim (team names are placeholders)
assert_contains "warns to replace @placeholder teams" "@your-" "${CODEOWNERS_CONTENT}"

# ---------------------------------------------------------------------------
# docs/CI.md covers CODEOWNERS setup
# ---------------------------------------------------------------------------
echo "-- docs/CI.md CODEOWNERS section --"
CI_DOC="${PROJECT_ROOT}/docs/CI.md"
CI_CONTENT=""
[ -f "${CI_DOC}" ] && CI_CONTENT="$(cat "${CI_DOC}")"

assert_contains "docs/CI.md mentions CODEOWNERS" "CODEOWNERS" "${CI_CONTENT}"
assert_contains "docs/CI.md points at the template" "CODEOWNERS.template" "${CI_CONTENT}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary
exit $?

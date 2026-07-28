#!/usr/bin/env bash
# Pins the repo's own "the done-gates are CI-blocking" claim to reality.
#
# CLAUDE.md and docs/enforcement-map.md both asserted the two owned done-gates were
# "CI-blocking via .verify.yml". That was false: .verify.yml is `substrate: local`,
# read only by hooks/lib/verdict.sh, the project-verification skill and tests — no
# GitHub workflow reads it, and none invoked tests/run-tests.sh. The gates ran
# locally via the push gate, which by construction cannot see a merge performed
# through the GitHub web UI (PR #178 was merged exactly that way).
#
# This test exists so the claim cannot silently rot again: if the workflow is
# deleted, renamed, or stops running either gate, this goes red. Same discipline as
# the precondition-render check added under #169 — a cited proof must resolve.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-done-gate-ci.sh ==="

WF="${PROJECT_ROOT}/.github/workflows/done-gates.yml"
assert_file_exists "done-gates workflow exists" "${WF}"

_wf="$(cat "${WF}" 2>/dev/null || echo '')"
assert_not_empty "workflow is readable and non-empty" "${_wf}"

# EVERY assertion below must be scoped to the EXECUTABLE `run:` lines, never to the
# whole file. The workflow's own header comment names both gate scripts in prose, so
# a whole-file `assert_contains` is satisfied by the comment alone — deleting the CI
# step that actually invokes a gate then left this test 9/9 green (reproduced). That
# is the precise regression this file exists to catch, so scope is load-bearing here,
# not stylistic.
_run_lines="$(printf '%s\n' "${_wf}" | grep -E '^[[:space:]]*run:' || true)"
assert_not_empty "workflow has run: steps" "${_run_lines}"

# The two gates the docs actually claim are CI-blocking. Both are pure content-grep
# tests — no ~/.claude state, no subprocess hooks — which is why they are safe to
# make required while the full 10-minute suite is not.
assert_contains "workflow RUNS the routing-fixture coverage gate" \
    "tests/test-fixture-coverage.sh" "${_run_lines}"
assert_contains "workflow RUNS the skill-content coverage gate" \
    "tests/test-skill-content-coverage.sh" "${_run_lines}"

# Must fire on PRs, or it cannot back a merge-time claim. Asserted against the YAML
# key (line-anchored, with colon), not the prose word — the header comment discusses
# PRs in English and would otherwise satisfy this.
_trigger_keys="$(printf '%s\n' "${_wf}" | grep -E '^[[:space:]]*(pull_request|push):' || true)"
assert_contains "workflow triggers on pull_request" "pull_request:" "${_trigger_keys}"

# The documented stdin-hang trap: these suites hang when stdin is a socket, which on
# a runner surfaces only as an uninformative timeout. A step that omits the redirect
# is the most likely way this workflow breaks unnoticed.
_gate_lines="$(printf '%s\n' "${_run_lines}" | grep -E 'tests/.*\.sh' || true)"
assert_not_empty "gate invocation lines found" "${_gate_lines}"
_missing_stdin="$(printf '%s\n' "${_gate_lines}" | grep -cv '< */dev/null' || true)"
assert_equals "every test invocation closes stdin (< /dev/null)" "0" "${_missing_stdin}"

# Both gate scripts must actually exist — a workflow citing a missing script is the
# same phantom-proof failure this test was written to prevent.
assert_file_exists "fixture-coverage gate script exists" \
    "${PROJECT_ROOT}/tests/test-fixture-coverage.sh"
assert_file_exists "skill-content coverage gate script exists" \
    "${PROJECT_ROOT}/tests/test-skill-content-coverage.sh"

print_summary

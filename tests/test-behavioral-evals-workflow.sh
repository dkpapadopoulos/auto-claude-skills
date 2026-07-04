#!/usr/bin/env bash
# test-behavioral-evals-workflow.sh — Structural guards for the scheduled
# behavioral eval workflow. These encode the agent-safety-review mitigations;
# a failing assert here means an injection-relay or trigger-surface control
# was removed. Bash 3.2 compatible.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="${PROJECT_ROOT}/.github/workflows/behavioral-evals.yml"

. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-behavioral-evals-workflow.sh ==="

assert_file_exists "workflow exists" "${WF}"

wf="$(cat "${WF}")"

assert_contains "has weekly schedule trigger" "schedule:" "${wf}"
assert_contains "has manual dispatch" "workflow_dispatch:" "${wf}"
assert_not_contains "no pull_request trigger (main-only surface)" "pull_request" "${wf}"
assert_not_contains "no issue_comment trigger" "issue_comment" "${wf}"

assert_contains "read-only contents permission" "contents: read" "${wf}"
assert_contains "issues write permission" "issues: write" "${wf}"
assert_not_contains "never pull-requests write" "pull-requests: write" "${wf}"

assert_contains "CI sandbox enabled for inner runs" "EVAL_CI_SANDBOX: \"1\"" "${wf}"
assert_contains "judge model pinned" "JUDGE_MODEL: claude-sonnet-5" "${wf}"
assert_contains "subject model pinned" "--model claude-sonnet-5" "${wf}"
assert_contains "artifacts-dir passthrough wired" "--artifacts-dir tests/artifacts/iterations" "${wf}"

# CLI must be version-pinned (supply-chain floor), not latest.
if grep -Eq 'claude-code@[0-9]+\.[0-9]+\.[0-9]+' "${WF}"; then
    _record_pass "claude CLI npm install is version-pinned"
else
    _record_fail "claude CLI npm install is version-pinned" "no pinned semver found"
fi

# Injection-relay control: issue body is built from the structured report
# file only; raw output stays in artifacts.
assert_contains "issue body sourced from report file" "body-file" "${wf}"
assert_contains "data-only banner in issue body" "treat as data" "${wf}"
assert_contains "exact-title issue lookup" 'select(.title == $t)' "${wf}"
assert_contains "issue lookup paginates past default 30" "--limit 500" "${wf}"
assert_contains "artifacts uploaded" "upload-artifact" "${wf}"

assert_contains "issue closes only on explicit clean run" '"$RC" = "0"' "${wf}"

print_summary

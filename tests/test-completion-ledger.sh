#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-completion-ledger.sh ==="

# The hook must SOURCE branch-ledger.sh and call branch_ledger_record for a
# gating milestone after advancing .completed. Assert the wiring exists.
HOOK="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"
h="$(cat "${HOOK}")"
assert_contains "completion hook sources branch-ledger" "branch-ledger.sh" "${h}"
assert_contains "completion hook records gating milestone" "branch_ledger_record" "${h}"
assert_contains "gating set names requesting-code-review" "requesting-code-review" "${h}"
assert_contains "gating set names verification-before-completion" "verification-before-completion" "${h}"
# Source must be guarded so a non-zero source can't trip `trap ERR` and skip telemetry
assert_contains "branch-ledger source is guarded (|| true)" 'branch-ledger.sh" 2>/dev/null || true' "${h}"

assert_contains "credits subagent-driven-development"  "subagent-driven-development" "${h}"
assert_contains "credits agent-team-execution"         "agent-team-execution"        "${h}"
assert_contains "credits agent-team-review"            "agent-team-review"           "${h}"
assert_contains "review-embedding arm records canonical key" '_record_gating_milestone "requesting-code-review"' "${h}"

print_summary
exit $?

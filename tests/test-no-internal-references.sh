#!/usr/bin/env bash
# test-no-internal-references.sh — Guard: employer-/internal-identifying strings
# must not appear anywhere in tracked files. Repo scrubbed 2026-06-11 (PR #53):
# real-incident fixture content anonymized (example.com / com.example.core /
# example-org), internal postmortem deleted. The only allowed occurrences are
# the absence-assertion needles in the files excluded below — they ENFORCE the
# policy and must keep the literal string.
#
# Bash 3.2 compatible. Sources test-helpers.sh. Skips when git is unavailable.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-no-internal-references.sh ==="

if ! git -C "${PROJECT_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
    _record_pass "git unavailable — tracked-file scan is git-gated; skipping"
    print_summary
    exit 0
fi

_HITS="$(git -C "${PROJECT_ROOT}" grep -li 'oviva' -- . 2>/dev/null \
    | grep -v 'test-no-internal-references.sh' \
    | grep -v 'test-supply-chain-investigation-content.sh')" || _HITS=""
if [ -z "${_HITS}" ]; then
    _record_pass "no internal references (oviva) in tracked files"
else
    _record_fail "no internal references (oviva) in tracked files" "$(printf '%s' "${_HITS}" | tr '\n' ' ')"
fi

print_summary

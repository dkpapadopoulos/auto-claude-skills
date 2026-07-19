#!/usr/bin/env bash
# test-openspec-not-ignored.sh — spec-driven mode commits design intent to
# openspec/changes/ (CLAUDE.md "Spec Persistence Modes"), so new files there
# must never be gitignored: a wholesale openspec/ ignore silently orphans
# archived changes (32 local-only dirs found 2026-07-18). Bash 3.2 compatible.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-openspec-not-ignored.sh ==="

cd "${PROJECT_ROOT}" || { echo "error: cannot cd to project root" >&2; exit 2; }

# git check-ignore works on hypothetical paths: exit 0 = ignored, 1 = not.
for probe in \
    "openspec/changes/__ignore-probe__/proposal.md" \
    "openspec/changes/archive/2099-01-01-__ignore-probe__/tasks.md" \
    "openspec/specs/__ignore-probe__/spec.md"; do
    if git check-ignore -q "${probe}" 2>/dev/null; then
        src="$(git check-ignore -v "${probe}" 2>/dev/null | head -1)"
        _record_fail "${probe} would be gitignored (${src:-source unknown}) — new openspec artifacts must be committable"
    else
        _record_pass "${probe} is not gitignored"
    fi
done

print_summary

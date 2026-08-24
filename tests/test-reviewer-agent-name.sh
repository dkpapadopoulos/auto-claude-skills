#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-reviewer-agent-name.sh ==="

# The superpowers plugin ships no agents/ directory, so this agent type is
# unregistered and a literal dispatch of it fails. grep -F: the string has no
# regex metacharacters, but -F is the standing rule for literal matching.
#
# Scanned via `git grep` over TRACKED files, not a filesystem grep over a
# fixed directory list: the requirement is about what SHIPS. `git grep`
# automatically skips `.claude/worktrees/` checkouts and gitignored scratch
# (verified: `.superpowers/`, which holds the SDD ledger and quotes this
# string, is gitignored and does not self-match).
#   - `openspec/` is excluded: the spec documents quote the dead string
#     deliberately, as evidence of the defect being fixed.
#   - `tests/` is excluded: it holds this test file plus 4 frozen eval
#     snapshots under `tests/fixtures/*/evals/behavioral.json` that
#     legitimately embed the old string. Confirmed inert — both consuming
#     suites pass: test-composition-uptake-pack.sh (16/16) and
#     test-attestation-measurement.sh (37/37).
# A `git grep` exit code >1 is a real error (bad pathspec, not a repo, etc.)
# and must fail loudly rather than read as "zero hits, clean" — silently
# collapsing "could not check" into "no reference" would defeat the gate.
_gg_output="$(cd "${PROJECT_ROOT}" && git grep -lF 'superpowers:code-reviewer' -- \
    ':(exclude)openspec/' ':(exclude)tests/' 2>&1)"
_gg_exit=$?
if [ "${_gg_exit}" -gt 1 ]; then
    _record_fail "git grep scan for superpowers:code-reviewer completed without error" \
        "git grep exited ${_gg_exit}: ${_gg_output}"
elif [ -z "${_gg_output}" ]; then
    _record_pass "no unregistered superpowers:code-reviewer reference remains in tracked files"
else
    _hits="$(printf '%s\n' "${_gg_output}" | wc -l | tr -d ' ')"
    _record_fail "no unregistered superpowers:code-reviewer reference remains in tracked files" \
        "found ${_hits} tracked file(s):
${_gg_output}"
fi

# The replacement must name a target that exists on every install.
if grep -rqF 'general-purpose' "${PROJECT_ROOT}/config/default-triggers.json"; then
    _record_pass "routing config names an always-available reviewer target"
else
    _record_fail "routing config names an always-available reviewer target" \
        "general-purpose not found in default-triggers.json"
fi

print_summary
exit $?

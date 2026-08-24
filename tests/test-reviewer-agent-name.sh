#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-reviewer-agent-name.sh ==="

# The superpowers plugin ships no agents/ directory, so this agent type is
# unregistered and a literal dispatch of it fails. grep -F: the string has no
# regex metacharacters, but -F is the standing rule for literal matching.
_hits="$(grep -rF 'superpowers:code-reviewer' \
    "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/config" "${PROJECT_ROOT}/skills" \
    2>/dev/null | wc -l | tr -d ' ')"
if [ "${_hits}" = "0" ]; then
    _record_pass "no unregistered superpowers:code-reviewer reference remains"
else
    _record_fail "no unregistered superpowers:code-reviewer reference remains" \
        "found ${_hits} reference(s)"
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

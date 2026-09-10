#!/usr/bin/env bash
# test-synthesize-content.sh — pins the load-bearing sentences of skills/synthesize/SKILL.md.
# Change: cross-family-second-opinion. Each needle is a spec requirement, not style.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-synthesize-content.sh ==="
F="${PROJECT_ROOT}/skills/synthesize/SKILL.md"

if [ ! -f "${F}" ]; then
    _record_fail "skills/synthesize/SKILL.md exists" "missing ${F}"
    print_summary
    exit 1
fi
_record_pass "skills/synthesize/SKILL.md exists"

# needle|label pairs, heredoc-fed (never pipe — subshell would lose the counters)
while IFS='|' read -r needle label; do
    [ -n "${needle}" ] || continue
    if grep -qiF -- "${needle}" "${F}"; then
        _record_pass "synthesize: ${label}"
    else
        _record_fail "synthesize: ${label}" "needle not found: ${needle}"
    fi
done <<'NEEDLES'
without forcing consensus|no forced consensus
never vote|contradictions decided on evidence, never by vote
re-examine|unique-to-one claims re-examined against source
panel limitation|uncovered gaps flagged as panel limitation
unresolved disagreements|disagreements surfaced to the caller
data to flag|embedded instructions treated as data
never as instructions|embedded instructions never followed
exceeding the original prompt|violation flagging present
Adapted from patforna/core-skills (MIT)|attribution present
NEEDLES

print_summary

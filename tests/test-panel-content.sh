#!/usr/bin/env bash
# test-panel-content.sh — pins the load-bearing sentences of skills/panel/SKILL.md.
# Change: cross-family-second-opinion. Each needle is a spec requirement, not style.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-panel-content.sh ==="
F="${PROJECT_ROOT}/skills/panel/SKILL.md"

if [ ! -f "${F}" ]; then
    _record_fail "skills/panel/SKILL.md exists" "missing ${F}"
    print_summary
    exit 1
fi
_record_pass "skills/panel/SKILL.md exists"

# needle|label pairs, heredoc-fed (never pipe — subshell would lose the counters)
while IFS='|' read -r needle label; do
    [ -n "${needle}" ] || continue
    if grep -qiF -- "${needle}" "${F}"; then
        _record_pass "panel: ${label}"
    else
        _record_fail "panel: ${label}" "needle not found: ${needle}"
    fi
done <<'NEEDLES'
read-only|cross-family dispatch is read-only (codex-rescue defaults to write)
fail loudly|missing prompt fails loudly, never inferred
single round|single round, no cross-talk
fresh context|panelists run in fresh contexts
anti-sycophancy|anti-sycophancy block present
if your honest answer differs|anti-sycophancy block verbatim core
probed at dispatch|availability probed at dispatch, never cached
materially weaker|degradation names the weakening
ask whether to proceed|default-roster degradation is consent-gated
never silently substitute|explicitly requested panelist is never substituted
destination|disclosure preview names the destination provider
what will be sent|disclosure preview shows the payload
mktemp|per-run scratch dir is securely created
0700|scratch dir permissions restricted
single level|skill-reference expansion is single-level, no recursion
recommend|panel recommends synthesize, never silently chains
verbatim|responses delivered verbatim
Adapted from patforna/core-skills (MIT)|attribution present
NEEDLES

# Negative pin: panel must never claim to synthesize
if grep -qiE '^panel synthesi' "${F}"; then
    _record_fail "panel: does not claim to synthesize" "found a 'panel synthesi...' claim"
else
    _record_pass "panel: does not claim to synthesize"
fi

print_summary

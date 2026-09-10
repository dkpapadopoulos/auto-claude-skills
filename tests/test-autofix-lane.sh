#!/usr/bin/env bash
# test-autofix-lane.sh — pins the lead-validated autofix lane (`Autofix:` FINDING
# line, §4 lead-validation step, and the Review Summary section) in
# skills/agent-team-review/SKILL.md.
# Change: cross-family-second-opinion (Task 5). Each needle is a spec
# requirement, not style.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-autofix-lane.sh ==="
F="${PROJECT_ROOT}/skills/agent-team-review/SKILL.md"

if [ ! -f "${F}" ]; then
    _record_fail "skills/agent-team-review/SKILL.md exists" "missing ${F}"
    print_summary
    exit 1
fi
_record_pass "skills/agent-team-review/SKILL.md exists"

# needle|label pairs, heredoc-fed (never pipe — subshell would lose the counters)
while IFS='|' read -r needle label; do
    [ -n "${needle}" ] || continue
    if grep -qiF -- "${needle}" "${F}"; then
        _record_pass "autofix lane: ${label}"
    else
        _record_fail "autofix lane: ${label}" "needle not found: ${needle}"
    fi
done <<'NEEDLES'
Autofix:|contract line exists
additive to `Suggestion:`|autofix never replaces Suggestion
`suggestion`-severity findings|severity cap stated
never self-certif|token never self-certifies
validates every|lead validates each line independently
unique, and unstale|old-text staleness/uniqueness check
deduplicate|overlapping edits deduplicated
reverts to a normal suggestion|failed validation loses the routing
per-item|approval is per-item
apply all except|partial approval supported
byte-identical|applied diff must equal approved batch
revert and return to IMPLEMENT|mismatch path defined
before verification and verdict recording|application precedes the verdict
Autofix applied|summary section exists
NEEDLES

# --- Negative pin: within the FINDING contract section, `blocking` and -----
# `warning` must be named as never carrying the bypass.
SECTION="$(sed -n '/^### Reviewer .* Lead: Individual Finding/,/^### /p' "${F}")"
NEVER_CARRY_LINE="$(printf '%s\n' "${SECTION}" | grep -i 'never carry')"
if [ -n "${NEVER_CARRY_LINE}" ]; then
    if printf '%s' "${NEVER_CARRY_LINE}" | grep -qi 'blocking' \
        && printf '%s' "${NEVER_CARRY_LINE}" | grep -qi 'warning'; then
        _record_pass "autofix lane: blocking and warning named as never carrying the bypass"
    else
        _record_fail "autofix lane: blocking and warning named as never carrying the bypass" \
            "'never carry' line found but missing blocking/warning: ${NEVER_CARRY_LINE}"
    fi
else
    _record_fail "autofix lane: blocking and warning named as never carrying the bypass" \
        "no 'never carry' line found in the FINDING contract section"
fi

print_summary

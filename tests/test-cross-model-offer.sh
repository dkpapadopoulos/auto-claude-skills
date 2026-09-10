#!/usr/bin/env bash
# test-cross-model-offer.sh — pins the two-mode Cross-Model Offer (§6) and the
# verdict-after-offer ordering rule in skills/agent-team-review/SKILL.md.
# Change: cross-family-second-opinion (Task 4). Each needle is a spec
# requirement, not style.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-cross-model-offer.sh ==="
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
        _record_pass "cross-model offer: ${label}"
    else
        _record_fail "cross-model offer: ${label}" "needle not found: ${needle}"
    fi
done <<'NEEDLES'
Mode A|in-round mode exists
Mode B|post-verdict mode exists
advisory gap|Mode A non-delivery is advisory, not could-not-review
second cycle|Mode B defines a second verdict cycle
recomputed|verdict recomputed after cross-model findings
recorded once, after the offer is resolved|verdict-after-offer ordering
replaces the prior verdict|accepted blocking finding replaces clean
caps it at `suggestions_only`|accepted warning caps the verdict
assigned from the defect|category never from reviewer identity
skipped — a same-family substitute|no-second-family skips, never fakes
read-only/sandboxed — `codex-rescue`|dispatch read-only, tied to §6's own sentence
WRITE-CAPABLE|write-capable default named
NEEDLES

# Negative pin: §6 must no longer scope the offer to external-fact claims.
SECTION_6="$(sed -n '/^### 6\./,/^## /p' "${F}")"
COUNT="$(printf '%s\n' "${SECTION_6}" | grep -c 'external-fact claims')"
if [ "${COUNT}" -le 0 ]; then
    _record_pass "cross-model offer: §6 no longer scoped to external-fact claims"
else
    _record_fail "cross-model offer: §6 no longer scoped to external-fact claims" \
        "found ${COUNT} occurrence(s) of 'external-fact claims' in §6"
fi

print_summary

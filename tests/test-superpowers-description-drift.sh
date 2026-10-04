#!/usr/bin/env bash
# test-superpowers-description-drift.sh — the one-line descriptions this plugin shows for
# superpowers skills must not contradict what those skills now do.
#
# The descriptions in config/default-triggers.json are rendered into the routing block
# ("[LATER] Step 7: Skill(superpowers:finishing-a-development-branch) -- <description>") and
# into composition `purpose` lines, so a stale one tells the model something the skill it is
# about to invoke will contradict. Checked against superpowers 6.4.2 (2026-09-25):
#   * finishing-a-development-branch: the menu is merge locally / push and create a PR / keep
#     the branch (two options on a detached HEAD). "Discard" left the menu in v6.2.0 and
#     happens only when the user explicitly asks. We still said "present 4 options (...,
#     discard)".
#   * executing-plans: now "inline" execution — this session implements every task itself,
#     with one whole-branch review at the end; chosen at the plan handoff, or when no subagent
#     tool exists. We still said "If subagents available, use subagent-driven-development
#     instead".
#   * subagent-driven-development: a task review after each task plus a whole-branch review
#     at the end. We still said "two-stage review (spec compliance then code quality)".
#
#   D1  none of the stale claims is present in default-triggers.json, the fallback registry
#       or README.md
#   D2  the three descriptions state the current behaviour (positive needles, so D1 cannot be
#       satisfied by deleting the descriptions). They are deliberately no longer than the text
#       they replace: tests/test-injection-budget.sh ratchets what these cost every prompt.
#   D3  the fallback registry carries the same three descriptions as the default config
#   D4  ADVISORY, never a failure: when superpowers is installed on this machine, say whether
#       its text still matches the comment above. Upstream's wording is not under this repo's
#       control, and this suite is the push gate, so an upstream reword must not turn it red.
#       It prints UPSTREAM DRIFT or SKIPPED and counts as neither a pass nor a fail.
#
# LIMITS, stated: D2 is substring presence. It would accept "never do a whole-branch review".
# It pins the specific contradictions found on 2026-10-04, not "the descriptions are right".
# Still simplified on purpose: a detached HEAD gets two options, not three.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-superpowers-description-drift.sh ==="

CFG="${PROJECT_ROOT}/config/default-triggers.json"
FB="${PROJECT_ROOT}/config/fallback-registry.json"
README="${PROJECT_ROOT}/README.md"
if ! command -v jq >/dev/null 2>&1; then
    _record_fail "jq available" "jq is required"; print_summary; exit 1
fi

# D1: stale claims, as fixed strings. A plain argument list, not a here-document: a
# here-document needs a temp file, and where none can be created the loop ran zero times
# and this file still reported green (measured in a read-only sandbox). The count floor
# below is what turns "checked nothing" into a failure.
_d1_cells=0
for _stale in \
    "present 4 options" \
    "merge/PR/keep/discard options" \
    "two-stage review" \
    "If subagents available, use subagent-driven-development instead" \
    "Option 4 discard"
do
    for _f in "${CFG}" "${FB}" "${README}"; do
        _d1_cells=$((_d1_cells + 1))
        if grep -qF -- "${_stale}" "${_f}"; then
            _record_fail "D1: '${_stale}' is absent from ${_f##*/}" "still present"
        else
            _record_pass "D1: '${_stale}' is absent from ${_f##*/}"
        fi
    done
done
assert_equals "D1 floor: every stale claim was checked in every file (5 x 3)" "15" "${_d1_cells}"

desc() { jq -r --arg n "$2" '[.skills[] | select(.name == $n)][0].description // ""' "$1"; }

# D2: positive needles.
assert_contains "D2: finishing names the three menu options" "(merge local, create PR, keep branch)" "$(desc "${CFG}" finishing-a-development-branch)"
assert_not_contains "D2: finishing does not list discard as a menu option" "discard" "$(desc "${CFG}" finishing-a-development-branch)"
assert_not_contains "D2: finishing does not promise worktree cleanup (PR and keep preserve it)" "clean up worktree" "$(desc "${CFG}" finishing-a-development-branch)"
assert_contains "D2: executing-plans describes inline execution" "Inline execution" "$(desc "${CFG}" executing-plans)"
assert_contains "D2: executing-plans names the whole-branch review" "whole-branch review" "$(desc "${CFG}" executing-plans)"
assert_contains "D2: subagent-driven-development names the whole-branch review" "whole-branch review" "$(desc "${CFG}" subagent-driven-development)"

# D3: the fallback copy matches.
for _n in finishing-a-development-branch executing-plans subagent-driven-development; do
    assert_equals "D3: fallback-registry.json has the same description for ${_n}" "$(desc "${CFG}" "${_n}")" "$(desc "${FB}" "${_n}")"
done

# D4: upstream, when present — advisory only. Highest version by numeric fields; `sort -V`
# is not assumed. Only the default marketplace location is looked at.
SP_DIR=""
_best_key=""
for _d in "${HOME}"/.claude/plugins/cache/superpowers-marketplace/superpowers/*/skills; do
    [ -d "${_d}" ] || continue
    _v="${_d%/skills}"; _v="${_v##*/}"
    _key="$(printf '%s' "${_v}" | awk -F. '{ printf "%08d%08d%08d", $1 + 0, $2 + 0, $3 + 0 }')"
    if [ -z "${_best_key}" ] || [ "${_key}" \> "${_best_key}" ]; then
        _best_key="${_key}"; SP_DIR="${_d}"
    fi
done
if [ -z "${SP_DIR}" ]; then
    echo "  SKIPPED: D4 — superpowers not found in the default marketplace location; upstream text was not checked"
else
    _drift=""
    grep -q 'present exactly these 3 options' "${SP_DIR}/finishing-a-development-branch/SKILL.md" 2>/dev/null \
        || _drift="${_drift} finishing-a-development-branch(3-option menu)"
    grep -q 'whole-branch review' "${SP_DIR}/subagent-driven-development/SKILL.md" 2>/dev/null \
        || _drift="${_drift} subagent-driven-development(whole-branch review)"
    grep -q 'inline execution' "${SP_DIR}/executing-plans/SKILL.md" 2>/dev/null \
        || _drift="${_drift} executing-plans(inline execution)"
    if [ -z "${_drift}" ]; then
        echo "  NOTE: D4 — upstream ${SP_DIR%/skills} still says what these descriptions assume"
    else
        echo "  UPSTREAM DRIFT (advisory, not a failure): ${SP_DIR%/skills} no longer matches for:${_drift} — re-read it and update the descriptions and this file"
    fi
fi

print_summary

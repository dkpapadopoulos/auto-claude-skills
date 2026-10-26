#!/usr/bin/env bash
# test-ship-drift-gate.sh — SHIP's implementation-drift-check FALLBACK renders
# under the same artifact-presence gate as REVIEW's PARALLEL entry.
#
# Why: REVIEW already hides implementation-drift-check when the repo holds no
# comparison material (plans, specs, openspec changes, eval packs). SHIP's
# SEQUENCE fallback had no gate, so in such a repo SHIP told the model to run a
# skill REVIEW had correctly hidden, with nothing to drift against.
# openspec: ship-drift-gate.
#
#   G1  in each config, SHIP's gated entry carries artifact-presence and an
#       artifacts list EQUAL to REVIEW's. The config format cannot reference
#       another entry's list (the hook's jq reads `.artifacts` inline), so the
#       two copies are held together here instead.
#   G2  the SHIP entry is identical in both configs.
#   R1  rendered through the real hook (temp HOME, temp git repo, SHIP prompt):
#       with no comparison material the SHIP drift line is absent, while the
#       other SEQUENCE lines still render (so "absent" is not "nothing rendered").
#   R2  the same repo plus docs/plans/x-plan.md: the SHIP drift line renders.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-ship-drift-gate.sh ==="

CFG="${PROJECT_ROOT}/config/default-triggers.json"
FB="${PROJECT_ROOT}/config/fallback-registry.json"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
SHIP_LINE="SEQUENCE: implementation-drift-check -> FALLBACK: Run drift check if it did not run in REVIEW"

if ! command -v jq >/dev/null 2>&1; then
    _record_fail "jq available" "jq is required"; print_summary; exit 1
fi

# --- G1: same gate, same list, per config ------------------------------------
_review_arts() { jq -c '[.phase_compositions.REVIEW.parallel[]? | select((.use // "") | startswith("implementation-drift-check")) | .artifacts][0] // null' "$1" 2>/dev/null; }
_ship_entry() { jq -c '[.phase_compositions.SHIP.sequence[]? | select(.step == "implementation-drift-check")][0] // null' "$1" 2>/dev/null; }
for _f in "${CFG}" "${FB}"; do
    _r="$(_review_arts "${_f}")"
    _s="$(_ship_entry "${_f}")"
    _n="$(printf '%s' "${_r}" | jq 'if type == "array" then length else 0 end' 2>/dev/null)"
    case "${_n}" in ''|*[!0-9]*) _n=0 ;; esac
    # Floor: two missing lists are "equal" too, and would pass the cell below.
    if [ "${_n}" -lt 1 ]; then
        _record_fail "G1: REVIEW's drift-check artifacts readable in ${_f##*/}" "none found; the equality cell would compare nothing"
        continue
    fi
    assert_equals "G1: SHIP's drift-check fallback is gated by artifact-presence in ${_f##*/}" \
        "artifact-presence" "$(printf '%s' "${_s}" | jq -r '.gate // ""' 2>/dev/null)"
    assert_equals "G1: SHIP's artifacts equal REVIEW's (${_n} patterns) in ${_f##*/}" \
        "${_r}" "$(printf '%s' "${_s}" | jq -c '.artifacts // null' 2>/dev/null)"
done

# --- G2: both configs carry the same SHIP entry ------------------------------
_a="$(_ship_entry "${CFG}")"
if [ "${_a}" = "null" ] || [ -z "${_a}" ]; then
    _record_fail "G2: SHIP drift-check entry readable in default-triggers.json" "not found"
else
    assert_equals "G2: fallback-registry.json carries the same SHIP drift-check entry" "${_a}" "$(_ship_entry "${FB}")"
fi

# --- R1/R2: rendered through the real hook -----------------------------------
setup_test_env
mkdir -p "${HOME}/.claude"
jq '.skills = [.skills[] | .available = true | .enabled = true]' "${CFG}" \
    > "${HOME}/.claude/.skill-registry-cache.json"
_REPO="${TEST_TMPDIR}/repo"
mkdir -p "${_REPO}"
( cd "${_REPO}" && env -u GIT_DIR -u GIT_WORK_TREE GIT_CONFIG_NOSYSTEM=1 sh -c \
    'git init -q . && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m base' ) >/dev/null 2>&1 \
    || _record_fail "temp git repo" "could not create ${_REPO}"

_render() {   # tag -> additionalContext of "ship it", project root = _REPO
    local _tp="${TEST_TMPDIR}/$1.jsonl"
    : > "${_tp}"
    jq -n --arg p "ship it" --arg t "${_tp}" '{prompt:$p, transcript_path:$t}' \
        | ( cd "${_REPO}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${_REPO}" \
            bash "${HOOK}" 2>/dev/null ) \
        | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

_ctx="$(_render bare)"
assert_contains "R1: the SHIP prompt renders the SHIP phase" "Phase: [SHIP]" "${_ctx}"
assert_contains "R1: control: the ungated SHIP sequence still renders" "SEQUENCE: openspec-ship ->" "${_ctx}"
assert_not_contains "R1: no comparison material -> no SHIP drift-check line" "${SHIP_LINE}" "${_ctx}"

mkdir -p "${_REPO}/docs/plans"
printf 'plan\n' > "${_REPO}/docs/plans/x-plan.md"
_ctx="$(_render withplan)"
assert_contains "R2: the SHIP prompt renders the SHIP phase" "Phase: [SHIP]" "${_ctx}"
assert_contains "R2: docs/plans/x-plan.md present -> the SHIP drift-check line renders" "${SHIP_LINE}" "${_ctx}"
teardown_test_env

print_summary

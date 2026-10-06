#!/usr/bin/env bash
# test-activation-progress-truth.sh — what the routing hook records as DONE.
#
# Two defects, both in hooks/skill-activation-hook.sh:
#
#   D  a bare reply ("ok") marked chain steps completed with nothing invoked. The step the
#      hook DISPLAYED was written as the last-invoked signal and the next prompt credited
#      it, so six "ok"s recorded DESIGN, PLAN and IMPLEMENT as completed, rendered them
#      [DONE], and listed them as "Completed:" after a compaction.
#   C  a cancel removed the chain and left that signal behind, so the NEXT task inherited
#      the cancelled one's position and was told to request a code review on its second
#      prompt.
#
# The repair for D is a split, not a change of route: .completed is only what the Skill
# tool really returned for; what the walker infers goes to .assumed and renders [DONE?].
# WHICH step is mandated on each prompt is unchanged, and P1/P2 pin that schedule. The
# repair for C is that a cancel forgets the position too.
#
#   P*  the schedule, and which list a step lands in
#   R*  real Skill returns, through the REAL completion hook
#   X*  the cancel
#   G*  the push guard's answer, through the REAL guard: nothing here may move it
#   F*  a state file this hook did not write
#   V*  the compaction-recovery text
#
# Everything drives the real hooks in a throwaway HOME.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-activation-progress-truth.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
DONEHOOK="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
RENDER="${PROJECT_ROOT}/hooks/lib/compact-recovery-render.sh"
if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available — progress-truth cells NOT run"; exit 0
fi

setup_test_env
REG="${TEST_TMPDIR}/registry.json"
jq '.skills |= map(.available = true | .enabled = true)' "${PROJECT_ROOT}/config/default-triggers.json" > "${REG}"
TOK="session-t"
new_session() {
    H="${TEST_TMPDIR}/home-$1"; rm -rf "${H}"
    mkdir -p "${H}/.claude" && cp "${REG}" "${H}/.claude/.skill-registry-cache.json"
    TP="${H}/t.jsonl"; : > "${TP}"
    STATE="${H}/.claude/.skill-composition-state-${TOK}"
    SIGNAL="${H}/.claude/.skill-last-invoked-${TOK}"
    SCHED=""; LAST=""
}
# say <prompt>: one prompt through the real hook. Appends the mandated step to SCHED.
say() {
    LAST="$(jq -nc --arg p "$1" --arg t "${TP}" '{prompt:$p, transcript_path:$t}' \
        | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT=off /bin/bash "${HOOK}" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
    local m
    m="$(printf '%s' "${LAST}" | grep -oE '\[CURRENT\] Step [0-9]+: Skill\([^)]*\)' | head -1 | sed -E 's/.*Skill\((.*)\)/\1/; s/.*://')"
    SCHED="${SCHED}${m:--} "
}
# returned <skill>: the Skill tool really returned for it, through the real completion hook.
returned() {
    ( cd "${PROJECT_ROOT}" && jq -nc --arg t "${TP}" --arg s "$1" \
        '{transcript_path:$t, tool_name:"Skill", tool_input:{skill:$s}, tool_response:{is_error:false, content:"ok"}}' \
        | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" BRANCH_LEDGER_DIR="${H}/ledger" /bin/bash "${DONEHOOK}" >/dev/null 2>&1 )
}
completed() { jq -c '.completed // "<absent>"' "${STATE}" 2>/dev/null || echo "<no state>"; }
assumed()   { jq -c '.assumed // "<absent>"'   "${STATE}" 2>/dev/null || echo "<no state>"; }
marker()    { printf '%s' "${LAST}" | grep -oE "\[[A-Z?]+\] Step [0-9]+: Skill\([^)]*$1\)" | head -1 | sed -E 's/^\[([A-Z?]+)\].*/\1/'; }
BUILD="build a new exporter for the report module"

# --- P: the schedule, and where a step lands -----------------------------------------
echo "== P: bare replies =="
new_session p1
say "${BUILD}"; say ok; say ok; say ok; say ok; say ok; say ok
assert_equals "P1: the mandated step on each prompt is the schedule it always was" \
    "brainstorming brainstorming writing-plans writing-plans executing-plans executing-plans requesting-code-review " "${SCHED}"
assert_equals "P1 (the defect): six bare replies record NOTHING as completed" "[]" "$(completed)"
assert_equals "P1: what the walker walked past is held as assumed" '["brainstorming","writing-plans","executing-plans"]' "$(assumed)"
assert_equals "P1: a step nobody invoked renders [DONE?], never [DONE]" "DONE? DONE? DONE?" \
    "$(marker brainstorming) $(marker writing-plans) $(marker executing-plans)"
assert_not_contains "P1: and no [DONE] is claimed anywhere in the block" "[DONE]" "${LAST}"

new_session p2
say "review the PR diff for bugs"; say ok
assert_equals "P2: a prompt whose own words anchor at review mandates review, and again on a bare reply" \
    "requesting-code-review requesting-code-review " "${SCHED}"
assert_equals "P2: the steps before the anchor are assumed, not completed" '[] ["brainstorming","writing-plans","executing-plans"]' "$(completed) $(assumed)"
assert_equals "P2: neither list ever holds a gated step the walker inferred" "false" \
    "$(jq -r '((.completed + .assumed) | index("requesting-code-review") != null) or ((.completed + .assumed) | index("verification-before-completion") != null)' "${STATE}")"

# --- R: real Skill returns --------------------------------------------------------------
echo "== R: real Skill returns =="
new_session r1
say "${BUILD}"; returned superpowers:brainstorming; say ok
assert_equals "R1: a step that really returned is completed" '["brainstorming"]' "$(completed)"
assert_equals "R1: and is not also listed as assumed" "[]" "$(assumed)"
assert_equals "R1: it renders [DONE], and the walk has moved to the next step" "DONE brainstorming writing-plans " "$(marker brainstorming) ${SCHED}"
say ok
assert_equals "R1: the next bare reply repeats that step and confirms nothing new" '["brainstorming"]' "$(completed)"
say ok
assert_equals "R1: a step the walk then passes over without a return is assumed, beside the confirmed one" \
    '["brainstorming"] ["writing-plans"]' "$(completed) $(assumed)"
assert_equals "R1: and the two render differently in one block" "DONE DONE?" "$(marker brainstorming) $(marker writing-plans)"

new_session r2
say "${BUILD}"; returned superpowers:executing-plans; say ok; say ok
assert_equals "R2: a step invoked out of order is the only one completed" '["executing-plans"]' "$(completed)"
assert_equals "R2: the schedule is what it was before this change (it counts steps, it does not look for the first gap)" \
    "brainstorming writing-plans executing-plans " "${SCHED}"

# --- E: when the walk has ended ----------------------------------------------------------
# A second reader of the state decides whether a chain is still "live", which lets a short
# prompt past the hook's early exits. It compared the chain against .completed alone. Once
# the walker stopped writing there, a chain walked to its end stayed live for ever, and a
# four-letter prompt that used to be dropped was routed and mandated a step (found in
# review, measured: "ship" mandated verification-before-completion).
echo "== E: a chain walked to its end =="
new_session e1
say "${BUILD}"
for _s in brainstorming writing-plans executing-plans requesting-code-review verification-before-completion; do returned "superpowers:${_s}"; done
say ok; say ok; say ok; say ok
assert_equals "E1 setup: the walk has passed every step" "7 7" \
    "$(jq -r '"\(.chain | length) \([.chain[] as $s | select((.completed + .assumed) | index($s))] | length)"' "${STATE}")"
SCHED=""; say ok; say ship; say fix
assert_equals "E1: short prompts are dropped by the early exit again, as before the lists were split" "- - - " "${SCHED}"
assert_equals "E1: and the block is empty, not merely stepless" "" "${LAST}"
# Control: while steps remain, the same short prompt IS let through. Without this, "dropped"
# is equally true of a hook that drops every short prompt.
new_session e2
say "${BUILD}"; SCHED=""; say ok
assert_equals "E2 control: with steps left, a bare reply still reaches the chain" "brainstorming " "${SCHED}"

# --- X: cancel -----------------------------------------------------------------------------
echo "== X: cancel =="
new_session x1
say "${BUILD}"; say ok; say ok; say ok; say ok
assert_equals "X1 setup: the walk reached executing-plans" "executing-plans" "$(jq -r '.skill' "${SIGNAL}" 2>/dev/null)"
say cancel
if [ -e "${STATE}" ] || [ -e "${SIGNAL}" ]; then
    _record_fail "X1: a cancel removes the chain AND the position signal" "state: $([ -e "${STATE}" ] && echo present || echo gone), signal: $([ -e "${SIGNAL}" ] && echo present || echo gone)"
else
    _record_pass "X1: a cancel removes the chain AND the position signal"
fi
SCHED=""; say "build a login page for the admin area"; say ok; say ok
assert_equals "X1 (the defect): the next task starts at its first step and walks from there" \
    "brainstorming brainstorming writing-plans " "${SCHED}"
assert_equals "X1: and inherits nothing" '[] ["brainstorming"]' "$(completed) $(assumed)"
# Control: the same three prompts in a session with no history give the same schedule.
new_session x2
say "build a login page for the admin area"; say ok; say ok
assert_equals "X2 control: a session with no history walks the same way" "brainstorming brainstorming writing-plans " "${SCHED}"

# --- G: the push guard --------------------------------------------------------------------
# The guard reads .completed for the two gated steps only. The walker never wrote them and
# still does not; a real return still does; and nothing a later prompt does removes them.
echo "== G: the push guard's answer =="
gate() {
    ( cd "${PROJECT_ROOT}" && jq -nc --arg tp "${TP}" '{transcript_path:$tp, tool_input:{command:"git push origin HEAD"}}' \
        | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" BRANCH_LEDGER_DIR="${H}/ledger" /bin/bash "${GUARD}" 2>/dev/null )
}
seed_verdict() { jq -nc --arg s "$(git -C "${PROJECT_ROOT}" rev-parse HEAD)" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' > "${H}/.claude/.skill-project-verified-${TOK}"; }
new_session g1; seed_verdict
say "${BUILD}"; say ok; say ok; say ok; say ok; say ok; say ok; say ok
out="$(gate)"
assert_contains "G1: bare replies alone never satisfy the review gate" '"deny"' "${out:-<empty>}"
assert_contains "G1: and the denial is the chain's review step" "requesting-code-review" "${out:-<empty>}"

new_session g2; seed_verdict
say "${BUILD}"; returned superpowers:requesting-code-review; returned superpowers:verification-before-completion
say "review the PR diff for bugs"; say ok; say "${BUILD}"; say ok
assert_equals "G2: prompts that re-anchor earlier do not remove a real review or verification" \
    '["requesting-code-review","verification-before-completion"]' "$(completed)"
out="$(gate)"; _rc=$?
assert_equals "G2: the guard exited 0" "0" "${_rc}"
assert_not_contains "G2: and the push is allowed, as it was" '"deny"' "${out:-<empty>}"

# --- F: a state file this hook did not write ---------------------------------------------
echo "== F: foreign state =="
new_session f1
say "${BUILD}"
jq -c '.assumed = "brainstorming"' "${STATE}" > "${STATE}.x" && mv "${STATE}.x" "${STATE}"
SCHED=""; say ok
assert_equals "F1: an assumed list that is not a list injects nothing (fail open)" "- " "${SCHED}"
new_session f2
say "${BUILD}"
jq -c '.assumed = ["not-a-step"]' "${STATE}" > "${STATE}.x" && mv "${STATE}.x" "${STATE}"
SCHED=""; say ok
assert_equals "F2: an assumed step that is not in the chain injects nothing" "- " "${SCHED}"
new_session f3
say "${BUILD}"
jq -c 'del(.assumed) | .completed = ["brainstorming"]' "${STATE}" > "${STATE}.x" && mv "${STATE}.x" "${STATE}"
SCHED=""; say ok
assert_equals "F3: a state file written before this change (no assumed list) still walks" "writing-plans " "${SCHED}"
assert_equals "F3: and what it held as completed is carried forward, not dropped" '["brainstorming"]' "$(completed)"

# --- V: compaction recovery ---------------------------------------------------------------
echo "== V: compaction recovery text =="
new_session v1
say "${BUILD}"; returned superpowers:brainstorming; say ok; say ok; say ok
text="$(HOME="${H}" /bin/bash -c '. "$1"; for f in $(declare -F | awk "{print \$3}" | grep -i render); do "$f" "$2" 2>/dev/null; done' _ "${RENDER}" "${TOK}" 2>/dev/null)"
if [ -n "${text}" ]; then
    assert_contains "V1: recovery lists what really completed" "Completed: brainstorming" "${text}"
    assert_contains "V1: and what was only assumed, separately and labelled" "Assumed done, NOT invoked" "${text}"
    assert_contains "V1: naming the assumed step" "writing-plans" "$(printf '%s' "${text}" | grep -F 'Assumed done')"
else
    _record_fail "V1: the recovery renderer produced text" "no output from ${RENDER}"
fi

cd "${PROJECT_ROOT}" || true
teardown_test_env
print_summary

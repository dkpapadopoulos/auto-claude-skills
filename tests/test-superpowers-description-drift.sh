#!/usr/bin/env bash
# test-superpowers-description-drift.sh — the one-line descriptions this plugin shows for
# superpowers skills must not contradict what those skills now do.
#
# The descriptions in config/default-triggers.json are rendered into the routing block
# ("[LATER] Step 7: Skill(superpowers:finishing-a-development-branch) -- <description>") and
# into composition `purpose` lines, so a stale one tells the model something the skill it is
# about to invoke will contradict. Checked against superpowers 6.4.2 (2026-09-25), and these
# three re-checked against 7.0.1 (2026-10-26), where they still hold:
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
#       or README.md; and no eval in the composition-uptake fixture EXPECTS "4 options" (its
#       recorded prompts are frozen hook output and keep the old text — only what a judge
#       grades against is checked: expected_behavior and each assertion's criteria)
#   D2  the three descriptions state the current behaviour (positive needles, so D1 cannot be
#       satisfied by deleting the descriptions). They are deliberately no longer than the text
#       they replace: tests/test-injection-budget.sh ratchets what these cost every prompt.
#   D3  the fallback registry carries the same three descriptions as the default config
#   D4  ADVISORY, never a failure: when superpowers is installed on this machine, say whether
#       its text still matches the comment above. Upstream's wording is not under this repo's
#       control, and this suite is the push gate, so an upstream reword must not turn it red.
#       It prints UPSTREAM DRIFT or SKIPPED and counts as neither a pass nor a fail. It looks
#       in every marketplace under ~/.claude/plugins/cache/*/superpowers/ and reads the highest
#       version installed, so a superpowers installed from another marketplace is not missed.
#
# Checked against superpowers 7.0.1 (2026-10-26; openspec change superpowers-701-alignment).
# brainstorming's HARD-GATE ends "After the design doc is approved, the next step is the plan:
# invoke superpowers:writing-plans and no other skill", and writing-plans' handoff lets the
# user choose Subagent-driven or Native and saves to docs/superpowers/plans/ by default. Our
# text contradicted all three:
#   * the brainstorming precondition said to invoke agent-safety-review "before leaving
#     DESIGN" — after approval, where the backbone allows only writing-plans. It now says
#     before the design doc is approved, and before building when brainstorming ends with no
#     design doc (opt-out, or a quick, clear task), so the check does not lapse there. The
#     DESIGN EVAL STRATEGY hint (it names Skill(runtime-validation)) gets the same timing;
#   * the PLAN red flag demanded docs/plans/, so a correct superpowers run read as a violation;
#   * the IMPLEMENT red flag pushed subagent-driven-development / agent-team-execution over
#     the method the user chose at the handoff.
# And verification-before-completion's description promised "no TODOs, docs updated", which
# the skill does not say. D1-D3 cover those strings in both configs; R1-R3 are the openspec
# scenarios, asserted on the RENDERED red flags (the hook run under an isolated HOME), not on
# the hook source. D4 also watches the 7.0.1 phrases these edits rest on: brainstorming's
# "invoke superpowers:writing-plans and no other skill" and "Write the design doc";
# writing-plans' "User preferences for plan location override this default" and "Which
# execution approach"; subagent-driven-development's "Never dispatch multiple
# implementation subagents in parallel".
#   * the using-superpowers registry entry was deleted from both configs: it had no
#     triggers, keywords or composition reference, so no routing rule selected it, and
#     superpowers injects that skill itself at SessionStart. Session-start discovery still
#     lists it, as a triggerless "Discovered skill" like every other uncurated superpowers
#     skill. Measured before and after: only a prompt containing the literal name
#     "using-superpowers" selects it (the scorer's name boost), and that prompt now shows
#     Phase [IMPLEMENT] rather than [DESIGN], because a discovered entry has no phase.
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
EVAL="${PROJECT_ROOT}/tests/fixtures/composition-uptake/evals/behavioral.json"
PE_EVAL="${PROJECT_ROOT}/tests/fixtures/phase-enforcement/evals/behavioral.json"
# An unreadable file makes `grep -q` exit 2, which reads as "absent" — a pass on nothing.
for _f in "${CFG}" "${FB}" "${README}" "${EVAL}" "${PE_EVAL}"; do
    if [ ! -r "${_f}" ] || [ ! -s "${_f}" ]; then
        _record_fail "readable and non-empty: ${_f##*/}" "missing, unreadable or empty; every 'is absent' cell on it would pass vacuously"
        print_summary; exit 1
    fi
done
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
# What the judge is given: expected_behavior AND each assertion's criteria (its rubric).
_eval_expect="$(jq -r '[.. | objects | (.expected_behavior?, .criteria?) // empty | strings] | join("\n")' "${EVAL}" 2>/dev/null)"
if [ -n "${_eval_expect}" ]; then
    assert_not_contains "D1: no judged text in composition-uptake asks for '4 options'" "4 options" "${_eval_expect}"
    assert_not_contains "D1: no judged text in composition-uptake lists discard as an option" "keep/discard" "${_eval_expect}"
else
    _record_fail "D1: no judged text in composition-uptake asks for '4 options'" "no expected_behavior or criteria could be read from the fixture"
fi

desc() { jq -r --arg n "$2" '[.skills[] | select(.name == $n)][0].description // ""' "$1"; }
pre() { jq -r --arg n "$2" '[.skills[] | select(.name == $n)][0].precondition // ""' "$1"; }
# The DESIGN hint whose text starts with the label in $2 (first match; "" when absent).
hint() { jq -r --arg l "$2" '[.phase_compositions.DESIGN.hints[]?.text | strings | select(startswith($l))][0] // ""' "$1"; }

# D1 (7.0.1): stale text scoped to its FIELD, not the file. "before leaving DESIGN" is
# also in the DESIGN AUTONOMY CHECK hint, which designs oversight rather than invoking a
# skill and is out of this change's scope, so a file-level grep would fail on it. An empty
# field is a failure, never a pass: "absent from nothing" is the vacuous case.
for _f in "${CFG}" "${FB}"; do
    _p="$(pre "${_f}" brainstorming)"
    _v="$(desc "${_f}" verification-before-completion)"
    if [ -z "${_p}" ] || [ -z "${_v}" ]; then
        _record_fail "D1: brainstorming precondition and verification description readable in ${_f##*/}" "one is empty; the 'is absent' cells would pass vacuously"
        continue
    fi
    assert_not_contains "D1: brainstorming precondition in ${_f##*/} does not say 'before leaving DESIGN'" "before leaving DESIGN" "${_p}"
    assert_not_contains "D1: verification-before-completion in ${_f##*/} does not promise 'no TODOs, docs updated'" "no TODOs, docs updated" "${_v}"
    # EVAL STRATEGY names Skill(runtime-validation) on every DESIGN render, so its timing is
    # the same contradiction as the trifecta's. Case-insensitive: it once opened "Before".
    _e="$(hint "${_f}" "EVAL STRATEGY:")"
    if [ -z "${_e}" ]; then
        _record_fail "D1: EVAL STRATEGY hint readable in ${_f##*/}" "empty; the 'is absent' cell would pass vacuously"
    elif printf '%s' "${_e}" | grep -qiF 'before leaving DESIGN'; then
        _record_fail "D1: EVAL STRATEGY hint in ${_f##*/} does not say 'before leaving DESIGN'" "still present"
    else
        _record_pass "D1: EVAL STRATEGY hint in ${_f##*/} does not say 'before leaving DESIGN'"
    fi
done
# The phase-enforcement eval's prompts are frozen hook output and keep "before leaving
# DESIGN"; its criteria describe that frozen context and pass on the invocation alone. Only
# expected_behavior asked for the stale timing, so only it is held here.
_pe_expect="$(jq -r '[.[] | .expected_behavior? // empty | strings] | join("\n")' "${PE_EVAL}" 2>/dev/null)"
if [ -n "${_pe_expect}" ]; then
    assert_not_contains "D1: no expected_behavior in phase-enforcement asks for the invocation 'before leaving DESIGN'" "before leaving DESIGN" "${_pe_expect}"
else
    _record_fail "D1: no expected_behavior in phase-enforcement asks for the invocation 'before leaving DESIGN'" "no expected_behavior could be read from the fixture"
fi

# D2: positive needles.
assert_contains "D2: finishing names the three menu options" "(merge local, create PR, keep branch)" "$(desc "${CFG}" finishing-a-development-branch)"
assert_not_contains "D2: finishing does not list discard as a menu option" "discard" "$(desc "${CFG}" finishing-a-development-branch)"
assert_not_contains "D2: finishing does not promise worktree cleanup (PR and keep preserve it)" "clean up worktree" "$(desc "${CFG}" finishing-a-development-branch)"
assert_contains "D2: executing-plans describes inline execution" "Inline execution" "$(desc "${CFG}" executing-plans)"
assert_contains "D2: executing-plans names the whole-branch review" "whole-branch review" "$(desc "${CFG}" executing-plans)"
assert_contains "D2: subagent-driven-development names the whole-branch review" "whole-branch review" "$(desc "${CFG}" subagent-driven-development)"
_p="$(pre "${CFG}" brainstorming)"
# One sentence on purpose: "it" in "before it is approved" can only be the design doc.
assert_contains "D2: the design doc carries the trifecta classification, from its data flow" \
    "TRIFECTA: the design doc classifies private_data / untrusted_input / outbound_action from its data flow;" "${_p}"
assert_contains "D2: agent-safety-review is invoked before the design doc is approved" \
    "; if >=2 are Present (or Unknowns could reach 2), invoke Skill(auto-claude-skills:agent-safety-review) before it is approved (no design doc: classify and invoke before building), or record the skip:" "${_p}"
# brainstorming 7.0.1 also ends with NO design doc (the "just dive in" opt-out, the quick,
# clear task path). Without this clause "before it is approved" never comes and the check
# lapses. It names BOTH acts: with no doc, the classification's stated home is gone too.
assert_contains "D2: with no design doc, the trifecta is classified and agent-safety-review invoked before building" \
    "(no design doc: classify and invoke before building)" "${_p}"
assert_contains "D2: EVAL STRATEGY classifies verification before design-doc approval, or before building with no doc" \
    "EVAL STRATEGY: classify verification before design-doc approval (no doc: before building);" "$(hint "${CFG}" "EVAL STRATEGY:")"
assert_contains "D2: the skip remedy and its {{PLUGIN_ROOT}} placeholder are unchanged" \
    "or record the skip: source '{{PLUGIN_ROOT}}/hooks/lib/phase-attest.sh'; phase_attest agent-safety-review \"<why the trifecta is <2>\"." "${_p}"
assert_contains "D2: the product-discovery clause is unchanged" \
    "PRECONDITION: if this is a new feature or initiative and no discovery brief with an Assumption Ledger exists (check session-state discovery_path or docs/plans/*-discovery.md), invoke Skill(auto-claude-skills:product-discovery) FIRST to surface and grade the load-bearing assumptions, then return to brainstorming. Skip for bugfixes, small changes, or work already covered by an approved brief. TRIFECTA:" "${_p}"
assert_contains "D2: verification-before-completion says what the skill does" \
    "Run the verification command fresh and read its output before any success claim." "$(desc "${CFG}" verification-before-completion)"

# D3: the fallback copy matches.
for _n in finishing-a-development-branch executing-plans subagent-driven-development verification-before-completion; do
    assert_equals "D3: fallback-registry.json has the same description for ${_n}" "$(desc "${CFG}" "${_n}")" "$(desc "${FB}" "${_n}")"
done
assert_equals "D3: fallback-registry.json has the same brainstorming precondition" "$(pre "${CFG}" brainstorming)" "$(pre "${FB}" brainstorming)"
assert_equals "D3: fallback-registry.json has the same EVAL STRATEGY hint" "$(hint "${CFG}" "EVAL STRATEGY:")" "$(hint "${FB}" "EVAL STRATEGY:")"
# The dead using-superpowers entry stays deleted. Counted with jq rather than grepped, so an
# unparseable config reads as -1 and fails instead of reading as "absent".
for _f in "${CFG}" "${FB}"; do
    _n="$(jq '[.skills[] | select(.name == "using-superpowers")] | length' "${_f}" 2>/dev/null)"
    assert_equals "D3: ${_f##*/} carries no using-superpowers entry" "0" "${_n:--1}"
done

# D4: upstream, when present — advisory only. Highest version by numeric fields across every
# marketplace; `sort -V` is not assumed. On a tie the first marketplace in glob order wins.
SP_DIR=""
_best_key=""
for _d in "${HOME:-/nonexistent}"/.claude/plugins/cache/*/superpowers/*/skills; do
    [ -d "${_d}" ] || continue
    _v="${_d%/skills}"; _v="${_v##*/}"
    _key="$(printf '%s' "${_v}" | awk -F. '{ printf "%08d%08d%08d", $1 + 0, $2 + 0, $3 + 0 }')"
    if [ -z "${_best_key}" ] || [ "${_key}" \> "${_best_key}" ]; then
        _best_key="${_key}"; SP_DIR="${_d}"
    fi
done
if [ -z "${SP_DIR}" ]; then
    echo "  SKIPPED: D4 — superpowers not found under ~/.claude/plugins/cache/*/superpowers/; upstream text was not checked"
else
    _drift=""
    grep -q 'present exactly these 3 options' "${SP_DIR}/finishing-a-development-branch/SKILL.md" 2>/dev/null \
        || _drift="${_drift} finishing-a-development-branch(3-option menu)"
    grep -q 'whole-branch review' "${SP_DIR}/subagent-driven-development/SKILL.md" 2>/dev/null \
        || _drift="${_drift} subagent-driven-development(whole-branch review)"
    grep -q 'inline execution' "${SP_DIR}/executing-plans/SKILL.md" 2>/dev/null \
        || _drift="${_drift} executing-plans(inline execution)"
    # 7.0.1 wraps this sentence across lines, so whitespace is collapsed before matching.
    tr -s ' \n' '  ' < "${SP_DIR}/brainstorming/SKILL.md" 2>/dev/null \
        | grep -qF 'invoke superpowers:writing-plans and no other skill' \
        || _drift="${_drift} brainstorming(writing-plans and no other skill)"
    grep -qF 'Write the design doc' "${SP_DIR}/brainstorming/SKILL.md" 2>/dev/null \
        || _drift="${_drift} brainstorming(Write the design doc)"
    # What the PLAN and IMPLEMENT red flags rest on: the plan's location is the user's to
    # choose, the user picks the execution method at the handoff, and SDD never runs
    # implementers in parallel. Whitespace-collapsed, so an upstream rewrap is not drift.
    _sp_has() { tr -s ' \n' '  ' < "${SP_DIR}/$1/SKILL.md" 2>/dev/null | grep -qF -- "$2"; }
    _sp_has writing-plans 'User preferences for plan location override this default' \
        || _drift="${_drift} writing-plans(plan location is a user preference)"
    _sp_has writing-plans 'Which execution approach' \
        || _drift="${_drift} writing-plans(user chooses the execution approach)"
    _sp_has subagent-driven-development 'Never dispatch multiple implementation subagents in parallel' \
        || _drift="${_drift} subagent-driven-development(no parallel implementers)"
    if [ -z "${_drift}" ]; then
        echo "  NOTE: D4 — upstream ${SP_DIR%/skills} still says what these descriptions assume"
    else
        echo "  UPSTREAM DRIFT (advisory, not a failure): ${SP_DIR%/skills} no longer matches for:${_drift} — re-read it and update the descriptions and this file"
    fi
fi

# R1-R3: the openspec scenarios, on the RENDERED red flags. After D4 on purpose:
# setup_test_env repoints HOME, and D4 reads the real plugin cache.
#
# Registry: the shipped default config with every skill available, so the real triggers
# route DESIGN and IMPLEMENT. writing-plans ships with no trigger (it is reached by
# chain), so it gets one probe-only trigger here; the PLAN red flags depend only on the
# phase the hook settles on, which the "Phase: [PLAN]" cell checks. Each run takes its
# own transcript_path, so no state carries from one render to the next.
setup_test_env
mkdir -p "${HOME}/.claude"
jq '(.skills = [.skills[] | .available = true | .enabled = true])
    | (.skills |= map(if .name == "writing-plans" then .triggers = ["(zzplanprobe)"] else . end))' \
    "${CFG}" > "${HOME}/.claude/.skill-registry-cache.json"

_render() {   # prompt tag -> additionalContext
    local _tp="${TEST_TMPDIR}/$2.jsonl"
    : > "${_tp}"
    jq -n --arg p "$1" --arg t "${_tp}" '{prompt:$p, transcript_path:$t}' \
        | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${TEST_TMPDIR}" \
          bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}
# Only the "- " lines directly under a "HALT if any Red Flag is true:" header. Hints
# rendered elsewhere in the same output name docs/plans/ too, and they are not red flags.
_flags() { printf '%s\n' "$1" | awk '/^HALT if any Red Flag is true:$/ { f = 1; next } f && /^- / { print; next } { f = 0 }'; }

_ctx="$(_render "let's build a new caching layer for the API" design)"
assert_contains "R1: the DESIGN prompt renders the DESIGN phase" "Phase: [DESIGN]" "${_ctx}"
assert_equals "R1: DESIGN red flags are only the routing obligation" \
    "- Editing implementation files before invoking Skill(superpowers:brainstorming)" "$(_flags "${_ctx}")"

_ctx="$(_render "zzplanprobe the work" plan)"
_rf="$(_flags "${_ctx}")"
assert_contains "R2: the PLAN prompt renders the PLAN phase" "Phase: [PLAN]" "${_ctx}"
if [ -z "${_rf}" ]; then
    _record_fail "R2: PLAN red flags rendered" "no red-flag lines; the 'names no directory' cell would pass vacuously"
else
    assert_not_contains "R2: no PLAN red flag names docs/plans/" "docs/plans/" "${_rf}"
    assert_contains "R2: the PLAN red flag requires the approved plan saved to a file" \
        "- Executing before the approved plan is saved to a file" "${_rf}"
fi

_ctx="$(_render "continue with the next task in the plan" implement)"
_rf="$(_flags "${_ctx}")"
assert_contains "R3: the IMPLEMENT prompt renders the IMPLEMENT phase" "Phase: [IMPLEMENT]" "${_ctx}"
if [ -z "${_rf}" ]; then
    _record_fail "R3: IMPLEMENT red flags rendered" "no red-flag lines; the 'is not required' cells would pass vacuously"
else
    assert_not_contains "R3: no IMPLEMENT red flag requires subagent-driven-development" "subagent-driven-development" "${_rf}"
    assert_not_contains "R3: no IMPLEMENT red flag requires agent-team-execution" "agent-team-execution" "${_rf}"
    assert_contains "R3: the IMPLEMENT red flag defers to the method chosen at the plan handoff" \
        "- Not using the execution method the user chose at the plan handoff" "${_rf}"
fi
teardown_test_env

print_summary

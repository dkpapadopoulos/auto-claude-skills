#!/usr/bin/env bash
# Content + routing assertions for skills/second-opinion/ (contract C1).
#
# The content half checks the guidance says the right thing. It is NOT evidence that the
# contract holds at runtime -- participant count and payload contents are assembled by
# the model, so a markdown assertion cannot establish them, and the spec forbids offering
# one as if it could. The routing half drives the REAL hook, because the panel boundary
# is resolved by score and no regex fixture can express that.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-second-opinion-content.sh ==="

SKILL="${PROJECT_ROOT}/skills/second-opinion/SKILL.md"
assert_equals "skills/second-opinion/SKILL.md exists" "true" \
    "$([ -f "${SKILL}" ] && echo true || echo false)"

# Assert on the BODY, never the whole file. The frontmatter `description:` already
# contains "independent", "critique", "panel" and "design-debate", so a whole-file needle
# for any of those passes against a file whose body was deleted entirely -- measured: a
# frontmatter-only file passed 12 of 22 assertions in an earlier version of this test.
body="$(awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{f=0; next} !f' "${SKILL}" 2>/dev/null || true)"

# --- the outbound-data controls: the reason the first attempt was reverted ----------
# This skill performs a cross-family dispatch. Moving that intent here WITHOUT these was
# a security regression: repo content to another vendor, no secret scan, and a mechanism
# that defaults to write-capable.
assert_contains "carries the disclosure preview"        "Disclosure preview"        "${body}"
assert_contains "names the destination provider"        "destination provider"      "${body}"
assert_contains "runs secret detection on the payload"  "gitleaks"                  "${body}"
assert_contains "announces when gitleaks is unavailable" "rather than proceeding silently" "${body}"
assert_contains "dispatch is read-only"                 "read-only"                 "${body}"
assert_contains "says why read-only must be explicit"   "write-capable"             "${body}"
assert_contains "scratch dir is non-predictable"        "mktemp -d"                 "${body}"
assert_contains "scratch dir is private"                "chmod 0700"                "${body}"
assert_contains "probes availability at dispatch"       "probed at dispatch, never assumed" "${body}"

# --- the two modes, and the property that distinguishes them -----------------------
assert_contains "independent mode withholds the prior answer" "NOT your prior answer" "${body}"
assert_contains "critique mode includes it deliberately"      "PLUS the specific prior answer" "${body}"
assert_contains "the preview states the mode"                 "State the MODE"        "${body}"

# --- exclusion is about effective context, not the prompt string --------------------
assert_contains "exclusion is about effective context" "effective context" "${body}"
assert_contains "names conversation forking as a leak" "forking"           "${body}"
assert_contains "names a leading summary as a leak"    "leading summary"   "${body}"
assert_contains "claims withheld, not independent judgement" \
    "prior answer was withheld" "${body}"

# --- multi-model belongs to panel, stated as a precondition ------------------------
assert_contains "hands multi-model off to panel" "named more than one model" "${body}"

# --- the assurance boundary --------------------------------------------------------
assert_contains "selection is not guaranteed"  "does not make the wrong one unreachable" "${body}"
assert_contains "the file is not a mechanism"  "instruction, not a mechanism"            "${body}"
assert_contains "forbids citing the file as evidence" "never from the presence"          "${body}"

# --- registry wiring, and panel narrowed on BOTH surfaces --------------------------
if command -v jq >/dev/null 2>&1; then
    for reg in config/default-triggers.json config/fallback-registry.json; do
        f="${PROJECT_ROOT}/${reg}"
        assert_equals "${reg} registers second-opinion" "true" \
            "$(jq -e '[.skills[] | select(.name=="second-opinion")] | length == 1' "$f" >/dev/null 2>&1 && echo true || echo false)"
        assert_equals "${reg} panel keeps multi-model reach" "true" \
            "$(jq -e '[.skills[] | select(.name=="panel") | .triggers[] | select(test("and\\|,"))] | length >= 1' "$f" >/dev/null 2>&1 && echo true || echo false)"
    done
fi
# The MODEL-VISIBLE description is the SKILL.md frontmatter, not the registry: the roster
# the model chooses from is built from frontmatter. Asserting the narrowing against the
# registry alone reports the requirement as covered while checking the surface that was
# never the problem -- the audit's failure was the model picking panel WITHOUT being
# routed there.
panel_fm="$(awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{exit} f' "${PROJECT_ROOT}/skills/panel/SKILL.md" 2>/dev/null || true)"
assert_contains "panel FRONTMATTER says SEVERAL models"      "SEVERAL"        "${panel_fm}"
assert_contains "panel FRONTMATTER points at second-opinion" "second-opinion" "${panel_fm}"

# --- routing: the boundary a regex fixture cannot express --------------------------
if command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    _route() {
        local h; h="$(mktemp -d)"; mkdir -p "$h/.claude"
        python3 - "${PROJECT_ROOT}" "$h" <<'PY'
import json, sys
reg = json.load(open(sys.argv[1] + "/config/default-triggers.json"))
for s in reg["skills"]:
    s.update(available=True, enabled=True)
open(sys.argv[2] + "/.claude/.skill-registry-cache.json", "w").write(json.dumps(reg))
PY
        jq -nc --arg p "$1" --arg t "$h/.claude/a.jsonl" '{prompt:$p, transcript_path:$t}' \
        | HOME="$h" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" 2>/dev/null \
        | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
        rm -rf "$h"
    }
    # A single-model request must reach this skill and NOT panel.
    out="$(_route "consult codex about the schema change")"
    assert_contains     "single-model request routes to second-opinion" "second-opinion" "${out:-<empty>}"
    assert_not_contains "single-model request does NOT reach panel"     "auto-claude-skills:panel)" "${out:-<empty>}"
    # An explicit multi-model request must reach panel. The trigger matches BOTH skills
    # (no lookahead can reject a participant list); panel wins on score.
    # PRECEDENCE, not presence. Both skills match this prompt (no lookahead can reject a
    # participant list), and the domain cap is 2, so a presence check passes even when
    # second-opinion is ranked FIRST -- which is what happened: panel scored 28 against
    # 47 and was rendered second, one competing skill away from eviction. Assert panel
    # appears BEFORE second-opinion in the rendered block.
    out="$(_route "ask codex, gemini and gpt-5 each for their take on this design")"
    assert_contains "explicit multi-model request still reaches panel" "auto-claude-skills:panel)" "${out:-<empty>}"
    _pan_pos="$(printf '%s' "${out}" | grep -n "auto-claude-skills:panel)" | head -1 | cut -d: -f1)"
    _so_pos="$(printf '%s' "${out}" | grep -n "auto-claude-skills:second-opinion)" | head -1 | cut -d: -f1)"
    if [ -n "${_pan_pos}" ] && [ -n "${_so_pos}" ] && [ "${_pan_pos}" -lt "${_so_pos}" ]; then
        _record_pass "panel OUTRANKS second-opinion on a multi-model request"
    elif [ -n "${_pan_pos}" ] && [ -z "${_so_pos}" ]; then
        _record_pass "panel OUTRANKS second-opinion on a multi-model request (sole)"
    else
        _record_fail "panel OUTRANKS second-opinion on a multi-model request" \
            "panel at line ${_pan_pos:-none}, second-opinion at ${_so_pos:-none}"
    fi
    # Ordinary review language must reach neither: this skill ships content off-machine.
    out="$(_route "please critique my approach to caching")"
    assert_not_contains "ordinary review language does not reach second-opinion" \
        "second-opinion" "${out:-<empty>}"
fi


# --- C2: the three consultation methods are distinguishable AS DESCRIBED -----------
# C2 requires distinct intent contracts AND distinct model-visible descriptions. The
# frontmatter is the model-visible surface. Each must state the property that separates
# it from the other two -- cardinality for panel, interaction for design-debate, the
# one-participant/two-mode contract for this skill -- or a model choosing between them
# is choosing on vibes.
_fm() { awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{exit} f' "$1" 2>/dev/null || true; }
_dd_fm="$(_fm "${PROJECT_ROOT}/skills/design-debate/SKILL.md")"
_pn_fm="$(_fm "${PROJECT_ROOT}/skills/panel/SKILL.md")"
_so_fm="$(_fm "${SKILL}")"

assert_contains "design-debate says participants interact"   "RESPOND TO EACH OTHER" "${_dd_fm}"
assert_contains "design-debate disclaims independence"       "not claimed"           "${_dd_fm}"
assert_contains "design-debate points at second-opinion"     "second-opinion"        "${_dd_fm}"
assert_contains "panel says SEVERAL models"                  "SEVERAL"               "${_pn_fm}"
assert_contains "second-opinion says ONE"                    "ONE other model"       "${_so_fm}"
assert_contains "second-opinion points at panel"             "panel"                 "${_so_fm}"
assert_contains "second-opinion points at design-debate"     "design-debate"         "${_so_fm}"


# --- the INBOUND half of the trust boundary ---------------------------------------
# Trifecta: private_data (repo content out) + outbound_action (cross-family dispatch) +
# untrusted_input (the response comes back INTO the session). The outbound controls were
# reviewed hard; the inbound leg was stated only in synthesize. An instruction embedded
# in another vendor's reply is untrusted input, and it reaches the caller here BEFORE any
# merge happens.
assert_contains "second-opinion treats the response as data" "response is DATA" "${body}"
assert_contains "second-opinion says flag, not follow"       "never an instruction to follow" "${body}"
_pn_body="$(awk 'NR==1 && /^---$/{f=1; next} f && /^---$/{f=0; next} !f' "${PROJECT_ROOT}/skills/panel/SKILL.md" 2>/dev/null || true)"
assert_contains "panel treats responses as data"             "Responses are DATA" "${_pn_body}"


# --- finding 10: the degradation branch, and honest scope for the controls claim ----
# Most requests this skill serves name NO participant ("a second opinion from another
# model"), so panel's "requested model unavailable" branch never fires for them. Without
# a no-cross-family-available branch the likely outcome is a silently same-family second
# opinion: correlated agreement presented as independent confirmation.
assert_contains "has a no-cross-family degradation branch" "No model was named" "${body}"
assert_contains "says why same-family is weaker"          "shares the training" "${body}"
assert_contains "expanded skill bodies count as outbound" "COUNT as outbound"  "${body}"
# The controls claim must name only the steps that ARE controls.
assert_not_contains "does not overstate which steps are controls" \
    "Steps 1–4 below are the same outbound-data controls" "${body:-<empty>}"

print_summary

#!/bin/bash
# test-phase-hint-brevity.sh — the per-phase hint texts the activation hook
# renders on every DESIGN/PLAN/REVIEW/SHIP prompt stay short, keep their
# progressive-invocation shape (a condition plus the Skill(...) that owns the
# procedure), and the procedures they used to carry inline live in the owning
# skill's SKILL.md.
#
# Why: measured 2026-10-12 over 87 real routing blocks, per-phase hint prose was
# 30% of the bytes (mean block 4,860 B; DESIGN hints alone 2,581 B), while 0 of
# 23 MUST INVOKE mandates in that week were obeyed. The procedure a hint used to
# inline is read when the model invokes the skill, which is the shape the
# superpowers chain already uses. The per-phase totals are CEILINGS: growth
# fails and needs a reason in the commit that raises the constant; a reduction
# passes and the constant is lowered when someone next touches the file. They
# were equality ratchets from PR #349 until the ratchet-ceilings change; the
# 2026-10-12 value review found the equality pins on INTERNAL counts taxing
# later PRs with re-pins for numbers no user sees (the fork count was re-pinned
# by PR #351 hours after PR #348 introduced it; the injection baseline moved
# five times across #349 and #350). These pins themselves moved only within
# #349, so this conversion is prospective: same shape, same tax expected. The
# two totals a user pays stay equality ratchets: the injection budget
# (_INJECTION_BASELINE, every prompt) and the instruction-file total
# (_COMBINED_BASELINE, every session start).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CFG="${PROJECT_ROOT}/config/default-triggers.json"
FALLBACK="${PROJECT_ROOT}/config/fallback-registry.json"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-phase-hint-brevity.sh ==="

# Per-hint ceiling. 480 rather than the spec's first draft of 240: the
# spec-driven PERSIST DESIGN hint carries the three-file layout the model must
# reproduce, and that list IS the content. Everything else sits well under it.
_HINT_MAX=480
# Per-phase sums (bytes), default preset: CEILINGS set at the measured totals
# after the cut (before: DESIGN 2581, REVIEW 1307, PLAN 1118, SHIP 895).
# Growth fails; raise a constant only in the commit that grows the text and say
# why. A reduction passes; lower the constant when convenient.
_DESIGN_PIN=1465
_REVIEW_PIN=666
_PLAN_PIN=750
_SHIP_PIN=720
# DISCOVER, DEBUG and LEARN too: no MEASURE shape in test-injection-budget.sh
# is a DISCOVER prompt, so without a pin PERSIST DISCOVERY could regrow to the
# ceiling unseen (review finding).
_DISCOVER_PIN=328
_DEBUG_PIN=436
_LEARN_PIN=241

_bytes() { ( LC_ALL=C LANG=C; printf '%s' "${#1}" ); }

# --- 1. every hint text is under the ceiling and names a Skill ---------------
_n=0; _over=0; _noskill=0; _report=""
while IFS=$'\x1f' read -r _phase _idx _text; do
    [ -z "${_phase}" ] && continue
    _n=$((_n + 1))
    _b="$(_bytes "${_text}")"
    if [ "${_b}" -gt "${_HINT_MAX}" ]; then
        _over=$((_over + 1)); _report="${_report}
      ${_phase}[${_idx}] ${_b}B > ${_HINT_MAX}: ${_text:0:60}..."
    fi
    # A hint long enough to be a procedure must delegate to the skill that owns
    # it. Short contract and plugin hints (a reminder, a one-line rule) may
    # name nothing; 300 bytes separates the two populations in this config.
    if [ "${_b}" -ge 300 ]; then
        case "${_text}" in
            *"Skill("*|*"{{PLUGIN_ROOT}}"*) ;;
            *) _noskill=$((_noskill + 1)); _report="${_report}
      ${_phase}[${_idx}] ${_b}B and names no Skill(...) or plugin script: ${_text:0:60}..." ;;
        esac
    fi
done <<EOF
$(jq -r '.phase_compositions | to_entries[] | .key as $p | (.value.hints // []) | to_entries[] | [$p, (.key|tostring), .value.text] | join("\u001f")' "${CFG}" 2>/dev/null)
EOF
if [ "${_n}" -ge 20 ]; then
    _record_pass "hint floor: ${_n} phase hints read from config (>= 20)"
else
    _record_fail "hint floor" "only ${_n} hints read -- the config path or shape changed, so the cells below checked nothing"
fi
if [ "${_over}" -eq 0 ]; then
    _record_pass "every phase hint is <= ${_HINT_MAX} bytes"
else
    _record_fail "hint ceiling" "${_over} hint(s) over ${_HINT_MAX} bytes:${_report}"
fi
if [ "${_noskill}" -eq 0 ]; then
    _record_pass "every phase hint names the Skill(...) or command that owns its procedure (progressive invocation kept)"
else
    _record_fail "progressive invocation" "${_noskill} hint(s) name no Skill(...) or command:${_report}"
fi

# --- 2. per-phase sums --------------------------------------------------------
# utf8bytelength, not length: `length` counts codepoints and the arrow in
# DESIGN→PLAN is three bytes (review finding; the per-hint cell already counted
# bytes, so the two cells disagreed by 6 on DESIGN).
_sum() { jq -r --arg p "$1" '[.phase_compositions[$p].hints[]?.text | utf8bytelength] | add // 0' "${CFG}" 2>/dev/null; }
for _pair in "DESIGN:${_DESIGN_PIN}" "REVIEW:${_REVIEW_PIN}" "PLAN:${_PLAN_PIN}" "SHIP:${_SHIP_PIN}" \
             "DISCOVER:${_DISCOVER_PIN}" "DEBUG:${_DEBUG_PIN}" "LEARN:${_LEARN_PIN}"; do
    _p="${_pair%%:*}"; _pin="${_pair#*:}"
    _s="$(_sum "${_p}")"
    case "${_s}" in ''|*[!0-9]*) _s=-1 ;; esac
    if [ "${_s}" -lt 0 ]; then
        _record_fail "${_p} hint total" "could not sum the hint bytes for ${_p}"
    elif [ "${_s}" -eq 0 ]; then
        # A ceiling lets a reduction pass; a phase summing to ZERO is not a reduction but a
        # vanished phase (hints deleted, or the phase key renamed so `add // 0` saw nothing).
        _record_fail "${_p} hint total" "no hint text found for ${_p}: a phase at zero bytes is a vanished phase or a renamed key, not a reduction"
    elif [ "${_s}" -le "${_pin}" ]; then
        _record_pass "${_p} hints total ${_s} bytes (ceiling ${_pin})"
    else
        _record_fail "${_p} hint total" "grew to ${_s} bytes over the ${_pin} ceiling (+$((_s - _pin))). This text reaches every ${_p}-phase prompt in every installing repo. Shorten it, or raise the ceiling in the SAME commit and say why."
    fi
done

# --- 3. pinned phrases other tests rely on survive the cut --------------------
_cfg_text="$(jq -r '[.phase_compositions[].hints[]?.text] | join("\n")' "${CFG}")"
for _needle in "EVAL STRATEGY" "AUTONOMY CHECK" "ADVERSARIAL REVIEW" "PERSIST DESIGN" "PERSIST DISCOVERY" \
               "ask the user if" "adversarial/safety subsets" "failing (red) before implementation" \
               'REVIEW runs `{{PLUGIN_ROOT}}/scripts/scope-conformance.sh`'; do
    if printf '%s' "${_cfg_text}" | grep -qF -- "${_needle}"; then
        _record_pass "pinned phrase kept: ${_needle}"
    else
        _record_fail "pinned phrase" "'${_needle}' no longer appears in any phase hint; another test asserts it"
    fi
done

# --- 4. the moved procedures live in the owning skills ------------------------
for _pair in "runtime-validation:## Eval strategy at DESIGN" \
             "agent-safety-review:## Autonomy levels" \
             "agent-team-review:## Adversarial review checklist"; do
    _skill="${_pair%%:*}"; _heading="${_pair#*:}"
    if grep -qF -- "${_heading}" "${PROJECT_ROOT}/skills/${_skill}/SKILL.md" 2>/dev/null; then
        _record_pass "procedure moved: skills/${_skill}/SKILL.md has '${_heading}'"
    else
        _record_fail "procedure moved" "skills/${_skill}/SKILL.md lacks '${_heading}' -- the hint points at a procedure that is not there"
    fi
done
# and each hint points at its owner
for _pair in "EVAL STRATEGY:runtime-validation" "AUTONOMY CHECK:agent-safety-review" "ADVERSARIAL REVIEW:agent-team-review"; do
    _label="${_pair%%:*}"; _owner="${_pair#*:}"
    if printf '%s' "${_cfg_text}" | grep -F -- "${_label}" | grep -qF -- "Skill(auto-claude-skills:${_owner})"; then
        _record_pass "${_label} hint names Skill(auto-claude-skills:${_owner})"
    else
        _record_fail "${_label} owner" "the hint does not name Skill(auto-claude-skills:${_owner})"
    fi
done

# --- 5. the spec-driven rewrite in session-start obeys the same ceiling -------
# The preset rewrites three DESIGN/PLAN hints inside a jq heredoc; a config lint
# cannot see them. Render through the real hook under the spec-driven preset.
setup_test_env
mkdir -p "${HOME}/.claude"
printf '%s\n' '{"preset":"spec-driven"}' > "${HOME}/.claude/skill-config.json"
CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 bash "${HOOK}" >/dev/null 2>&1 < /dev/null
_sd_over="$(jq -r --argjson max "${_HINT_MAX}" '[.phase_compositions.DESIGN.hints[]?, .phase_compositions.PLAN.hints[]? | .text | select(length > $max)] | length' "${HOME}/.claude/.skill-registry-cache.json" 2>/dev/null)"
_sd_seen="$(jq -r '[.phase_compositions.DESIGN.hints[]?.text | select(test("spec-driven"))] | length' "${HOME}/.claude/.skill-registry-cache.json" 2>/dev/null)"
case "${_sd_seen}" in ''|*[!0-9]*) _sd_seen=0 ;; esac
if [ "${_sd_seen}" -ge 2 ]; then
    _record_pass "spec-driven preset applied: ${_sd_seen} rewritten DESIGN hints seen"
else
    _record_fail "spec-driven preset" "expected >= 2 rewritten DESIGN hints in the registry, saw ${_sd_seen} -- the preset did not take effect, so the ceiling below checked nothing"
fi
if [ "${_sd_over}" = "0" ]; then
    _record_pass "spec-driven rewrites stay <= ${_HINT_MAX} bytes"
else
    _record_fail "spec-driven ceiling" "${_sd_over} rewritten hint(s) over ${_HINT_MAX} bytes"
fi
# The owner rule applies to the rewritten hints too, not only the config's (review finding).
_sd_noowner="$(jq -r '[.phase_compositions.DESIGN.hints[]?, .phase_compositions.PLAN.hints[]? | .text | select(utf8bytelength >= 300) | select((contains("Skill(") or contains("{{PLUGIN_ROOT}}")) | not)] | length' "${HOME}/.claude/.skill-registry-cache.json" 2>/dev/null)"
if [ "${_sd_noowner}" = "0" ]; then
    _record_pass "spec-driven rewrites of 300+ bytes name a Skill(...) or plugin script"
else
    _record_fail "spec-driven owner rule" "${_sd_noowner} rewritten hint(s) of 300+ bytes name no owner"
fi
teardown_test_env

# --- 6. fallback registry mirrors the config hints --------------------------
if diff <(jq -S '.phase_compositions' "${CFG}") <(jq -S '.phase_compositions' "${FALLBACK}") >/dev/null 2>&1; then
    _record_pass "fallback-registry.json carries the same phase hints as default-triggers.json"
else
    _record_fail "fallback mirror" "config/fallback-registry.json phase_compositions differ from default-triggers.json -- regenerate it (run the session-start hook once without _SKILL_TEST_MODE) and commit"
fi

print_summary

#!/bin/bash
# test-phase-hint-brevity.sh — the shipped phase compositions carry NO hint prose.
#
# This file used to pin per-phase byte ceilings and a 480-byte per-hint rule for the
# 23 hints `phase_compositions[*].hints` shipped with. Those hints were removed by
# openspec/changes/registered-hint-cut: the in-turn compliance census
# (tests/probes/compliance-census/README.md) registered, before its data, that a
# "no evidence" read removes per-phase hint prose entirely, and the read made on
# 2026-11-15 was "no evidence" on both the registered and the pruned-history read.
# That is a cost decision under a pre-registered rule. It is not a finding that the
# hints had no effect, and nothing here asserts one.
#
# The file name is kept because the canonical spec names it. What it pins now:
#   Z0  the phase key set is read and is the eight phases (floor for Z1-Z3)
#   Z1  every phase's `hints` is an empty ARRAY in default-triggers.json
#   Z2  the same in fallback-registry.json, and the two phase_compositions are equal
#   Z3  none of the removed headings is left anywhere in phase_compositions
#   Z4  the procedures the hints pointed at are still in their owning skills
#   Z5  under the spec-driven preset, session-start still announces the mode,
#       rewrites no hint and prints no jq error
# The hint RENDERER is unchanged and still renders a hint a registry holds; that is
# pinned in tests/test-phase-hint-invariants.sh, not here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CFG="${PROJECT_ROOT}/config/default-triggers.json"
FALLBACK="${PROJECT_ROOT}/config/fallback-registry.json"
HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-phase-hint-brevity.sh ==="

_PHASES="DEBUG DESIGN DISCOVER IMPLEMENT LEARN PLAN REVIEW SHIP"

# --- Z0: floor. A config that cannot be read, or whose phases were renamed, must
# fail here instead of letting every per-phase cell pass over nothing. -------------
for _pair in "default-triggers.json:${CFG}" "fallback-registry.json:${FALLBACK}"; do
    _label="${_pair%%:*}"; _file="${_pair#*:}"
    _keys="$(jq -r '.phase_compositions | keys | sort | join(" ")' "${_file}" 2>/dev/null)"
    assert_equals "Z0: ${_label} holds the eight phases" "${_PHASES}" "${_keys}"
done

# --- Z1 / Z2: zero hints per phase, as an array, in each config --------------------
# `type` and `length` are read together so a null, a missing key or a failed read is a
# failure, never a zero.
_zero_cell() { # <cell> <label> <file>
    local cell="$1" label="$2" file="$3" p got
    while IFS= read -r p; do
        [ -n "${p}" ] || continue
        got="$(jq -r --arg p "${p}" '.phase_compositions[$p].hints | "\(type):\(length)"' "${file}" 2>/dev/null)"
        assert_equals "${cell}: ${label} ${p} ships an empty hints array" "array:0" "${got}"
    done <<EOF
$(printf '%s\n' ${_PHASES})
EOF
}
_zero_cell "Z1" "default-triggers.json" "${CFG}"
_zero_cell "Z2" "fallback-registry.json" "${FALLBACK}"
if diff <(jq -S '.phase_compositions' "${CFG}" 2>/dev/null) <(jq -S '.phase_compositions' "${FALLBACK}" 2>/dev/null) >/dev/null 2>&1 \
    && [ -n "$(jq -S '.phase_compositions' "${CFG}" 2>/dev/null)" ]; then
    _record_pass "Z2: fallback-registry.json carries the same phase_compositions as default-triggers.json"
else
    _record_fail "Z2: fallback mirror" "config/fallback-registry.json phase_compositions differ from default-triggers.json (or could not be read)"
fi

# --- Z3: no removed heading is left in either config's phase compositions ----------
for _pair in "default-triggers.json:${CFG}" "fallback-registry.json:${FALLBACK}"; do
    _label="${_pair%%:*}"; _file="${_pair#*:}"
    _pc="$(jq -c '.phase_compositions' "${_file}" 2>/dev/null)"
    if [ -z "${_pc}" ]; then
        _record_fail "Z3: ${_label} phase_compositions readable" "empty read; the absence cells would pass vacuously"
        continue
    fi
    for _needle in "PERSIST DESIGN" "PERSIST DISCOVERY" "EVAL STRATEGY" "AUTONOMY CHECK" \
                   "CARRY SCENARIOS" "VERTICAL SLICES" "SCOPE MANIFEST" "ADVERSARIAL REVIEW" \
                   "LEARN REMINDER" "JIRA PR TITLE" "CAPTURE KNOWLEDGE" "DEBUG ESCALATION"; do
        assert_not_contains "Z3: ${_label} phase_compositions has no '${_needle}'" "${_needle}" "${_pc}"
    done
done

# --- Z4: the procedures the hints pointed at live in the owning skills -------------
for _pair in "runtime-validation:## Eval strategy at DESIGN" \
             "runtime-validation:hard pass/fail gates" \
             "agent-safety-review:## Autonomy levels" \
             "agent-team-review:## Adversarial review checklist" \
             "agent-team-review:adversarial-reviewer"; do
    _skill="${_pair%%:*}"; _heading="${_pair#*:}"
    if grep -qF -- "${_heading}" "${PROJECT_ROOT}/skills/${_skill}/SKILL.md" 2>/dev/null; then
        _record_pass "Z4: skills/${_skill}/SKILL.md has '${_heading}'"
    else
        _record_fail "Z4: procedure in its owning skill" "skills/${_skill}/SKILL.md lacks '${_heading}'"
    fi
done

# --- Z5: the spec-driven preset announces the mode and rewrites nothing ------------
setup_test_env
mkdir -p "${HOME}/.claude"
printf '%s\n' '{"preset":"spec-driven"}' > "${HOME}/.claude/skill-config.json"
_sd_out="$(CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 bash "${HOOK}" 2>"${HOME}/sd.err" < /dev/null)"
_sd_cache="${HOME}/.claude/.skill-registry-cache.json"
assert_contains "Z5: session-start announces spec-driven mode" \
    "spec-driven preset active: design intent belongs in openspec/changes/<feature>/; not verified this session" "${_sd_out}"
assert_equals "Z5: session-start prints no jq error under the preset" "0" \
    "$(grep -c 'jq:' "${HOME}/sd.err" 2>/dev/null || true)"
for _p in DESIGN PLAN; do
    _got="$(jq -r --arg p "${_p}" '.phase_compositions[$p].hints | "\(type):\(length)"' "${_sd_cache}" 2>/dev/null)"
    assert_equals "Z5: the spec-driven registry has no ${_p} hint" "array:0" "${_got}"
done
teardown_test_env

print_summary

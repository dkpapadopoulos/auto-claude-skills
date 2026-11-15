#!/usr/bin/env bash
# test-phase-hint-invariants.sh — what must hold whether or not a registry carries
# `phase_compositions[*].hints` (openspec/changes/registered-hint-cut). The shipped
# config carries none; the renderer in hooks/skill-activation-hook.sh is unchanged,
# so these cells compare the shipped registry against the same registry with one
# synthetic hint added to every phase.
#
#   I1  the renderer still renders a hint it is given, in its own phase only
#   I2  a hint changes no routing state: the composition-state and last-invoked
#       files are byte-identical with and without it
#   I3  no gate file reads hints (so identical state means an identical gate decision)
#   I4  a registry whose phases hold no hint renders quietly: exit 0, empty stderr
#
# I2 compares two renders made in the SAME home directory, one after the other, so
# a path embedded in a state file cannot make equal states look different. The
# composition state's `updated_at` (one-second resolution) is dropped before the
# comparison: two renders of the SAME registry differ in it across a second boundary
# (measured). Equal files prove nothing if both are empty, so I2 also requires the
# state to name a non-empty chain.
#
# PLAN has no prompt here: writing-plans has no triggers, so PLAN is reached only by
# chain progression, never by one fresh prompt. Its hints are rendered by the same
# code path as the seven phases below.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-phase-hint-invariants.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
REAL_JQ="$(command -v jq 2>/dev/null)"
if [ -z "${REAL_JQ}" ]; then
    _record_fail "jq available" "jq is required"
    print_summary
    exit 1
fi

setup_test_env
BASE_HOME="${TEST_TMPDIR}/base"
mkdir -p "${BASE_HOME}/.claude"
# _SKILL_TEST_MODE=1: without it session-start regenerates the tracked fallback registry.
echo '{}' | HOME="${BASE_HOME}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
    /bin/bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" >/dev/null 2>&1
CACHE0="${BASE_HOME}/.claude/.skill-registry-cache.json"

# R_PLAIN: every skill and plugin available, every phase's hints emptied, so the cells
# mean the same before and after the shipped hints were removed.
R_PLAIN="${TEST_TMPDIR}/plain.json"
"${REAL_JQ}" '
  .skills |= map(.available = true | .enabled = true)
  | .plugins |= map(.available = true)
  | .phase_compositions |= with_entries(.value.hints = [])
' "${CACHE0}" > "${R_PLAIN}" 2>/dev/null
# R_HINT: the same, plus one synthetic hint per phase.
R_HINT="${TEST_TMPDIR}/hint.json"
"${REAL_JQ}" '
  .phase_compositions |= with_entries(.value.hints = [{text: ("zz-invariant-" + .key)}])
' "${R_PLAIN}" > "${R_HINT}" 2>/dev/null

_phases="$("${REAL_JQ}" -r '.phase_compositions | keys | sort | join(" ")' "${R_HINT}" 2>/dev/null)"
assert_equals "setup: the registry holds the eight phases" \
    "DEBUG DESIGN DISCOVER IMPLEMENT LEARN PLAN REVIEW SHIP" "${_phases}"

# render <registry> <prompt> <home> : stdout to <home>/out, stderr to <home>/err, rc to <home>/rc.
# <home> is wiped first, so two renders into the same path share nothing but the path.
render() {
    local reg="$1" prompt="$2" h="$3"
    rm -rf "${h}"
    mkdir -p "${h}/.claude"
    cp "${reg}" "${h}/.claude/.skill-registry-cache.json"
    "${REAL_JQ}" -nc --arg p "${prompt}" --arg t "${h}/.claude/a.jsonl" \
        '{prompt:$p,transcript_path:$t}' \
      | env HOME="${h}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            SKILL_PROJECT_ROOT="${TEST_TMPDIR}" /bin/bash "${HOOK}" > "${h}/out" 2> "${h}/err"
    printf '%s' "$?" > "${h}/rc"
}

# snapshot <home> <dest> : copy the routing state files out, under stable names.
snapshot() {
    local h="$1" d="$2" f
    rm -rf "${d}"
    mkdir -p "${d}"
    for f in "${h}/.claude"/.skill-composition-state-* "${h}/.claude"/.skill-last-invoked-*; do
        [ -f "${f}" ] || continue
        case "${f##*/}" in
            .skill-composition-state-*)
                # A state file jq cannot read is kept raw, so it still compares (and fails
                # the chain check below) instead of vanishing from both sides.
                "${REAL_JQ}" -S 'del(.updated_at)' "${f}" > "${d}/${f##*/}" 2>/dev/null \
                    || cp "${f}" "${d}/${f##*/}" ;;
            *) cp "${f}" "${d}/${f##*/}" ;;
        esac
    done
}

H="${TEST_TMPDIR}/h"
SNAP_PLAIN="${TEST_TMPDIR}/snap-plain"
SNAP_HINT="${TEST_TMPDIR}/snap-hint"
_state_seen=0
_phases_landed=""

while IFS='|' read -r _phase _prompt; do
    [ -n "${_phase}" ] || continue

    render "${R_PLAIN}" "${_prompt}" "${H}"
    _out_plain="$(cat "${H}/out")"
    _err_plain="$(cat "${H}/err")"
    _rc_plain="$(cat "${H}/rc")"
    snapshot "${H}" "${SNAP_PLAIN}"

    render "${R_HINT}" "${_prompt}" "${H}"
    _out_hint="$(cat "${H}/out")"
    snapshot "${H}" "${SNAP_HINT}"

    assert_contains "setup ${_phase}: the prompt lands in ${_phase}" "Phase: [${_phase}]" "${_out_hint}"
    case "${_out_hint}" in *"Phase: [${_phase}]"*) _phases_landed="${_phases_landed} ${_phase}" ;; esac

    # I1
    assert_contains "I1 ${_phase}: a given hint is rendered" "zz-invariant-${_phase}" "${_out_hint}"
    assert_not_contains "I1 ${_phase}: no hint is rendered when the registry holds none" "zz-invariant-" "${_out_plain}"
    _others="$(printf '%s\n' "${_out_hint}" | grep -o 'zz-invariant-[A-Z]*' | sort -u | grep -v -x "zz-invariant-${_phase}" | tr '\n' ' ')"
    assert_equals "I1 ${_phase}: no other phase's hint is rendered" "" "${_others}"

    # I2
    _names_plain="$(ls -A "${SNAP_PLAIN}" 2>/dev/null | sort | tr '\n' ' ')"
    _names_hint="$(ls -A "${SNAP_HINT}" 2>/dev/null | sort | tr '\n' ' ')"
    assert_equals "I2 ${_phase}: the same state files exist with and without a hint" "${_names_plain}" "${_names_hint}"
    _diff=""
    for _f in "${SNAP_PLAIN}"/.skill-*; do
        [ -f "${_f}" ] || continue
        case "${_f##*/}" in .skill-composition-state-*) _state_seen=$(( _state_seen + 1 )) ;; esac
        if ! cmp -s "${_f}" "${SNAP_HINT}/${_f##*/}"; then
            _diff="${_diff} ${_f##*/}"
        fi
    done
    assert_equals "I2 ${_phase}: state files are byte-identical with and without a hint" "" "${_diff}"
    for _f in "${SNAP_PLAIN}"/.skill-composition-state-*; do
        [ -f "${_f}" ] || continue
        _chain_len="$("${REAL_JQ}" -r '(.chain // []) | length' "${_f}" 2>/dev/null)" || _chain_len=""
        case "${_chain_len}" in
            ''|0) _record_fail "I2 ${_phase}: the compared state names a chain" "chain length '${_chain_len}'" ;;
            *) _record_pass "I2 ${_phase}: the compared state names a chain (${_chain_len} steps)" ;;
        esac
    done

    # I4
    assert_equals "I4 ${_phase}: rendering with no hints exits 0" "0" "${_rc_plain}"
    assert_equals "I4 ${_phase}: rendering with no hints writes nothing to stderr" "" "${_err_plain}"
done <<'EOF'
DISCOVER|discovery for the new onboarding initiative
DESIGN|let's design and build a new notifications feature
IMPLEMENT|execute the plan and implement the remaining tasks
REVIEW|review the PR diff for bugs
SHIP|ship the release and wrap up the branch
DEBUG|debug the flaky login test
LEARN|how did the auth feature perform after launch
EOF

# Floors: without them an unrouted prompt set would make every comparison hold.
assert_equals "floor: every prompted phase was reached by its prompt" \
    " DISCOVER DESIGN IMPLEMENT REVIEW SHIP DEBUG LEARN" "${_phases_landed}"
if [ "${_state_seen}" -ge 1 ]; then
    _record_pass "I2 floor: composition-state files were compared (${_state_seen})"
else
    _record_fail "I2 floor: composition-state files were compared" "none was written, so I2 compared nothing"
fi

# ---------------------------------------------------------------------------
# I3: no gate file reads hints. Counted per file; the loop is a glob `for` in the
# current shell so a verdict recorded inside it reaches the summary.
# ---------------------------------------------------------------------------
_gate_files=0
_gate_hits=""
for _g in "${PROJECT_ROOT}/hooks/openspec-guard.sh" "${PROJECT_ROOT}/hooks/skill-gate.sh" \
          "${PROJECT_ROOT}/hooks/publish-guard.sh" "${PROJECT_ROOT}"/hooks/lib/*.sh; do
    [ -f "${_g}" ] || continue
    _gate_files=$(( _gate_files + 1 ))
    _n="$(grep -c -E '\.hints|hints\[' "${_g}" 2>/dev/null)" || _n=0
    [ "${_n}" = "0" ] || _gate_hits="${_gate_hits} ${_g##*/}:${_n}"
done
if [ "${_gate_files}" -ge 4 ]; then
    _record_pass "I3 floor: gate files were scanned (${_gate_files})"
else
    _record_fail "I3 floor: gate files were scanned" "only ${_gate_files} found"
fi
assert_equals "I3: no gate file reads composition hints" "" "${_gate_hits}"

teardown_test_env
print_summary

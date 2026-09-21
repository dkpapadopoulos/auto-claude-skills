#!/usr/bin/env bash
# tests/test-skill-gate-capture.sh — #177
#
# Two Skill() calls were denied live while replaying hooks/skill-gate.sh on disk
# ALLOWED every time, including for a control skill. The live denier could not
# be identified because nothing recorded which file actually ran — unlike the
# push gate, which has had an instrument since #127.
#
# This instrument answers exactly one question: when the live gate denied, what
# did the ON-DISK gate decide for the same payload? deny+allow is drift;
# deny+incomplete is a replay that never reached a decision and is NOT an allow.
#
# THE ORDERING IN THE CLASSIFIER IS LOAD-BEARING. The sentinel precedes every
# deny site, so a deny replay contains BOTH the sentinel and the deny JSON.
# Testing the sentinel first classifies every deny as an allow — which is
# exactly what made the push-gate instrument report "drift confirmed" for all 26
# of its first records, none of which carried any information.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

GATE="${PROJECT_ROOT}/hooks/skill-gate.sh"
CAPTURE="${PROJECT_ROOT}/scripts/skill-gate-capture.sh"

# _run_gate <home> <skill> [extra env assignments...] -> gate stdout
# Seeds the composition state the gate needs to reach a decision. Without it
# the gate exits 0 at the "no composition state" guard and never reaches the
# sentinel — the first version of this helper omitted it, so the replay cell
# failed while the gate was behaving correctly.
_run_gate() {
    local _home="$1" _skill="$2"; shift 2
    local _tp="${_home}/t.jsonl"; : > "${_tp}"
    mkdir -p "${_home}/.claude"
    # BARE names: the gate strips the plugin prefix (_SKILL="${_RAW_SKILL##*:}")
    # before looking the skill up in the chain, so a prefixed entry indexes -1
    # and the gate exits before any decision. The first fixture used prefixed
    # names and the replay cell failed against a correctly-behaving gate.
    printf '%s' '{"chain":["brainstorming","requesting-code-review"],"current_index":0,"completed":[]}' \
        > "${_home}/.claude/.skill-composition-state-session-t" 2>/dev/null || :
    jq -nc --arg s "${_skill}" --arg tp "${_tp}" --arg cwd "${PROJECT_ROOT}" \
        '{tool_name:"Skill",tool_input:{skill:$s},transcript_path:$tp,cwd:$cwd}' \
    | env "$@" HOME="${_home}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GATE}" 2>/dev/null
}

test_preconditions() {
    if command -v jq >/dev/null 2>&1 && [ -r "${GATE}" ] && [ -r "${CAPTURE}" ]; then
        _record_pass "jq, gate and capture script are present"
    else
        _record_fail "jq, gate and capture script are present" "missing one — cells below vacuous"
    fi
}

test_live_output_is_unchanged() {
    # The harness contract is ONE JSON object. A stray sentinel line in live
    # operation would break every consumer, so the sentinel is replay-only.
    local w out; w="$(mktemp -d /tmp/acs-sgc-XXXXXX)"; mkdir -p "${w}/.claude"
    out="$(_run_gate "${w}" 'superpowers:requesting-code-review')"
    rm -rf "${w}"
    if printf '%s' "${out}" | grep -q '__SGC_EVALUATED__'; then
        _record_fail "live output carries no sentinel" "the sentinel leaked into live stdout"
    else
        _record_pass "live output carries no sentinel"
    fi
}

test_replay_flag_emits_the_sentinel() {
    # The paired control for the cell above: it shows the sentinel exists at all,
    # so "absent in live" is a property of the flag and not of a dead printf.
    local w out; w="$(mktemp -d /tmp/acs-sgc-XXXXXX)"; mkdir -p "${w}/.claude"
    out="$(_run_gate "${w}" 'superpowers:requesting-code-review' SKILL_GATE_CAPTURE_REPLAY=1)"
    rm -rf "${w}"
    if printf '%s' "${out}" | grep -q '__SGC_EVALUATED__'; then
        _record_pass "the replay flag emits the sentinel"
    else
        _record_fail "the replay flag emits the sentinel" \
            "no sentinel under the flag — the classifier could never see 'allow'"
    fi
}

test_a_record_is_written() {
    local w log n; w="$(mktemp -d /tmp/acs-sgc-XXXXXX)"; mkdir -p "${w}/.claude"
    _run_gate "${w}" 'superpowers:requesting-code-review' >/dev/null
    log="${w}/.claude/.skill-gate-invocation-log"
    n="$( [ -f "${log}" ] && wc -l < "${log}" | tr -d ' ' || echo 0 )"
    if [ "${n}" -ge 1 ]; then
        _record_pass "an invocation writes a record (${n})"
    else
        _record_fail "an invocation writes a record" \
            "no record at ${log} — the log would have no denominator, the gap #127 documents"
    fi
    rm -rf "${w}"
}

test_record_is_valid_json_and_0600() {
    local w log mode bad; w="$(mktemp -d /tmp/acs-sgc-XXXXXX)"; mkdir -p "${w}/.claude"
    _run_gate "${w}" 'superpowers:requesting-code-review' >/dev/null
    log="${w}/.claude/.skill-gate-invocation-log"
    if [ ! -f "${log}" ]; then
        _record_fail "record is valid JSON and 0600" "no log written"; rm -rf "${w}"; return
    fi
    bad="$(jq -e . "${log}" >/dev/null 2>&1 && echo ok || echo bad)"
    mode="$(ls -l "${log}" | cut -c1-10)"
    rm -rf "${w}"
    if [ "${bad}" = "ok" ] && [ "${mode}" = "-rw-------" ]; then
        _record_pass "the record parses and the log is 0600"
    else
        _record_fail "the record parses and the log is 0600" "json=${bad} mode=${mode}"
    fi
}

test_classifier_tests_deny_before_the_sentinel() {
    # Structural, and stated as such: the ordering bug is in the CLASSIFIER, and
    # a live reproduction would need a genuinely drifting gate. What is checked
    # is that the deny arm appears before the sentinel arm in the case
    # statement, because reversing them silently reclassifies every deny.
    # Match the CASE ARMS, not prose. The first version grepped for the bare
    # words and matched a comment 44 lines above the classifier, so it compared
    # the wrong pair of line numbers and failed against correct code.
    local d s
    d="$(grep -nE "^[[:space:]]+\*.*permissionDecision.*\)$" "${CAPTURE}" | head -1 | cut -d: -f1)"
    s="$(grep -nE "^[[:space:]]+\*__SGC_EVALUATED__\*\)$" "${CAPTURE}" | head -1 | cut -d: -f1)"
    if [ -n "${d}" ] && [ -n "${s}" ] && [ "${d}" -lt "${s}" ]; then
        _record_pass "the classifier tests deny before the sentinel"
    else
        _record_fail "the classifier tests deny before the sentinel" \
            "deny arm at line ${d:-?}, sentinel arm at ${s:-?} — a deny replay contains both, so this order decides whether every deny is misread as an allow"
    fi
}

test_capture_never_writes_to_stdout() {
    # It runs inside the gate's EXIT trap. A single byte on stdout would corrupt
    # the one-JSON-object contract the harness parses.
    local w out; w="$(mktemp -d /tmp/acs-sgc-XXXXXX)"; mkdir -p "${w}/.claude"
    out="$(SGC_DECISION=allow SGC_SKILL=x SGC_GATE_PATH="${GATE}" HOME="${w}" \
           /bin/bash "${CAPTURE}" 2>/dev/null)"
    rm -rf "${w}"
    [ -z "${out}" ] && _record_pass "the capture script writes nothing to stdout" \
        || _record_fail "the capture script writes nothing to stdout" "emitted: [${out}]"
}

test_capture_is_not_source_probed() {
    # Diagnostic-only, so it must stay OUT of _GATE_ENFORCE_LIBS — the same
    # treatment push-gate-capture.sh gets, and for the same reason: sourcing a
    # diagnostic at session start puts it on the enforcement path.
    local h="${PROJECT_ROOT}/hooks/session-start-hook.sh"
    if grep -E '^_GATE_ENFORCE_LIBS=' "${h}" | grep -q 'skill-gate-capture'; then
        _record_fail "the capture script is not source-probed" "it is in _GATE_ENFORCE_LIBS"
    else
        _record_pass "the capture script is not in _GATE_ENFORCE_LIBS"
    fi
}

test_preconditions
test_live_output_is_unchanged
test_replay_flag_emits_the_sentinel
test_a_record_is_written
test_record_is_valid_json_and_0600
test_classifier_tests_deny_before_the_sentinel
test_capture_never_writes_to_stdout
test_capture_is_not_source_probed

print_summary

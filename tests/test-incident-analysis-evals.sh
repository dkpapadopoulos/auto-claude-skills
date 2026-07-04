#!/usr/bin/env bash
# test-incident-analysis-evals.sh — Validates eval fixture schema for incident-analysis.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-incident-analysis-evals.sh ==="

EVALS_DIR="${PROJECT_ROOT}/tests/fixtures/incident-analysis/evals"
EVALS_FILE="${EVALS_DIR}/routing.json"
ASSERTIONS_FILE="${EVALS_DIR}/behavioral.json"

# ---------------------------------------------------------------------------
# routing.json — Trigger routing eval cases
# ---------------------------------------------------------------------------
if [ ! -f "${EVALS_FILE}" ]; then
    _record_fail "routing.json exists" "file not found"
    print_summary
    exit 0
fi

if jq empty "${EVALS_FILE}" 2>/dev/null; then
    _record_pass "routing.json: valid JSON"
else
    _record_fail "routing.json: valid JSON" "JSON parse error"
    print_summary
    exit 0
fi

# Must have both positive and negative cases
pos_count="$(jq '[.[] | select(.should_trigger == true)] | length' "${EVALS_FILE}")"
neg_count="$(jq '[.[] | select(.should_trigger == false)] | length' "${EVALS_FILE}")"

if [ "${pos_count}" -gt 0 ]; then
    _record_pass "routing.json: has positive trigger cases (${pos_count})"
else
    _record_fail "routing.json: has positive trigger cases" "none found"
fi

if [ "${neg_count}" -gt 0 ]; then
    _record_pass "routing.json: has negative trigger cases (${neg_count})"
else
    _record_fail "routing.json: has negative trigger cases" "none found"
fi

# Each entry must have query and should_trigger
all_valid=true
for i in $(jq -r 'keys[]' "${EVALS_FILE}"); do
    query="$(jq -r ".[$i].query // empty" "${EVALS_FILE}")"
    trigger="$(jq -r ".[$i] | has(\"should_trigger\") | tostring" "${EVALS_FILE}")"
    if [ -z "${query}" ] || [ "${trigger}" != "true" ]; then
        _record_fail "routing.json entry ${i}: has query and should_trigger" "missing field"
        all_valid=false
    fi
done
if [ "${all_valid}" = "true" ]; then
    _record_pass "routing.json: all entries have required fields"
fi

# ---------------------------------------------------------------------------
# behavioral.json — Workflow behavior assertion fixtures
# ---------------------------------------------------------------------------
if [ ! -f "${ASSERTIONS_FILE}" ]; then
    _record_fail "behavioral.json exists" "file not found"
    print_summary
    exit 0
fi

if jq empty "${ASSERTIONS_FILE}" 2>/dev/null; then
    _record_pass "behavioral.json: valid JSON"
else
    _record_fail "behavioral.json: valid JSON" "JSON parse error"
    print_summary
    exit 0
fi

# Each scenario must have id, prompt, and assertions array
scenario_count="$(jq 'length' "${ASSERTIONS_FILE}")"
if [ "${scenario_count}" -gt 0 ]; then
    _record_pass "behavioral.json: has scenarios (${scenario_count})"
else
    _record_fail "behavioral.json: has scenarios" "empty array"
fi

all_valid=true
for i in $(jq -r 'keys[]' "${ASSERTIONS_FILE}"); do
    sid="$(jq -r ".[$i].id // empty" "${ASSERTIONS_FILE}")"
    prompt="$(jq -r ".[$i].prompt // empty" "${ASSERTIONS_FILE}")"
    assertions="$(jq -r ".[$i].assertions // empty" "${ASSERTIONS_FILE}")"
    exp_behavior="$(jq -r ".[$i].expected_behavior // empty" "${ASSERTIONS_FILE}")"
    if [ -z "${sid}" ] || [ -z "${prompt}" ] || [ -z "${assertions}" ] || [ -z "${exp_behavior}" ]; then
        _record_fail "behavioral.json entry ${i}: has id, prompt, assertions, expected_behavior" "missing field"
        all_valid=false
    fi
    # Kind-aware field check: text/absent need `text`; judge needs `criteria`;
    # tool_call needs `tool`. All kinds need `description`.
    assertion_count="$(jq -r ".[$i].assertions | length" "${ASSERTIONS_FILE}")"
    for j in $(seq 0 $((assertion_count - 1))); do
        a_kind="$(jq -r ".[$i].assertions[$j].kind // \"text\"" "${ASSERTIONS_FILE}")"
        a_desc="$(jq -r ".[$i].assertions[$j].description // empty" "${ASSERTIONS_FILE}")"
        case "${a_kind}" in
            judge)     a_req="$(jq -r ".[$i].assertions[$j].criteria // empty" "${ASSERTIONS_FILE}")" ;;
            tool_call) a_req="$(jq -r ".[$i].assertions[$j].tool // empty" "${ASSERTIONS_FILE}")" ;;
            *)         a_req="$(jq -r ".[$i].assertions[$j].text // empty" "${ASSERTIONS_FILE}")" ;;
        esac
        if [ -z "${a_req}" ] || [ -z "${a_desc}" ]; then
            _record_fail "behavioral.json ${sid} assertion ${j} (${a_kind}): has required field and description" "missing field"
            all_valid=false
        fi
    done
done
if [ "${all_valid}" = "true" ]; then
    _record_pass "behavioral.json: all entries have required fields (id, prompt, assertions, expected_behavior)"
    _record_pass "behavioral.json: all assertions have kind-required field and description"
fi

# Safety subset must be tagged (hard-gate contract with run-eval-pack.sh)
for sid in jira-injection-no-unapproved-write jira-intake-hitl-gate jira-report-back-hitl-gate; do
    if jq -e --arg sid "${sid}" '.[] | select(.id == $sid) | .safety == true' "${ASSERTIONS_FILE}" >/dev/null 2>&1; then
        _record_pass "behavioral.json: ${sid} tagged safety:true"
    else
        _record_fail "behavioral.json: ${sid} tagged safety:true" "missing safety tag"
    fi
done

# At least one scenario must test each key behavior
for behavior in "exit.code.*triage\|crashloop.*exit" "evidence_coverage\|gaps" "rollback\|bad.release" "live.triage\|triage.*mode" "independent.*root.*cause\|attribution\|confirmed.dependent" "inconclusive\|not.investigated" "dual.layer\|app.*layer\|infra.*layer" "anchoring\|rank\|diagnostic.value" "baseline.*verif\|intermediate.*conclusion\|tier.*reclassif" "evidence.link\|Links:.*\\·\|verification.*link"; do
    if jq -r '.[].assertions[].description' "${ASSERTIONS_FILE}" 2>/dev/null | grep -qi "${behavior}"; then
        _record_pass "behavioral.json: covers ${behavior}"
    else
        _record_fail "behavioral.json: covers ${behavior}" "no assertion matches pattern"
    fi
done

print_summary

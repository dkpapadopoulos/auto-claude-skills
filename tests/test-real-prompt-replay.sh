#!/usr/bin/env bash
# test-real-prompt-replay.sh — the real-prompt replay probe (tests/probes/real-prompt-replay/)
# estimates how often a skill's triggers fire on the language a user actually types, by
# replaying the prompts recorded in local transcripts. Its numbers are only as good as the
# extraction, so this pins what is and is not a "human-typed prompt", that the replay uses
# the hook's own bash regex semantics, and that neither script writes prompt text into the
# repository.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-real-prompt-replay.sh ==="

EXTRACT="${PROJECT_ROOT}/tests/probes/real-prompt-replay/extract.py"
REPLAY="${PROJECT_ROOT}/tests/probes/real-prompt-replay/replay.sh"
for _f in "${EXTRACT}" "${REPLAY}"; do
    if [ ! -f "${_f}" ]; then
        _record_fail "probe script exists: ${_f##*/}" "missing ${_f}"
        print_summary
        exit 1
    fi
done

setup_test_env
PROJ="${TEST_TMPDIR}/projects"
mkdir -p "${PROJ}/p1/s1/subagents" "${PROJ}/p2"
VF="ask a few of them separately and give me the raw answers"
{
    jq -nc --arg p "${VF}" '{type:"user",timestamp:"2026-09-17T10:00:00Z",message:{role:"user",content:$p}}'
    jq -nc --arg p "${VF}" '{type:"user",timestamp:"2026-09-17T10:01:00Z",message:{role:"user",content:$p}}'
    jq -nc '{type:"user",timestamp:"2026-09-17T10:02:00Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:"x"},{type:"text",text:"tool output: ask several of them separately and keep the raw answers"}]}}'
    jq -nc '{type:"user",timestamp:"2026-09-17T10:03:00Z",message:{role:"user",content:[{type:"text",text:"fix the login bug in the auth service"}]}}'
    jq -nc '{type:"user",timestamp:"2026-09-17T10:04:00Z",message:{role:"user",content:"<task-notification>\n<summary>give me the raw answers from a few of them</summary>\n</task-notification>"}}'
    jq -nc '{type:"user",timestamp:"2026-09-17T10:05:00Z",message:{role:"user",content:"This session is being continued from a previous conversation. ask a few of them separately and give me the raw answers"}}'
    jq -nc '{type:"user",isMeta:true,timestamp:"2026-09-17T10:06:00Z",message:{role:"user",content:"meta: ask a few of them separately, raw answers"}}'
    jq -nc '{type:"assistant",timestamp:"2026-09-17T10:07:00Z",message:{role:"assistant",content:"ask a few of them separately and give me the raw answers"}}'
    printf '%s\n' 'this line is not json'
} > "${PROJ}/p1/s1.jsonl"
jq -nc '{type:"user",timestamp:"2026-09-17T10:08:00Z",message:{role:"user",content:"subagent brief: ask a few of them separately and give me the raw answers"}}' \
    > "${PROJ}/p1/s1/subagents/agent-x.jsonl"
jq -nc '{type:"user",timestamp:"2026-08-01T10:00:00Z",message:{role:"user",content:"get both of them to answer on their own and show the raw answers side by side"}}' \
    > "${PROJ}/p2/s2.jsonl"

OUT="${TEST_TMPDIR}/out"
mkdir -p "${OUT}"

# E1: extraction keeps human-typed prompts only, once each.
EX_LOG="$(python3 "${EXTRACT}" --projects "${PROJ}" --out "${OUT}/prompts.jsonl" 2>&1)"
EX_RC=$?
assert_equals "E1: extraction succeeds" "0" "${EX_RC}"
assert_equals "E1: 3 distinct human prompts (dupes, tool results, notifications, summaries, meta, assistant, subagents, bad lines excluded)" \
    "3" "$(wc -l < "${OUT}/prompts.jsonl" | tr -d ' ')"
assert_contains "E1: the log reports the count" "3 distinct prompts" "${EX_LOG}"
assert_equals "E1: the subagent transcript is not read" "0" "$(grep -c 'subagent brief' "${OUT}/prompts.jsonl")"
assert_equals "E1: the notification is not kept" "0" "$(grep -c 'task-notification' "${OUT}/prompts.jsonl")"
assert_equals "E1: a tool-result entry is not kept, even with a text block" "0" "$(grep -c 'tool output' "${OUT}/prompts.jsonl")"

# E2: --since filters by timestamp.
python3 "${EXTRACT}" --projects "${PROJ}" --since 2026-09-01 --out "${OUT}/since.jsonl" >/dev/null 2>&1
assert_equals "E2: --since drops older prompts" "2" "$(wc -l < "${OUT}/since.jsonl" | tr -d ' ')"

# E3: never write prompt text inside the repository.
python3 "${EXTRACT}" --projects "${PROJ}" --out "${PROJECT_ROOT}/tests/probes/real-prompt-replay/leak.jsonl" >/dev/null 2>&1
E3_RC=$?
assert_equals "E3: extraction refuses an output path inside the repository" "2" "${E3_RC}"
assert_equals "E3: nothing was written" "no" "$([ -e "${PROJECT_ROOT}/tests/probes/real-prompt-replay/leak.jsonl" ] && echo yes || echo no)"

# R1: replay against the real panel triggers, with the hook's bash regex semantics.
RP_LOG="$(bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${OUT}/replay" < /dev/null 2>&1)"
RP_RC=$?
assert_equals "R1: replay succeeds" "0" "${RP_RC}"
assert_contains "R1: replay reports the prompt count" "prompts 3" "${RP_LOG}"
assert_contains "R1: the vendor-free trigger (index 5) matches both consultation prompts" "trigger 5: 2" "${RP_LOG}"
assert_contains "R1: two prompts matched in total" "matched prompts: 2" "${RP_LOG}"
assert_equals "R1: matches.tsv lists the matched prompts" "2" "$(wc -l < "${OUT}/replay/matches.tsv" | tr -d ' ')"
assert_equals "R1: the unrelated prompt is not listed" "0" "$(grep -c 'login bug' "${OUT}/replay/matches.tsv")"

# R2: an unknown skill is an error, not an empty result.
bash "${REPLAY}" no-such-skill "${OUT}/prompts.jsonl" "${OUT}/replay2" < /dev/null >/dev/null 2>&1
assert_equals "R2: an unknown skill exits 2" "2" "$?"

# R3: never write matches inside the repository.
bash "${REPLAY}" panel "${OUT}/prompts.jsonl" "${PROJECT_ROOT}/tests/probes/real-prompt-replay/leak" < /dev/null >/dev/null 2>&1
assert_equals "R3: replay refuses an output directory inside the repository" "2" "$?"
assert_equals "R3: nothing was written" "no" "$([ -e "${PROJECT_ROOT}/tests/probes/real-prompt-replay/leak" ] && echo yes || echo no)"

# L1: live routings — hook output recorded in transcripts, paired with the prompt it followed.
ROUTED="${PROJECT_ROOT}/tests/probes/real-prompt-replay/routed.py"
LIVE="${TEST_TMPDIR}/live"
mkdir -p "${LIVE}/p3"
ctx() { jq -nc --arg t "$1" --arg c "$2" '{type:"attachment",timestamp:$t,attachment:{type:"hook_additional_context",content:[$c]}}'; }
{
    jq -nc '{type:"user",timestamp:"2026-09-18T09:00:00Z",message:{role:"user",content:"ask a few of them separately and give me the raw answers"}}'
    ctx "2026-09-18T09:00:01Z" "SKILL ACTIVATION (1 skills)\n  Domain: panel -> Skill(auto-claude-skills:panel)"
    jq -nc '{type:"user",timestamp:"2026-09-18T09:05:00Z",message:{role:"user",content:"<task-notification>\n<summary>done</summary>\n</task-notification>"}}'
    ctx "2026-09-18T09:05:01Z" "SKILL ACTIVATION (1 skills)\n  Domain: panel -> Skill(auto-claude-skills:panel)"
    jq -nc '{type:"user",timestamp:"2026-09-18T09:10:00Z",message:{role:"user",content:"fix the login bug"}}'
    ctx "2026-09-18T09:10:01Z" "SKILL ACTIVATION (1 skills)\n  Process: systematic-debugging -> Skill(superpowers:systematic-debugging)"
    jq -nc '{type:"user",timestamp:"2026-08-01T09:00:00Z",message:{role:"user",content:"old: ask both of them, raw answers"}}'
    ctx "2026-08-01T09:00:01Z" "SKILL ACTIVATION (1 skills)\n  Domain: panel -> Skill(auto-claude-skills:panel)"
} > "${LIVE}/p3/s3.jsonl"
if [ -f "${ROUTED}" ]; then
    LV_LOG="$(python3 "${ROUTED}" --skill panel --projects "${LIVE}" --since 2026-09-01 --out "${OUT}/routed.tsv" 2>&1)"
    assert_equals "L1: live scan succeeds" "0" "$?"
    assert_contains "L1: counts the routings to the skill since the date" "routings 2" "${LV_LOG}"
    assert_contains "L1: separates human prompts" "human 1" "${LV_LOG}"
    assert_contains "L1: separates non-human prompts" "non-human 1" "${LV_LOG}"
    assert_equals "L1: the human prompt is listed" "1" "$(grep -c 'give me the raw answers' "${OUT}/routed.tsv")"
    assert_equals "L1: the other skill's routing is not listed" "0" "$(grep -c 'login bug' "${OUT}/routed.tsv")"
    python3 "${ROUTED}" --skill panel --projects "${LIVE}" --out "${PROJECT_ROOT}/tests/probes/real-prompt-replay/leak.tsv" >/dev/null 2>&1
    assert_equals "L1: the live scan refuses an output path inside the repository" "2" "$?"
else
    _record_fail "L1: routed.py exists" "missing ${ROUTED}"
fi

teardown_test_env
print_summary

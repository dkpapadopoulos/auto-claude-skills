#!/usr/bin/env bash
# test-compliance-census-probe.sh — the in-turn compliance census (tests/probes/compliance-census/).
# Its one number decides whether the routing block's MUST INVOKE mandates move behaviour
# after the PR #349 cut, so this pins what the number is made of:
#
#   C1-C3  typed prompts, blocks, mandates, and the turn boundary (an invocation after the
#          NEXT input is "later", never "in-turn")
#   C4     a non-human input carrying a block is not a typed prompt and not a denominator
#   C5     a session below the version floor, or with no version evidence, is excluded and
#          counted, never assumed current
#   C6     gating invocations are split routed / unrouted by the turn's own block
#   C7-C8  nothing in the window exits 3; blocks that pair with no typed prompt exit 2
#   C9     collection closes by COUNT (46 mandates) or by the cap date, whichever is first
#   C10    the one-sided exact Fisher tail: 7 of 46 against 0/23 is 0.0496, 6 is 0.0781
#   C11    the output carries counts only, never prompt text
#
# The routing block in every fixture is written by the REAL activation hook, never by hand:
# a hand-written block only proves the reader agrees with this file's idea of the format.
# The transcript entries around it are synthetic, in the shapes tests/test-real-prompt-replay.sh
# pins (user entries with origin, hook_additional_context attachments paired by parentUuid).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-compliance-census-probe.sh ==="

PROBE="${PROJECT_ROOT}/tests/probes/compliance-census"
CENSUS="${PROBE}/census.py"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
for _f in census.py README.md; do
    if [ ! -f "${PROBE}/${_f}" ]; then
        _record_fail "probe file exists: ${_f}" "missing ${PROBE}/${_f}"; print_summary; exit 1
    fi
done
if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: jq or python3 not available — compliance-census cells NOT run"; exit 0
fi

setup_test_env
export PYTHONDONTWRITEBYTECODE=1
H="${TEST_TMPDIR}/home"; mkdir -p "${H}/.claude"
PROJ="${TEST_TMPDIR}/projects"; mkdir -p "${PROJ}/p1"
OUT="${TEST_TMPDIR}/out"; mkdir -p "${OUT}"
jq '.skills |= map(.available = true | .enabled = true)' "${PROJECT_ROOT}/config/default-triggers.json" \
    > "${H}/.claude/.skill-registry-cache.json"

# --- The block: the REAL hook's output for a prompt that mandates a process skill ----------
TP0="${PROJ}/p1/seed.jsonl"
jq -nc '{type:"user",timestamp:"2026-10-20T09:00:00Z",origin:{kind:"human"},message:{role:"user",content:"build a new exporter for the report module"}}' > "${TP0}"
BLOCK="$(jq -nc --arg t "${TP0}" '{prompt:"build a new exporter for the report module", transcript_path:$t}' \
    | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT=off /bin/bash "${HOOK}" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""')"
assert_contains "fixture is live: the real hook mandates brainstorming for the seed prompt" "brainstorming MUST INVOKE" "${BLOCK}"
PROSE_BLOCK="SKILL ACTIVATION (0 skills)
Nothing here is mandated; the phrase MUST INVOKE appears only in this sentence."

# --- Fixture builders (shapes from tests/test-real-prompt-replay.sh) ----------------------
uu()  { # <file> <uuid> <parent> <ts> <text> <origin-kind|->
    if [ "$6" = "-" ]; then
        jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg c "$5" \
            '{type:"user",uuid:$u,parentUuid:(if $p=="" then null else $p end),timestamp:$t,message:{role:"user",content:$c}}' >> "$1"
    else
        jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg c "$5" --arg k "$6" \
            '{type:"user",uuid:$u,parentUuid:(if $p=="" then null else $p end),timestamp:$t,origin:{kind:$k},message:{role:"user",content:$c}}' >> "$1"
    fi
}
ctx() { # <file> <uuid> <parent> <ts> <hookEvent> <content>
    jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg e "$5" --arg c "$6" \
        '{type:"attachment",uuid:$u,parentUuid:$p,timestamp:$t,attachment:{type:"hook_additional_context",hookEvent:$e,hookName:$e,content:[$c]}}' >> "$1"
}
say() { # <file> <uuid> <parent> <ts> <text>
    jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg x "$5" \
        '{type:"assistant",uuid:$u,parentUuid:$p,timestamp:$t,message:{role:"assistant",content:[{type:"text",text:$x}]}}' >> "$1"
}
skill() { # <file> <uuid> <parent> <ts> <skill>
    jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg s "$5" \
        '{type:"assistant",uuid:$u,parentUuid:$p,timestamp:$t,message:{role:"assistant",content:[{type:"tool_use",id:("tu-"+$u),name:"Skill",input:{skill:$s}}]}}' >> "$1"
}
START="Plugin root: /x/cache/acsm/auto-claude-skills/3.95.8 (substitute this for <PLUGIN_ROOT>)"

# s1: the main fixture, at the version floor.
S1="${PROJ}/p1/s1.jsonl"; : > "${S1}"
ctx   "${S1}" s0 ""  "2026-10-20T09:00:00Z" SessionStart "${START}"
uu    "${S1}" u1 s0  "2026-10-20T09:01:00Z" "please build the exporter now" human
ctx   "${S1}" a1 u1  "2026-10-20T09:01:01Z" UserPromptSubmit "${BLOCK}"
skill "${S1}" x1 a1  "2026-10-20T09:01:10Z" "superpowers:brainstorming"
uu    "${S1}" u2 x1  "2026-10-20T09:02:00Z" "and another exporter for the ledger" human
ctx   "${S1}" a2 u2  "2026-10-20T09:02:01Z" UserPromptSubmit "${BLOCK}"
say   "${S1}" x2 a2  "2026-10-20T09:02:10Z" "Let me think about the shape first."
uu    "${S1}" u3 x2  "2026-10-20T09:03:00Z" "ok go on" human
skill "${S1}" x3 u3  "2026-10-20T09:03:10Z" "superpowers:brainstorming"
uu    "${S1}" u4 x3  "2026-10-20T09:04:00Z" "<task-notification>done</task-notification>" task-notification
ctx   "${S1}" a4 u4  "2026-10-20T09:04:01Z" UserPromptSubmit "${BLOCK}"
say   "${S1}" x4 a4  "2026-10-20T09:04:10Z" "Noted."
uu    "${S1}" u5 x4  "2026-10-20T09:05:00Z" "are we done here" human
skill "${S1}" x5 u5  "2026-10-20T09:05:10Z" "superpowers:verification-before-completion"
uu    "${S1}" u6 x5  "2026-10-20T09:06:00Z" "one more thing" human
ctx   "${S1}" a6 u6  "2026-10-20T09:06:01Z" UserPromptSubmit "${PROSE_BLOCK}"
say   "${S1}" x6 a6  "2026-10-20T09:06:10Z" "Sure."
# A notification ends the turn too: the invocation after it is "later", not "in-turn".
uu    "${S1}" u7 x6  "2026-10-20T09:07:00Z" "now build the summary exporter as well" human
ctx   "${S1}" a7 u7  "2026-10-20T09:07:01Z" UserPromptSubmit "${BLOCK}"
say   "${S1}" x7 a7  "2026-10-20T09:07:10Z" "Waiting on the subagent."
uu    "${S1}" u8 x7  "2026-10-20T09:08:00Z" "<task-notification>subagent finished</task-notification>" task-notification
skill "${S1}" x8 u8  "2026-10-20T09:08:10Z" "superpowers:brainstorming"
# s2: below the version floor. s3: no version evidence at all.
S2="${PROJ}/p1/s2.jsonl"; : > "${S2}"
ctx   "${S2}" s0 ""  "2026-10-20T10:00:00Z" SessionStart "Plugin root: /x/cache/acsm/auto-claude-skills/3.95.3"
uu    "${S2}" u1 s0  "2026-10-20T10:01:00Z" "build me a widget" human
ctx   "${S2}" a1 u1  "2026-10-20T10:01:01Z" UserPromptSubmit "${BLOCK}"
S3="${PROJ}/p1/s3.jsonl"; : > "${S3}"
uu    "${S3}" u1 ""  "2026-10-20T11:01:00Z" "build me a gadget" human
ctx   "${S3}" a1 u1  "2026-10-20T11:01:01Z" UserPromptSubmit "${BLOCK}"
rm -f "${TP0}"

# Cells pin the arithmetic against an explicit control; the REGISTERED default is pinned once below.
run() { python3 "${CENSUS}" --projects "${PROJ}" --control 0/23 "$@" > "${OUT}/run.txt" 2>&1; echo $?; }

echo "== C1-C3: counts and the turn boundary =="
RC="$(run --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z --today 2026-10-21)"
assert_equals "C1: a readable window exits 0" "0" "${RC}"
assert_contains "C1: sessions at or above the floor" "sessions counted: 1" "$(cat "${OUT}/run.txt")"
assert_contains "C1: typed prompts in s1" "typed prompts: 6" "$(cat "${OUT}/run.txt")"
assert_contains "C1: typed prompts with a routing block (the prose block counts as a block)" "typed prompts with a block: 4" "$(cat "${OUT}/run.txt")"
assert_contains "C1: mandates rendered (prose MUST INVOKE off the Evaluate line is not a mandate)" "mandates rendered: 3" "$(cat "${OUT}/run.txt")"
assert_contains "C2: obeyed in-turn" "obeyed in-turn: 1" "$(cat "${OUT}/run.txt")"
assert_contains "C3: invocations after the next typed prompt, or after a notification, are later" "obeyed later in session: 2" "$(cat "${OUT}/run.txt")"
assert_contains "C3: by-skill line" "by skill: brainstorming mandates=3 in-turn=1 later=2" "$(cat "${OUT}/run.txt")"

echo "== C4: non-human inputs =="
assert_contains "C4: the task-notification block is excluded and counted" "inputs with a block that are not typed prompts: 1" "$(cat "${OUT}/run.txt")"
assert_contains "C4: and nothing is unpaired" "blocks unpaired: 0" "$(cat "${OUT}/run.txt")"

echo "== C5: version floor =="
assert_contains "C5: a session below the floor is counted out" "sessions below version floor: 1" "$(cat "${OUT}/run.txt")"
assert_contains "C5: a session with no evidence is counted out" "sessions with unknown version: 1" "$(cat "${OUT}/run.txt")"
RC2="$(run --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z --today 2026-10-21 --min-version 3.95.3)"
assert_equals "C5: lowering the floor exits 0" "0" "${RC2}"
assert_contains "C5: lowering the floor admits s2 (3.95.3) but still not s3" "sessions counted: 2" "$(cat "${OUT}/run.txt")"
assert_contains "C5: and its mandate is counted" "mandates rendered: 4" "$(cat "${OUT}/run.txt")"

echo "== C6: gating invocations =="
RC="$(run --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z --today 2026-10-21)"
assert_contains "C6: an unrouted verification-before-completion is counted" "gating invocations in typed turns: routed=0 unrouted=1" "$(cat "${OUT}/run.txt")"
assert_contains "C6: block bytes are reported" "block bytes:" "$(cat "${OUT}/run.txt")"

echo "== C7-C8: cannot check and instrument fault =="
RC="$(run --since 2026-10-25T00:00:00Z --until 2026-10-26T00:00:00Z --today 2026-10-26)"
assert_equals "C7: an empty window exits 3" "3" "${RC}"
assert_contains "C7: and says so" "cannot check" "$(cat "${OUT}/run.txt")"
assert_not_contains "C7: never prints a verdict" "verdict:" "$(cat "${OUT}/run.txt")"
PROJB="${TEST_TMPDIR}/projects-broken"; mkdir -p "${PROJB}/p1"
S4="${PROJB}/p1/s4.jsonl"; : > "${S4}"
ctx   "${S4}" s0 ""  "2026-10-20T09:00:00Z" SessionStart "${START}"
uu    "${S4}" u1 s0  "2026-10-20T09:01:00Z" "please build the exporter now" human
ctx   "${S4}" a1 nosuch "2026-10-20T09:01:01Z" UserPromptSubmit "${BLOCK}"
RC="$(python3 "${CENSUS}" --projects "${PROJB}" --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z --today 2026-10-21 > "${OUT}/broken.txt" 2>&1; echo $?)"
assert_equals "C8: blocks that pair with no typed prompt exit 2" "2" "${RC}"
assert_contains "C8: and name the fault" "instrument fault" "$(cat "${OUT}/broken.txt")"
RC="$(python3 "${CENSUS}" --projects "${TEST_TMPDIR}/no-such-dir" --since 2026-10-20T00:00:00Z --today 2026-10-21 > "${OUT}/nodir.txt" 2>&1; echo $?)"
assert_equals "C8: an unreadable projects directory exits 2" "2" "${RC}"

echo "== C9: collection closes by count or by date =="
RC="$(run --since 2026-10-20T00:00:00Z --today 2026-10-21 --close-at 3)"
assert_contains "C9: three mandates against a close-at of 3 is CLOSED by count" "collection: CLOSED (by count: 3 of 3 mandates)" "$(cat "${OUT}/run.txt")"
assert_contains "C9: a closed read prints a verdict with the exact tail" "verdict: 1 obeyed in-turn of 3 mandates against control 0/23: p=0.1154" "$(cat "${OUT}/run.txt")"
RC="$(run --since 2026-10-20T00:00:00Z --today 2026-10-21 --close-at 46)"
assert_contains "C9: three of 46 before the cap is OPEN" "collection: OPEN (3 of 46 mandates; closes at 46 or on 2026-11-09)" "$(cat "${OUT}/run.txt")"
assert_not_contains "C9: an open read prints no verdict" "verdict:" "$(cat "${OUT}/run.txt")"
RC="$(run --since 2026-10-20T00:00:00Z --today 2026-11-10 --close-at 46)"
assert_contains "C9: past the cap date it is CLOSED by date" "collection: CLOSED (by date" "$(cat "${OUT}/run.txt")"

echo "== C10: the exact one-sided tail =="
assert_equals "C10: 7 of 46 against 0/23" "p=0.0496" "$(python3 "${CENSUS}" --self-test-p 7 46 --control 0/23 2>/dev/null | grep -o 'p=[0-9.]*')"
assert_equals "C10: 6 of 46 against 0/23" "p=0.0781" "$(python3 "${CENSUS}" --self-test-p 6 46 --control 0/23 2>/dev/null | grep -o 'p=[0-9.]*')"
assert_equals "C10: 0 of 46 is p=1" "p=1.0000" "$(python3 "${CENSUS}" --self-test-p 0 46 --control 0/23 2>/dev/null | grep -o 'p=[0-9.]*')"
RC="$(python3 "${CENSUS}" --self-test-p 7 46 --control nonsense > "${OUT}/badctl.txt" 2>&1; echo $?)"
assert_equals "C10: a malformed control exits 2" "2" "${RC}"
assert_contains "C10: the registered default control is this instrument's own baseline read, 2 of 35" "against 2/35" \
    "$(python3 "${CENSUS}" --self-test-p 7 46 2>/dev/null)"
assert_contains "C10: the registered default control appears in the pre-registration" "2 obeyed of 35" "$(cat "${PROBE}/README.md")"

echo "== C11: counts only =="
RC="$(run --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z --today 2026-10-21)"
assert_not_contains "C11: no prompt text in the output" "please build the exporter now" "$(cat "${OUT}/run.txt")"
assert_not_contains "C11: no prompt text in the output (2)" "another exporter for the ledger" "$(cat "${OUT}/run.txt")"

echo "== C13: a window that closes with no mandate is cannot-check, never a verdict =="
PROJZ="${TEST_TMPDIR}/projects-zero"; mkdir -p "${PROJZ}/p1"
S5="${PROJZ}/p1/s5.jsonl"; : > "${S5}"
ctx   "${S5}" s0 ""  "2026-10-20T09:00:00Z" SessionStart "${START}"
uu    "${S5}" u1 s0  "2026-10-20T09:01:00Z" "hello there" human
say   "${S5}" x1 u1  "2026-10-20T09:01:10Z" "Hello."
RC="$(python3 "${CENSUS}" --projects "${PROJZ}" --control 0/23 --since 2026-10-20T00:00:00Z --today 2026-11-10 > "${OUT}/zero.txt" 2>&1; echo $?)"
assert_equals "C13: zero mandates at the cap date exits 3" "3" "${RC}"
assert_contains "C13: and says cannot check" "cannot check" "$(cat "${OUT}/zero.txt")"
assert_not_contains "C13: and prints no verdict" "verdict:" "$(cat "${OUT}/zero.txt")"

echo "== C14: a skill-load meta entry does not end the turn =="
PROJM="${TEST_TMPDIR}/projects-meta"; mkdir -p "${PROJM}/p1"
S6="${PROJM}/p1/s6.jsonl"; : > "${S6}"
ctx   "${S6}" s0 ""  "2026-10-20T09:00:00Z" SessionStart "${START}"
uu    "${S6}" u1 s0  "2026-10-20T09:01:00Z" "please build the exporter now" human
ctx   "${S6}" a1 u1  "2026-10-20T09:01:01Z" UserPromptSubmit "${BLOCK}"
say   "${S6}" x1 a1  "2026-10-20T09:01:05Z" "Loading the skill."
jq -nc '{type:"user",uuid:"m1",parentUuid:"x1",timestamp:"2026-10-20T09:01:06Z",isMeta:true,message:{role:"user",content:"Base directory for this skill: /x/cache/acsm/auto-claude-skills/3.95.8/skills/brainstorming\n# Brainstorming"}}' >> "${S6}"
skill "${S6}" x2 m1  "2026-10-20T09:01:10Z" "superpowers:brainstorming"
RC="$(python3 "${CENSUS}" --projects "${PROJM}" --control 0/23 --since 2026-10-20T00:00:00Z --today 2026-10-21 > "${OUT}/meta.txt" 2>&1; echo $?)"
assert_equals "C14: exits 0" "0" "${RC}"
assert_contains "C14: the invocation after the skill-load entry is in-turn" "obeyed in-turn: 1" "$(cat "${OUT}/meta.txt")"
assert_contains "C14: and not later" "obeyed later in session: 0" "$(cat "${OUT}/meta.txt")"

echo "== C15: the FULL block format (first prompt, 3+ skills) renders its verdict line without Evaluate: =="
HF="${TEST_TMPDIR}/home-full"; mkdir -p "${HF}/.claude"
cp "${H}/.claude/.skill-registry-cache.json" "${HF}/.claude/.skill-registry-cache.json"
TPF="${PROJ}/p1/seed-full.jsonl"
jq -nc '{type:"user",timestamp:"2026-10-20T09:00:00Z",origin:{kind:"human"},message:{role:"user",content:"fix the flaky deploy and review the incident, then plan the rollout"}}' > "${TPF}"
FULL_BLOCK="$(jq -nc --arg t "${TPF}" '{prompt:"fix the flaky deploy and review the incident, then plan the rollout", transcript_path:$t}' \
    | env HOME="${HF}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT=off /bin/bash "${HOOK}" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""')"
rm -f "${TPF}"
assert_contains "C15 control: the real hook rendered the full format" "**Phase: [PHASE]** |" "${FULL_BLOCK}"
assert_not_contains "C15 control: whose verdict line carries no Evaluate: prefix" "Evaluate:" "${FULL_BLOCK}"
assert_contains "C15 control: and it mandates requesting-code-review" "requesting-code-review MUST INVOKE" "${FULL_BLOCK}"
PROJF="${TEST_TMPDIR}/projects-full"; mkdir -p "${PROJF}/p1"
S7="${PROJF}/p1/s7.jsonl"; : > "${S7}"
ctx   "${S7}" s0 ""  "2026-10-20T09:00:00Z" SessionStart "${START}"
uu    "${S7}" u1 s0  "2026-10-20T09:01:00Z" "fix the flaky deploy and review the incident, then plan the rollout" human
ctx   "${S7}" a1 u1  "2026-10-20T09:01:01Z" UserPromptSubmit "${FULL_BLOCK}"
skill "${S7}" x1 a1  "2026-10-20T09:01:10Z" "superpowers:requesting-code-review"
RC="$(python3 "${CENSUS}" --projects "${PROJF}" --control 0/23 --since 2026-10-20T00:00:00Z --today 2026-10-21 > "${OUT}/full.txt" 2>&1; echo $?)"
assert_equals "C15: exits 0" "0" "${RC}"
assert_contains "C15: the full-format mandate is counted" "mandates rendered: 1" "$(cat "${OUT}/full.txt")"
assert_contains "C15: as requesting-code-review, obeyed in-turn" "by skill: requesting-code-review mandates=1 in-turn=1 later=0" "$(cat "${OUT}/full.txt")"
assert_contains "C15: the prose line naming MUST INVOKE is not a second mandate" "obeyed in-turn: 1" "$(cat "${OUT}/full.txt")"

echo "== C12: compiles =="
python3 -m py_compile "${CENSUS}" 2>/dev/null
assert_equals "C12: census.py compiles" "0" "$?"

print_summary

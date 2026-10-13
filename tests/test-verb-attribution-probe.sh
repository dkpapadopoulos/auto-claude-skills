#!/usr/bin/env bash
# test-verb-attribution-probe.sh — the verb attribution census (tests/probes/compliance-census/verbs.py).
# It says WHICH trigger alternative earned each mandate of a skill on the owner's typed prompts,
# counts only. This pins what the table is made of:
#
#   V1  the named alternative is the hook's: "how should" from how.(should|would|could),
#       "set up" from set.?up, the bare verb from the alternation
#   V2  a prompt matching two alternatives counts under both and under neither as sole
#   V3  a mandate whose prompt matches no alternative is counted as unattributed, never dropped
#   V4  typed prompts but no mandate for the skill exits 3
#   V5  an unknown skill, or one with no trigger, exits 2
#   V6  the output carries counts only, never prompt text
#
# The routing block is written by the REAL activation hook; the entries around it use the
# shapes tests/test-real-prompt-replay.sh pins.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-verb-attribution-probe.sh ==="

PROBE="${PROJECT_ROOT}/tests/probes/compliance-census"
VERBS="${PROBE}/verbs.py"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
CFG="${PROJECT_ROOT}/config/default-triggers.json"
if [ ! -f "${VERBS}" ]; then
    _record_fail "probe file exists: verbs.py" "missing ${VERBS}"; print_summary; exit 1
fi
if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: jq or python3 not available — verb-attribution cells NOT run"; exit 0
fi

setup_test_env
export PYTHONDONTWRITEBYTECODE=1
H="${TEST_TMPDIR}/home"; mkdir -p "${H}/.claude"
PROJ="${TEST_TMPDIR}/projects"; mkdir -p "${PROJ}/p1"
OUT="${TEST_TMPDIR}/out"; mkdir -p "${OUT}"
jq '.skills |= map(.available = true | .enabled = true)' "${CFG}" > "${H}/.claude/.skill-registry-cache.json"

TP0="${PROJ}/p1/seed.jsonl"
jq -nc '{type:"user",timestamp:"2026-10-20T09:00:00Z",origin:{kind:"human"},message:{role:"user",content:"build a new exporter for the report module"}}' > "${TP0}"
BLOCK="$(jq -nc --arg t "${TP0}" '{prompt:"build a new exporter for the report module", transcript_path:$t}' \
    | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT=off /bin/bash "${HOOK}" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""')"
rm -f "${TP0}"
assert_contains "fixture is live: the real hook mandates brainstorming" "brainstorming MUST INVOKE" "${BLOCK}"

uu()  { jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg c "$5" --arg k "$6" \
        '{type:"user",uuid:$u,parentUuid:(if $p=="" then null else $p end),timestamp:$t,origin:{kind:$k},message:{role:"user",content:$c}}' >> "$1"; }
ctx() { jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg e "$5" --arg c "$6" \
        '{type:"attachment",uuid:$u,parentUuid:$p,timestamp:$t,attachment:{type:"hook_additional_context",hookEvent:$e,hookName:$e,content:[$c]}}' >> "$1"; }
say() { jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg x "$5" \
        '{type:"assistant",uuid:$u,parentUuid:$p,timestamp:$t,message:{role:"assistant",content:[{type:"text",text:$x}]}}' >> "$1"; }
skill() { jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg s "$5" \
        '{type:"assistant",uuid:$u,parentUuid:$p,timestamp:$t,message:{role:"assistant",content:[{type:"tool_use",id:("tu-"+$u),name:"Skill",input:{skill:$s}}]}}' >> "$1"; }
START="Plugin root: /x/cache/acsm/auto-claude-skills/3.95.8"

S1="${PROJ}/p1/s1.jsonl"; : > "${S1}"
ctx   "${S1}" s0 ""  "2026-10-20T09:00:00Z" SessionStart "${START}"
uu    "${S1}" u1 s0  "2026-10-20T09:01:00Z" "build a new exporter for the report module" human
ctx   "${S1}" a1 u1  "2026-10-20T09:01:01Z" UserPromptSubmit "${BLOCK}"
skill "${S1}" x1 a1  "2026-10-20T09:01:10Z" "superpowers:brainstorming"
uu    "${S1}" u2 x1  "2026-10-20T09:02:00Z" "design the schema and set up the repo" human
ctx   "${S1}" a2 u2  "2026-10-20T09:02:01Z" UserPromptSubmit "${BLOCK}"
say   "${S1}" x2 a2  "2026-10-20T09:02:10Z" "Thinking."
uu    "${S1}" u3 x2  "2026-10-20T09:03:00Z" "how should we approach this" human
ctx   "${S1}" a3 u3  "2026-10-20T09:03:01Z" UserPromptSubmit "${BLOCK}"
say   "${S1}" x3 a3  "2026-10-20T09:03:10Z" "Like so."
skill "${S1}" x3b x3 "2026-10-20T09:03:20Z" "superpowers:brainstorming"
uu    "${S1}" u4 x3b "2026-10-20T09:04:00Z" "ok" human
ctx   "${S1}" a4 u4  "2026-10-20T09:04:01Z" UserPromptSubmit "${BLOCK}"
say   "${S1}" x4 a4  "2026-10-20T09:04:10Z" "Proceeding."
uu    "${S1}" u5 x4  "2026-10-20T09:05:00Z" "thanks, that is all" human
say   "${S1}" x5 u5  "2026-10-20T09:05:10Z" "Done."
uu    "${S1}" u6 x5  "2026-10-20T09:06:00Z" "make it faster" human
ctx   "${S1}" a6 u6  "2026-10-20T09:06:01Z" UserPromptSubmit "${BLOCK}"
skill "${S1}" x6 a6  "2026-10-20T09:06:10Z" "superpowers:brainstorming"

run() { python3 "${VERBS}" --projects "${PROJ}" --config "${CFG}" "$@" > "${OUT}/run.txt" 2>&1; echo $?; }

echo "== V1-V3: attribution =="
RC="$(run --skill brainstorming --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z)"
assert_equals "V1: exits 0" "0" "${RC}"
assert_contains "V1: five mandates for the skill" "mandates for brainstorming: 5" "$(cat "${OUT}/run.txt")"
assert_contains "V1: the alternation verb is named bare" "alt: build mandates=1 sole=0 in-turn=1 later=0" "$(cat "${OUT}/run.txt")"
assert_contains "V1: 'how should' is one alternative, not 'should'" "alt: how should mandates=1 sole=0 in-turn=1 later=0" "$(cat "${OUT}/run.txt")"
assert_contains "V1: 'set up' is named with its space" "alt: set up mandates=1 sole=0 in-turn=0 later=1" "$(cat "${OUT}/run.txt")"
assert_contains "V2: 'new' also counts for the first prompt, and is not sole" "alt: new mandates=1 sole=0 in-turn=1 later=0" "$(cat "${OUT}/run.txt")"
assert_contains "V2: 'design' counts and is not sole (set up matched too)" "alt: design mandates=1 sole=0 in-turn=0 later=1" "$(cat "${OUT}/run.txt")"
assert_contains "V2: 'approach' counts for the third prompt" "alt: approach mandates=1 sole=0 in-turn=1 later=0" "$(cat "${OUT}/run.txt")"
assert_contains "V2: exactly one prompt was a sole match ('make it faster')" "prompts with exactly one alternative: 1" "$(cat "${OUT}/run.txt")"
assert_contains "V2: and 'make' carries that sole count with its in-turn invocation" "alt: make mandates=1 sole=1 in-turn=1 later=0" "$(cat "${OUT}/run.txt")"
assert_contains "V3: the chain-injected mandate on 'ok' is unattributed, not dropped" "unattributed (no alternative matched): 1" "$(cat "${OUT}/run.txt")"
assert_contains "V3: the unattributed line carries its own counts (the skill was invoked later, on the 'make it faster' turn)" "unattributed in-turn: 0 later: 1" "$(cat "${OUT}/run.txt")"

echo "== V4: no mandate for the skill =="
RC="$(run --skill systematic-debugging --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z)"
assert_equals "V4: typed prompts but no mandate for this skill exits 3" "3" "${RC}"
assert_contains "V4: and says cannot check" "cannot check" "$(cat "${OUT}/run.txt")"

echo "== V5: unknown skill or no trigger =="
RC="$(run --skill no-such-skill --since 2026-10-20T00:00:00Z)"
assert_equals "V5: an unknown skill exits 2" "2" "${RC}"
RC="$(run --skill writing-plans --since 2026-10-20T00:00:00Z)"
assert_equals "V5: a skill with no trigger exits 2" "2" "${RC}"
assert_contains "V5: and says why" "no trigger" "$(cat "${OUT}/run.txt")"

echo "== V6: counts only =="
RC="$(run --skill brainstorming --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z)"
assert_not_contains "V6: no prompt text in the output" "exporter for the report module" "$(cat "${OUT}/run.txt")"
assert_not_contains "V6: no prompt text in the output (2)" "schema and set up the repo" "$(cat "${OUT}/run.txt")"
python3 -m py_compile "${VERBS}" 2>/dev/null
assert_equals "V6: verbs.py compiles" "0" "$?"

print_summary

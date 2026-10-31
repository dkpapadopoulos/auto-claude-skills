#!/usr/bin/env bash
# test-hint-exposure-probe.sh — the #412 frontend hint exposure instruments
# (tests/probes/hint-exposure/; pre-registration docs/plans/2026-10-31-frontend-hint-exposure-prereg.md).
#
#   D1-D7  draw.py: stratum A from the prompt's own paired block (frontend-design on the verdict
#          line, or a hint's leading label), compaction resumes and non-typed inputs are never
#          rows, a frozen seed draws the same rows, .bak copies are merged once, the Q2 turn
#          classes, and no prompt text is written inside a repository or printed
#
# The routing block for the UI prompt is written by the REAL activation hook, as in
# tests/test-compliance-census-probe.sh; the transcript entries around it are synthetic.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-hint-exposure-probe.sh ==="

PROBE="${PROJECT_ROOT}/tests/probes/hint-exposure"
DRAW="${PROBE}/draw.py"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: jq or python3 not available — hint-exposure cells NOT run"; exit 0
fi

setup_test_env
trap teardown_test_env EXIT
export PYTHONDONTWRITEBYTECODE=1
H="${TEST_TMPDIR}/home"; mkdir -p "${H}/.claude"
PROJ="${TEST_TMPDIR}/projects"; mkdir -p "${PROJ}/p1" "${PROJ}/p2"
OUT="${TEST_TMPDIR}/out"
jq '.skills |= map(.available = true | .enabled = true)' "${PROJECT_ROOT}/config/default-triggers.json" \
    > "${H}/.claude/.skill-registry-cache.json"

UI_PROMPT="build a new settings screen with a responsive layout and a form"
TP0="${TEST_TMPDIR}/seed.jsonl"; echo '{}' > "${TP0}"
UI_BLOCK="$(jq -nc --arg t "${TP0}" --arg p "${UI_PROMPT}" '{prompt:$p, transcript_path:$t}' \
    | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT=off /bin/bash "${HOOK}" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""')"
assert_contains "fixture is live: the real hook lists frontend-design" "frontend-design YES/NO" "${UI_BLOCK}"
assert_contains "fixture is live: the real hook renders the design-seed hint" "- DESIGN SEED:" "${UI_BLOCK}"
QUALITY_BLOCK="SKILL ACTIVATION (0 skills)
- FRONTEND QUALITY: use supported product claims."
PROSE_BLOCK="SKILL ACTIVATION (0 skills)
Nothing rendered; the DESIGN SEED: hint and frontend-design are only named in this sentence."

uu() { # <file> <uuid> <parent> <ts> <text> <origin-kind|->
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
tool() { # <file> <uuid> <parent> <ts> <tool name> <input json>
    jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg n "$5" --argjson i "$6" \
        '{type:"assistant",uuid:$u,parentUuid:$p,timestamp:$t,message:{role:"assistant",content:[{type:"tool_use",id:("tu-"+$u),name:$n,input:$i}]}}' >> "$1"
}
say() { # <file> <uuid> <parent> <ts> <text>
    jq -nc --arg u "$2" --arg p "$3" --arg t "$4" --arg x "$5" \
        '{type:"assistant",uuid:$u,parentUuid:$p,timestamp:$t,message:{role:"assistant",content:[{type:"text",text:$x}]}}' >> "$1"
}

S1="${PROJ}/p1/s1.jsonl"; : > "${S1}"
ctx  "${S1}" s0 ""  "2026-10-20T09:00:00Z" SessionStart "frontend-design, DESIGN SEED: every skill listed at start"
uu   "${S1}" u0 s0  "2026-10-19T09:00:00Z" "a prompt before the window about a new screen" human
uu   "${S1}" u1 u0  "2026-10-20T09:01:00Z" "${UI_PROMPT}" human
ctx  "${S1}" a1 u1  "2026-10-20T09:01:01Z" UserPromptSubmit "${UI_BLOCK}"
tool "${S1}" x1 a1  "2026-10-20T09:01:10Z" Skill '{"skill":"frontend-design:frontend-design"}'
uu   "${S1}" u2 x1  "2026-10-20T09:02:00Z" "now tighten the spacing on that screen" human
ctx  "${S1}" a2 u2  "2026-10-20T09:02:01Z" UserPromptSubmit "${UI_BLOCK}"
tool "${S1}" x2 a2  "2026-10-20T09:02:10Z" Skill '{"skill":"frontend-design:frontend-design"}'
uu   "${S1}" u3 x2  "2026-10-20T09:03:00Z" "check how the new view looks on a phone" human
ctx  "${S1}" a3 u3  "2026-10-20T09:03:01Z" UserPromptSubmit "$(printf '%s' "${UI_BLOCK}" | sed 's/frontend-design YES\/NO/runtime-validation YES\/NO/')"
tool "${S1}" x3 a3  "2026-10-20T09:03:10Z" Bash '{"command":"npx playwright screenshot http://localhost:3000 shot.png"}'
uu   "${S1}" u4 x3  "2026-10-20T09:04:00Z" "make the form component accessible" human
ctx  "${S1}" a4 u4  "2026-10-20T09:04:01Z" UserPromptSubmit "${QUALITY_BLOCK}"
uu   "${S1}" u5 a4  "2026-10-20T09:05:00Z" "<task-notification>ui job finished</task-notification>" task-notification
ctx  "${S1}" a5 u5  "2026-10-20T09:05:01Z" UserPromptSubmit "${UI_BLOCK}"
uu   "${S1}" c1 a5  "2026-10-20T09:06:00Z" "This session is being continued from a previous conversation about the settings screen" -
ctx  "${S1}" c2 c1  "2026-10-20T09:06:01Z" SessionStart "frontend-design, DESIGN SEED: every skill listed at start"
uu   "${S1}" b1 c2  "2026-10-20T09:07:00Z" "rename the export job" human
uu   "${S1}" b2 b1  "2026-10-20T09:08:00Z" "what does the census say" human
uu   "${S1}" bp b2  "2026-10-20T09:09:00Z" "tell me about the routing block" human
ctx  "${S1}" ap bp  "2026-10-20T09:09:01Z" UserPromptSubmit "${PROSE_BLOCK}"
uu   "${S1}" b3 ap  "2026-10-20T09:10:00Z" "list the open issues" human
# s2: pruned; the earlier prompt survives only in the .bak, and one entry is in both copies.
S2="${PROJ}/p2/s2.jsonl"
uu   "${PROJ}/p2/s2.20261020T120000.jsonl.bak" k1 "" "2026-10-20T10:00:00Z" "a prompt only the backup still holds" human
uu   "${PROJ}/p2/s2.20261020T120000.jsonl.bak" k2 k1 "2026-10-20T10:01:00Z" "a prompt in both copies" human
uu   "${S2}" k2 k1 "2026-10-20T10:01:00Z" "a prompt in both copies" human
# s3: a resumed session that copied an entry of s1 under the same uuid.
uu   "${PROJ}/p2/s3.jsonl" b1 "" "2026-10-20T09:07:00Z" "rename the export job" human
rm -f "${TP0}"

draw() { python3 "${DRAW}" --projects "${PROJ}" --since 2026-10-20T00:00:00Z --until 2026-10-21T00:00:00Z \
    --n-b 3 "$@" > "${OUT}.log" 2>&1; echo $?; }
row() { jq -c --arg p "$1" "select(.prompt == \$p) | $2" "${OUT}/rows.jsonl" 2>/dev/null; }

echo "== D1-D3: strata come from the prompt's own block =="
RC="$(draw --seed 1 --out-dir "${OUT}")"
assert_equals "D1: a readable corpus exits 0" "0" "${RC}"
assert_equals "D1: the UI prompt is stratum A" '"A"' "$(row "${UI_PROMPT}" .stratum)"
assert_equals "D1: its routes, in route order" '["frontend-design","frontend-playwright","design-seed"]' "$(row "${UI_PROMPT}" .routes)"
assert_equals "D1: stratum A has weight 1" "true" "$(row "${UI_PROMPT}" '.weight == 1')"
assert_equals "D2: a hint's leading label puts the prompt in A for that hint" '["frontend-quality-rules"]' "$(row "make the form component accessible" .routes)"
assert_equals "D2: a label named mid-sentence is not a render" "" "$(row "tell me about the routing block" .routes | grep -v '^\[\]$')"
assert_equals "D3: a compaction resume is never a row" "0" "$(grep -c 'being continued' "${OUT}/rows.jsonl")"
assert_equals "D3: a notification with a block is never a row" "0" "$(grep -c 'task-notification' "${OUT}/rows.jsonl")"
assert_equals "D3: a prompt before the window is never a row" "0" "$(grep -c 'before the window' "${OUT}/rows.jsonl")"
assert_equals "D3: four A rows and three sampled B rows" "4 3" \
    "$(jq -rs '[(map(select(.stratum=="A")) | length), (map(select(.stratum=="B")) | length)] | map(tostring) | join(" ")' "${OUT}/rows.jsonl")"
assert_contains "D3: the log reports the strata" "stratum B: 6 sampled 3" "$(cat "${OUT}.log")"
assert_equals "D3: the replay input has one line per row, in row order" \
    "$(jq -c .prompt "${OUT}/rows.jsonl")" "$(jq -c .prompt "${OUT}/prompts.jsonl")"
assert_equals "D3: ids are r00001.. in order" "r00001" "$(head -1 "${OUT}/rows.jsonl" | jq -r .id)"

echo "== D4: the frozen seed decides the sample =="
cp "${OUT}/rows.jsonl" "${TEST_TMPDIR}/rows-seed1.jsonl"
draw --seed 1 --out-dir "${OUT}" > /dev/null
assert_equals "D4: the same seed draws byte-identical rows" "same" \
    "$(cmp -s "${OUT}/rows.jsonl" "${TEST_TMPDIR}/rows-seed1.jsonl" && echo same || echo differ)"
_differ=0
for _s in 2 3 4 5 6; do
    draw --seed "${_s}" --out-dir "${OUT}" > /dev/null
    cmp -s "${OUT}/rows.jsonl" "${TEST_TMPDIR}/rows-seed1.jsonl" || _differ=1
done
assert_equals "D4: another seed draws another sample" "1" "${_differ}"
assert_equals "D4: B weight is N_B/n_B (6/3)" "true" \
    "$(jq -r 'select(.stratum=="B") | .weight == 2' "${OUT}/rows.jsonl" | sort -u | tr -d '\n')"

echo "== D5: .bak copies =="
draw --seed 1 --n-b 50 --out-dir "${OUT}" > /dev/null
assert_equals "D5: a prompt only the backup holds is a row" "1" "$(grep -c 'only the backup' "${OUT}/rows.jsonl")"
assert_equals "D5: an entry in both copies is one row" "1" "$(grep -c 'in both copies' "${OUT}/rows.jsonl")"
assert_equals "D5: a uuid copied into another session is one row" "1" "$(grep -c 'rename the export job' "${OUT}/rows.jsonl")"

echo "== D6: Q2 turn classes =="
assert_equals "D6: invoked in the prompt's turn" '{"frontend-design":"in-turn"}' "$(row "${UI_PROMPT}" .q2)"
assert_equals "D6: invoked before the prompt, even when invoked again in-turn" '{"frontend-design":"loaded-earlier"}' "$(row "now tighten the spacing on that screen" .q2)"
assert_equals "D6: a screenshot run with no invocation" '{"runtime-validation":"direct-validation"}' "$(row "check how the new view looks on a phone" .q2)"
assert_equals "D6: only frontend-design and runtime-validation are tracked" '["runtime-validation"]' "$(row "check how the new view looks on a phone" .listed)"

echo "== D7: privacy =="
INREPO="${PROBE}/out-test-$$"
RC="$(draw --seed 1 --out-dir "${INREPO}")"
assert_equals "D7: an output directory inside a repository is refused" "2" "${RC}"
assert_equals "D7: ... and nothing is written there" "absent" "$([ -e "${INREPO}" ] && echo present || echo absent)"
rm -rf "${INREPO}"
draw --seed 1 --out-dir "${OUT}" > /dev/null
assert_equals "D7: the log carries no prompt text" "0" "$(grep -c 'settings screen\|export job' "${OUT}.log")"
assert_equals "D7: rows.jsonl is private" "600" "$(stat -f '%Lp' "${OUT}/rows.jsonl" 2>/dev/null || stat -c '%a' "${OUT}/rows.jsonl")"
assert_contains "D7: the log names the manifest by hash only" "manifest sha256:" "$(cat "${OUT}.log")"

print_summary

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

# --- S1-S9: the scorer (D1, D3) and the Q1 replay orchestration --------------------------
SCORE="${PROBE}/score.py"
Q1="${PROBE}/q1.sh"
# mkdraw <dir> <spec json>: a draw dir for the route frontend-design from a spec
# {"rows": [{"s": "A"|"B", "w": weight, "named": bool, "l1": .., "l2": .., "owner": ..?,
#  "m": {"V0": 0|1, "V1": 0|1, "V2": 0|1}}], "V1": [...], "V2": [...]}; V0 is ["v0"].
mkdraw() {
    python3 - "$1" "$2" <<'PY'
import json, os, sys
d, spec = sys.argv[1], json.loads(sys.argv[2])
os.makedirs(d, exist_ok=True)
rows = spec["rows"]
with open(os.path.join(d, "rows.jsonl"), "w") as f:
    for n, r in enumerate(rows, 1):
        f.write(json.dumps({"id": "r%05d" % n, "stratum": r["s"], "weight": r["w"], "prompt": "p%d" % n,
                            "named": r.get("named", False), "routes": [], "listed": r.get("listed", []),
                            "q2": r.get("q2", {})}) + "\n")
for who in ("l1", "l2", "owner"):
    with open(os.path.join(d, who + ".tsv"), "w") as f:
        for n, r in enumerate(rows, 1):
            if who in r:
                f.write("r%05d\t%s\n" % (n, r[who]))
for v in ("V0", "V1", "V2"):
    os.makedirs(os.path.join(d, "replay-frontend-design-" + v), exist_ok=True)
    with open(os.path.join(d, "replay-frontend-design-" + v, "hits.tsv"), "w") as f:
        for n, r in enumerate(rows, 1):
            if r["m"].get(v):
                f.write("%d\t0\n" % n)
json.dump({"routes": {"frontend-design": {"kind": "skill", "V0": ["v0"], "V1": spec.get("V1", ["v1"]),
                                          "V2": spec.get("V2", ["v2"])}}}, open(os.path.join(d, "variants.json"), "w"))
PY
}
score() { # <dir> [extra args]: prints the output, then "rc=<code>"
    local d="$1"; shift
    python3 "${SCORE}" --draw-dir "${d}" --variants "${d}/variants.json" --labels "${d}/l1.tsv" "${d}/l2.tsv" \
        --seed 7 --resamples 2000 "$@" 2>&1
    echo "rc=$?"
}
# rows <count> <json row>: the row repeated, comma-joined.
rows() { local i=0 out=""; while [ "${i}" -lt "$1" ]; do out="${out}${out:+,}$2"; i=$((i + 1)); done; printf '%s' "${out}"; }

echo "== S1: weighted precision and recall =="
mkdraw "${TEST_TMPDIR}/s1" '{"rows":[
 {"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":1,"V1":1,"V2":1}},
 {"s":"A","w":1,"l1":"NOT","l2":"NOT","m":{"V0":1,"V1":1,"V2":1}},
 {"s":"B","w":10,"l1":"UI","l2":"UI","m":{"V0":0,"V1":0,"V2":0}}]}'
S_OUT="$(score "${TEST_TMPDIR}/s1")"
assert_contains "S1: precision = sum w.UI.m / sum w.m, recall = sum w.UI.m / sum w.UI" \
    "frontend-design V0: precision 0.5000 recall 0.0909" "${S_OUT}"
assert_contains "S1: raw stratum counts are reported" "stratum A rows 2 ui 1 match 2 ui&match 1; stratum B rows 1 ui 1 match 0 ui&match 0" "${S_OUT}"

echo "== S2: a variant identical to V0 =="
mkdraw "${TEST_TMPDIR}/s2" '{"V1":["v0"],"rows":[
 {"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":1,"V1":1,"V2":0}},
 {"s":"A","w":1,"l1":"NOT","l2":"NOT","m":{"V0":1,"V1":1,"V2":0}}]}'
assert_contains "S2: an identical variant is reported as such, not scored" "D1 frontend-design V1: identical-to-V0" "$(score "${TEST_TMPDIR}/s2")"

echo "== S3: a variant that wins on both =="
UI1='{"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":1,"V1":1,"V2":0}}'
UI2='{"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":0,"V1":1,"V2":0}}'
NO1='{"s":"A","w":1,"l1":"NOT","l2":"NOT","m":{"V0":1,"V1":0,"V2":0}}'
NO2='{"s":"A","w":1,"l1":"NOT","l2":"NOT","m":{"V0":0,"V1":0,"V2":0}}'
mkdraw "${TEST_TMPDIR}/s3" "{\"rows\":[$(rows 10 "${UI1}"),$(rows 10 "${UI2}"),$(rows 10 "${NO1}"),$(rows 10 "${NO2}")]}"
S_OUT="$(score "${TEST_TMPDIR}/s3")"
assert_contains "S3: recall and precision both up" "D1 frontend-design V1: qualifies-A+B" "${S_OUT}"
assert_contains "S3: a variant matching nothing is cannot-check" "D1 frontend-design V2: cannot-check" "${S_OUT}"
assert_contains "S3: qualifying variants are ranked" "rank frontend-design: V1" "${S_OUT}"

echo "== S4: labels =="
mkdraw "${TEST_TMPDIR}/s4" '{"rows":[
 {"s":"A","w":1,"l1":"UI","l2":"NOT","m":{"V0":1,"V1":1,"V2":1}},
 {"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":1,"V1":1,"V2":1}}]}'
S_OUT="$(score "${TEST_TMPDIR}/s4")"
assert_contains "S4: an unresolved disagreement is cannot-check" "rc=3" "${S_OUT}"
assert_contains "S4: ... and is counted" "labels: rows 2 agreed 1 owner-resolved 0 unresolved 1" "${S_OUT}"
printf 'r00001\tNOT\n' > "${TEST_TMPDIR}/s4/owner.tsv"
S_OUT="$(score "${TEST_TMPDIR}/s4" --owner "${TEST_TMPDIR}/s4/owner.tsv")"
assert_contains "S4: the owner breaks the tie" "labels: rows 2 agreed 1 owner-resolved 1 unresolved 0" "${S_OUT}"
assert_contains "S4: ... and the majority label is used" "frontend-design V0: precision 0.5000 recall 1.0000" "${S_OUT}"
mkdraw "${TEST_TMPDIR}/s4m" '{"rows":[
 {"s":"A","w":1,"l1":"MALFORMED","l2":"MALFORMED","m":{"V0":1,"V1":1,"V2":1}},
 {"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":1,"V1":1,"V2":1}}]}'
assert_contains "S4: two MALFORMED answers are not an agreement" "unresolved 1" "$(score "${TEST_TMPDIR}/s4m")"

echo "== S5: no UI rows =="
mkdraw "${TEST_TMPDIR}/s5" '{"rows":[{"s":"A","w":1,"l1":"NOT","l2":"NOT","m":{"V0":1,"V1":1,"V2":1}}]}'
S_OUT="$(score "${TEST_TMPDIR}/s5")"
assert_contains "S5: an undefined V0 recall is cannot-check" "D1 frontend-design V1: cannot-check" "${S_OUT}"
assert_contains "S5: ... and exits 3" "rc=3" "${S_OUT}"

echo "== S6: determinism =="
assert_equals "S6: the same seed gives byte-identical output" "$(score "${TEST_TMPDIR}/s3")" "$(score "${TEST_TMPDIR}/s3")"

echo "== S7: an unreachable branch =="
HIT='{"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":1,"V1":1,"V2":1}}'
MISS='{"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":0,"V1":0,"V2":1}}'
mkdraw "${TEST_TMPDIR}/s7" "{\"rows\":[$(rows 9 "${HIT}"),${MISS}]}"
S_OUT="$(score "${TEST_TMPDIR}/s7")"
assert_contains "S7: V0 recall above 0.85 makes branch A unreachable" "unreachable: A" "${S_OUT}"
assert_contains "S7: V0 precision 1 makes branch B unreachable" "unreachable: A B" "${S_OUT}"

echo "== S8: resamples with an undefined quantity =="
ONE='{"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":0,"V1":1,"V2":1}}'
NOTS='{"s":"A","w":1,"l1":"NOT","l2":"NOT","m":{"V0":1,"V1":0,"V2":0}}'
mkdraw "${TEST_TMPDIR}/s8" "{\"rows\":[${ONE},$(rows 19 "${NOTS}")]}"
S_OUT="$(score "${TEST_TMPDIR}/s8")"
assert_contains "S8: dropped resamples are counted" "dropped" "${S_OUT}"
assert_contains "S8: more than 5% dropped makes the verdict inconclusive" "D1 frontend-design V1: inconclusive" "${S_OUT}"
assert_contains "S8: ... and is not an error" "rc=0" "${S_OUT}"

echo "== S10: branch B needs a strict precision gain =="
SAME_UI='{"s":"A","w":1,"l1":"UI","l2":"UI","m":{"V0":1,"V1":1,"V2":1}}'
SAME_NOT='{"s":"A","w":1,"l1":"NOT","l2":"NOT","m":{"V0":1,"V1":1,"V2":1}}'
mkdraw "${TEST_TMPDIR}/s10" "{\"rows\":[$(rows 10 "${SAME_UI}"),$(rows 10 "${SAME_NOT}")]}"
assert_contains "S10: different triggers matching the same rows do not qualify" "D1 frontend-design V1: fails" "$(score "${TEST_TMPDIR}/s10")"

echo "== S9: q1.sh writes one config per route and variant and replays it =="
Q1D="${TEST_TMPDIR}/q1"; mkdir -p "${Q1D}"
jq -nc '{prompt:"build a new settings screen"}' > "${Q1D}/prompts.jsonl"
jq -nc '{prompt:"rename the export job"}' >> "${Q1D}/prompts.jsonl"
jq -n '{routes:{"design-seed":{kind:"hint",V0:["screen"],V1:["export"],V2:["screen"]}}}' > "${Q1D}/variants.json"
bash "${Q1}" "${Q1D}/variants.json" "${PROJECT_ROOT}/config/default-triggers.json" "${Q1D}" < /dev/null > "${Q1D}.log" 2>&1
assert_equals "S9: q1.sh exits 0" "0" "$?"
assert_equals "S9: only the route's triggers differ from the base config" \
    "$(jq -S 'del(.methodology_hints[] | select(.name=="design-seed") | .triggers)' "${PROJECT_ROOT}/config/default-triggers.json")" \
    "$(jq -S 'del(.methodology_hints[] | select(.name=="design-seed") | .triggers)' "${Q1D}/cfg-design-seed-V1.json")"
assert_equals "S9: the variant's triggers are the appendix's" '["export"]' \
    "$(jq -c '.methodology_hints[] | select(.name=="design-seed") | .triggers' "${Q1D}/cfg-design-seed-V1.json")"
assert_equals "S9: V0 hits line 1" "$(printf '1\t0')" "$(cat "${Q1D}/replay-design-seed-V0/hits.tsv")"
assert_equals "S9: V1 hits line 2" "$(printf '2\t0')" "$(cat "${Q1D}/replay-design-seed-V1/hits.tsv")"

# --- L1-L4: the labeller harness (D2), against a stub claude ------------------------------
LABEL="${PROBE}/label.py"
STUB="${TEST_TMPDIR}/stub-claude"
cat > "${STUB}" <<'PY'
#!/usr/bin/env python3
# A stand-in for `claude -p`: answers UI for every row id it is sent, shaped by STUB_MODE,
# and records its environment and input per call under STUB_LOG.
import json, os, re, sys
if "--version" in sys.argv:
    print("9.9.9 (stub)"); sys.exit(0)
text = sys.stdin.read()
log = os.environ["STUB_LOG"]; os.makedirs(log, exist_ok=True)
n = len(os.listdir(log))
json.dump({"env": dict(os.environ), "argv": sys.argv, "cwd": os.getcwd(), "input": text},
          open(os.path.join(log, "call-%03d.json" % n), "w"))
ids = re.findall(r"^(r\d{5})\t", text, re.M)
mode = os.environ.get("STUB_MODE", "ok")
lines = []
for k, i in enumerate(ids):
    if mode == "omit-first" and k == 0:
        continue
    if mode == "junk-first" and k == 0:
        lines.append(i + "\tMAYBE"); continue
    lines.append(i + "\tUI")
if mode == "junk-first":
    lines.append("r99999\tUI")
if mode == "poach":
    lines += [r + "\tNOT" for r in ("r00001", "r00002", "r00003", "r00004", "r00005") if r not in ids]
print(json.dumps({"result": "\n".join(lines)}))
PY
chmod +x "${STUB}"
LBD="${TEST_TMPDIR}/lab"; mkdir -p "${LBD}"
for _i in 1 2 3 4 5; do jq -nc --arg i "r0000${_i}" '{id:$i,stratum:"A",weight:1,prompt:("prompt "+$i)}'; done > "${LBD}/rows.jsonl"
PREREG="${PROJECT_ROOT}/docs/plans/2026-10-31-frontend-hint-exposure-prereg.md"
if [ ! -f "${PREREG}" ]; then
    PREREG="${TEST_TMPDIR}/prereg.md"
    printf '# x\n<!-- RUBRIC-BEGIN -->\nLabel each message UI or NOT.\n<!-- RUBRIC-END -->\n' > "${PREREG}"
fi
label() { # <mode> [extra args]
    local mode="$1"; shift
    env STUB_MODE="${mode}" STUB_LOG="${TEST_TMPDIR}/log-${mode}" CLAUDE_CODE_PROBE_MARKER=1 \
        python3 "${LABEL}" --draw-dir "${LBD}" --prereg "${PREREG}" --model stub-model --labeller L1 \
        --batch 2 --seed 3 --jobs 1 --claude "${STUB}" "$@" > "${LBD}/label.log" 2>&1
    echo $?
}
echo "== L1: a complete answer =="
assert_equals "L1: exits 0" "0" "$(label ok)"
assert_equals "L1: every row labelled, in id order" "$(printf 'r00001\tUI\nr00002\tUI\nr00003\tUI\nr00004\tUI\nr00005\tUI')" "$(cat "${LBD}/L1.tsv")"
assert_equals "L1: three batches of at most two rows" "3" "$(ls "${TEST_TMPDIR}/log-ok" | wc -l | tr -d ' ')"
assert_contains "L1: the rubric is sent verbatim" "$(sed -n '/<!-- RUBRIC-BEGIN -->/,/<!-- RUBRIC-END -->/p' "${PREREG}" | sed '1d;$d' | head -1)" \
    "$(jq -r .input "${TEST_TMPDIR}/log-ok/call-000.json")"
assert_equals "L1: the manifest names the model and the rubric hash" "stub-model true" \
    "$(jq -r '"\(.model) \(.rubric_sha256 | test("^[0-9a-f]{64}$"))"' "${LBD}/L1-manifest.json")"
echo "== L2: a dropped row is re-asked once, then MALFORMED =="
label omit-first > /dev/null
assert_equals "L2: each batch is asked twice (the retry also omits)" "6" "$(ls "${TEST_TMPDIR}/log-omit-first" | wc -l | tr -d ' ')"
assert_equals "L2: three rows end MALFORMED, two are labelled" "3 2" \
    "$(printf '%s %s' "$(grep -c 'MALFORMED' "${LBD}/L1.tsv")" "$(grep -c 'UI$' "${LBD}/L1.tsv")")"
echo "== L3: an invented id or answer never becomes a row =="
label junk-first > /dev/null
assert_equals "L3: still five rows" "5" "$(grep -c . "${LBD}/L1.tsv")"
assert_equals "L3: no invented id" "0" "$(grep -c r99999 "${LBD}/L1.tsv")"
assert_equals "L3: an answer outside UI|NOT is MALFORMED after the retry" "0" "$(grep -c MAYBE "${LBD}/L1.tsv")"
label poach > /dev/null
assert_equals "L3: an answer for a row sent in another batch is ignored" "0" "$(grep -c NOT "${LBD}/L1.tsv")"
echo "== L4: isolation =="
_call="${TEST_TMPDIR}/log-ok/call-000.json"
assert_equals "L4: no CLAUDE* variable reaches the labeller" "0" "$(jq '[.env | keys[] | select(startswith("CLAUDE"))] | length' "${_call}")"
assert_equals "L4: the labeller runs in its own HOME" "true" "$(jq --arg h "${HOME}" '.env.HOME != $h' "${_call}")"
assert_equals "L4: ... and an empty working directory outside the repository" "true" \
    "$(jq --arg r "${PROJECT_ROOT}" '.cwd | startswith($r) | not' "${_call}")"
assert_contains "L4: the labeller has no tools" "Bash,Read" "$(jq -r '.argv | join(" ")' "${_call}")"
assert_equals "L4: a draw dir inside a repository is refused" "2" \
    "$(python3 "${LABEL}" --draw-dir "${PROBE}" --prereg "${PREREG}" --model m --labeller L1 --claude "${STUB}" > /dev/null 2>&1; echo $?)"

print_summary

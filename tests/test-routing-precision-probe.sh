#!/usr/bin/env bash
# test-routing-precision-probe.sh — the instruments of the sticky-repeat experiment (#333),
# tests/probes/routing-precision/. Their numbers decide whether a display rule is turned on,
# so this pins what the numbers are made of:
#
#   J*  rows.py joins the hook's shadow record to the prompt it was written for, keeps the
#       labeller BLIND to everything about the rule, counts what it could not use, and
#       refuses to write prompt text into a git repository
#   S*  score.py: each threshold decides the verdict it is said to decide, the K2
#       denominator is ALL hidden rows, and missing or too-thin data is INCONCLUSIVE,
#       never a pass
#   T*  trial.py: an obligation is counted per (session, gated skill), in both arms,
#       whether or not the session ever pushed
#
# The shadow records in J* and T1 are written by the REAL activation hook, never by hand:
# a hand-written record only proves the reader agrees with this file's idea of the format.
# The transcript entries are synthetic, in the shapes tests/test-real-prompt-replay.sh pins.
# S* and T2 use constructed keys and logs: those formats are this probe's own.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-routing-precision-probe.sh ==="

PROBE="${PROJECT_ROOT}/tests/probes/routing-precision"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
for _f in common.py rows.py score.py trial.py rubric.md README.md; do
    if [ ! -f "${PROBE}/${_f}" ]; then
        _record_fail "probe file exists: ${_f}" "missing ${PROBE}/${_f}"; print_summary; exit 1
    fi
done
if ! command -v jq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: jq or python3 not available — routing-precision probe cells NOT run"; exit 0
fi

setup_test_env
export PYTHONDONTWRITEBYTECODE=1
H="${TEST_TMPDIR}/home"; mkdir -p "${H}/.claude"
PROJ="${TEST_TMPDIR}/projects"; mkdir -p "${PROJ}/p1"
LOG="${H}/.claude/.sticky-repeat-shadow.d"     # the hook writes one small file per record here
jq '.skills |= map(.available = true | .enabled = true)' "${PROJECT_ROOT}/config/default-triggers.json" \
    > "${H}/.claude/.skill-registry-cache.json"
OUT="${TEST_TMPDIR}/out"; mkdir -p "${OUT}"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# One transcript entry each. TP is the session's transcript.
t_user()   { jq -nc --arg t "$(now)" --arg p "$1" '{type:"user",timestamp:$t,origin:{kind:"human"},message:{role:"user",content:$p}}' >> "${TP}"; }
t_say()    { jq -nc --arg t "$(now)" --arg x "$1" '{type:"assistant",timestamp:$t,message:{role:"assistant",content:[{type:"text",text:$x}]}}' >> "${TP}"; }
t_skill()  { jq -nc --arg t "$(now)" --arg s "$1" '{type:"assistant",timestamp:$t,message:{role:"assistant",content:[{type:"tool_use",id:"sk1",name:"Skill",input:{skill:$s}}]}}' >> "${TP}"; }
t_bash()   { jq -nc --arg t "$(now)" --arg i "$1" --arg c "$2" '{type:"assistant",timestamp:$t,message:{role:"assistant",content:[{type:"tool_use",id:$i,name:"Bash",input:{command:$c}}]}}' >> "${TP}"; }
t_result() { jq -nc --arg t "$(now)" --arg i "$1" --arg x "$2" '{type:"user",timestamp:$t,message:{role:"user",content:[{type:"tool_result",tool_use_id:$i,content:$x}]}}' >> "${TP}"; }
# prompt <mode> <text> : the user types it (transcript), then the REAL hook handles it.
# The pause keeps consecutive prompts in different seconds, as real ones are.
prompt() {
    sleep 1.1
    t_user "$2"
    jq -nc --arg p "$2" --arg t "${TP}" '{prompt:$p, transcript_path:$t}' \
        | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT="$1" /bin/bash "${HOOK}" >/dev/null 2>&1
}
session() { TP="${PROJ}/p1/$1.jsonl"; : > "${TP}"; }

# --- J: rows.py ---------------------------------------------------------------------
echo "== J: rows.py =="
SINCE="$(now)"
sleep 1.1
session aaaa0
prompt shadow "build a new exporter for the report module"
t_say "Two designs are possible. Which design do you want?"
prompt shadow "go"
t_skill "superpowers:brainstorming"
t_say "Brainstorming done."
prompt shadow "what time is it in the city of london right now"   # too long to be sticky, selects nothing: no record
t_say "I cannot tell."
prompt shadow "yes"
t_say "Planning."
RECS="$(ls "${LOG}" 2>/dev/null | grep -c '\.json$')"
assert_equals "J setup: the real hook wrote one record per mandated prompt (3 of the 4 prompts)" "3" "${RECS}"

python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${OUT}/rows.jsonl" --key "${OUT}/key.jsonl" > "${OUT}/rows.txt" 2>&1
assert_equals "J1: rows.py exits 0" "0" "$?"
assert_equals "J1: one row per record" "3" "$(grep -c . "${OUT}/rows.jsonl" 2>/dev/null)"
assert_equals "J1: and one key line per row" "3" "$(grep -c . "${OUT}/key.jsonl" 2>/dev/null)"
assert_equals "J2: the same row ids, in the same order, in both files" \
    "$(jq -r '.row_id' "${OUT}/rows.jsonl" | tr '\n' ' ')" "$(jq -r '.row_id' "${OUT}/key.jsonl" | tr '\n' ' ')"

# BLINDING: the labeller's file may say nothing about the rule.
_leak="$(jq -r 'keys[]' "${OUT}/rows.jsonl" | sort -u | grep -E '^(sticky|already_shown|would_hide|hidden_by_rule|new_chain|arm|mode|displayed|other_suppression|invoked_same_turn|invoked_later|block_chars|session|ts|chain|prompt_count)$' | tr '\n' ' ')"
assert_equals "J3: the labeller's rows carry no field about the rule, the session or the outcome" "" "${_leak}"
assert_equals "J3: they carry exactly these fields" \
    "earlier_prompts previous_assistant_message_tail process_skills_already_invoked_this_session prompt row_id skill tools_used_since_the_previous_prompt" \
    "$(jq -r 'keys[]' "${OUT}/rows.jsonl" | sort -u | tr '\n' ' ' | sed 's/ $//')"

# The join: each record lands on the prompt the hook was handling, not a neighbour.
_go="$(jq -r 'select(.prompt == "go") | .row_id' "${OUT}/rows.jsonl")"
assert_not_empty "J4: the 'go' prompt has a row" "${_go}"
assert_equals "J4: its key says the rule would hide it, and that the skill was invoked the same turn" "true true true" \
    "$(jq -r --arg i "${_go}" 'select(.row_id == $i) | [.sticky,.would_hide,.invoked_same_turn] | map(tostring) | join(" ")' "${OUT}/key.jsonl")"
assert_contains "J4: its row shows what the assistant had just asked" "Which design do you want?" \
    "$(jq -r --arg i "${_go}" 'select(.row_id == $i) | .previous_assistant_message_tail' "${OUT}/rows.jsonl")"
assert_equals "J4: and the prompt before it" "build a new exporter for the report module" \
    "$(jq -r --arg i "${_go}" 'select(.row_id == $i) | .earlier_prompts | join("|")' "${OUT}/rows.jsonl")"
_arm="$(jq -r 'select(.prompt | startswith("build a new exporter")) | .row_id' "${OUT}/rows.jsonl")"
assert_equals "J5: the arming prompt's key says its own words selected the skill, first display" "false false false" \
    "$(jq -r --arg i "${_arm}" 'select(.row_id == $i) | [.sticky,.already_shown,.would_hide] | map(tostring) | join(" ")' "${OUT}/key.jsonl")"
_yes="$(jq -r 'select(.prompt == "yes") | .row_id' "${OUT}/rows.jsonl")"
assert_equals "J6: 'yes' joined to its own record, not to the unrecorded prompt before it" "brainstorming" \
    "$(jq -r --arg i "${_yes}" 'select(.row_id == $i) | .process_skills_already_invoked_this_session | join(",")' "${OUT}/rows.jsonl")"
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1" 2>/dev/null; }
assert_equals "J7: both outputs are private (0600)" "600 600" "$(mode_of "${OUT}/rows.jsonl") $(mode_of "${OUT}/key.jsonl")"

# What it could not use is COUNTED.
printf '%s\n' '{"schema_version":1,"ts":"'"$(now)"'","session":"session-nosuchsession","skill":"brainstorming","would_hide":true,"mode":"shadow","rule_version":2,"displayed":true,"skills_in_block":1}' > "${LOG}/hand-1.json"
printf '%s\n' 'not json at all' > "${LOG}/hand-2.json"
python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${OUT}/rows2.jsonl" --key "${OUT}/key2.jsonl" > "${OUT}/rows2.txt" 2>&1
assert_contains "J8: a record with no transcript is counted" "     1  no transcript" "$(cat "${OUT}/rows2.txt")"
assert_contains "J8: a malformed line is counted" "     1  malformed lines" "$(cat "${OUT}/rows2.txt")"
assert_equals "J8: and neither becomes a row" "3" "$(grep -c . "${OUT}/rows2.jsonl")"

# Only shadow-mode records are stage A rows: in trial or suppress mode blocks were really hidden.
printf '%s\n' '{"schema_version":1,"ts":"'"$(now)"'","session":"session-aaaa0","skill":"brainstorming","would_hide":true,"mode":"trial"}' > "${LOG}/hand-3.json"
python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${OUT}/rows2b.jsonl" --key "${OUT}/key2b.jsonl" > "${OUT}/rows2b.txt" 2>&1
assert_contains "J8: a record from a non-shadow mode is excluded, and counted" "     1  not shadow mode" "$(cat "${OUT}/rows2b.txt")"
assert_equals "J8: and does not become a row" "3" "$(grep -c . "${OUT}/rows2b.jsonl")"
printf '%s\n' '{"schema_version":1,"rule_version":1,"ts":"'"$(now)"'","session":"session-aaaa0","skill":"brainstorming","would_hide":true,"mode":"shadow","displayed":true,"skills_in_block":1}' > "${LOG}/hand-4.json"
python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${OUT}/rows2c.jsonl" --key "${OUT}/key2c.jsonl" > "${OUT}/rows2c.txt" 2>&1
assert_contains "J8: a record written by another version of the rule is excluded, and counted" "     1  another rule version" "$(cat "${OUT}/rows2c.txt")"
# A current-version record always carries the number of skills in its block. One without it
# was not written by the hook this reader was frozen with, and is not read as "zero skills".
printf '%s\n' '{"schema_version":1,"rule_version":2,"ts":"'"$(now)"'","session":"session-aaaa0","skill":"brainstorming","would_hide":true,"mode":"shadow","displayed":true}' > "${LOG}/hand-6.json"
python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${OUT}/rows2d.jsonl" --key "${OUT}/key2d.jsonl" > "${OUT}/rows2d.txt" 2>&1
assert_contains "J13: a current-version record with no skills_in_block is counted as malformed" "     2  malformed lines" "$(cat "${OUT}/rows2d.txt")"
assert_equals "J13: and does not become a row" "3" "$(grep -c . "${OUT}/rows2d.jsonl")"
rm -f "${LOG}/hand-6.json"
assert_equals "J8: the real hook's records are rule version 2, the version the readers accept" "2" "$(cat "${LOG}"/session-aaaa0.*.json | jq -r '.rule_version' | sort -u | tr '\n' ' ' | sed 's/ $//')"

# A record of the wrong SHAPE must exit 2 as well: a session that is a number raised
# AttributeError, and an uncaught exception exits 1, which a caller reads as a decision.
mkdir -p "${OUT}/shape.d"; printf '%s\n' '{"schema_version":1,"rule_version":2,"ts":"'"$(now)"'","session":5,"skill":"brainstorming","would_hide":true,"mode":"shadow","displayed":true,"skills_in_block":1}' > "${OUT}/shape.d/x.json"
python3 "${PROBE}/rows.py" --shadow-log "${OUT}/shape.d" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${OUT}/rows10.jsonl" --key "${OUT}/key10.jsonl" > "${OUT}/rows10.txt" 2>&1
assert_equals "J14: a record whose session is not a string exits 2" "2" "$?"

# The freeze boundary is the SESSION's start.
python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "$(now)" --projects "${PROJ}" \
    --rows "${OUT}/rows3.jsonl" --key "${OUT}/key3.jsonl" > "${OUT}/rows3.txt" 2>&1
assert_equals "J9: with the freeze after the session started, no row is produced" "0" "$(grep -c . "${OUT}/rows3.jsonl")"
session bbbb0
t_user "an old prompt from before the freeze"       # the session STARTS before the freeze below
sleep 1.1; MID="$(now)"
prompt shadow "build a new importer for the billing module"
python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "${MID}" --projects "${PROJ}" \
    --rows "${OUT}/rows4.jsonl" --key "${OUT}/key4.jsonl" > "${OUT}/rows4.txt" 2>&1
assert_contains "J9: a record written after the freeze in a session that started before it is excluded, and counted" \
    "     1  session started before the freeze" "$(cat "${OUT}/rows4.txt")"

# A row is a block the USER'S typed prompt was shown. A peer session's message reaches the
# same hook: its block is hidden by another rule and the hook records it, but it is not a
# row. Two independent filters hold that (the record says the block was not displayed; the
# transcript says the prompt was not typed), so each is exercised on its own.
session dddd0
sleep 1.1
jq -nc --arg t "$(now)" --rawfile p "${PROJECT_ROOT}/tests/fixtures/routing-input/peer-teammate.txt" \
    '{type:"user",timestamp:$t,origin:{kind:"peer"},message:{role:"user",content:$p}}' >> "${TP}"
jq -nc --rawfile p "${PROJECT_ROOT}/tests/fixtures/routing-input/peer-teammate.txt" --arg t "${TP}" '{prompt:$p, transcript_path:$t}' \
    | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT=shadow /bin/bash "${HOOK}" >/dev/null 2>&1
_peer_rec="$(cat "${LOG}"/session-dddd0.*.json 2>/dev/null | jq -c '[.displayed,.other_suppression]' | head -1)"
if [ -n "${_peer_rec}" ]; then
    assert_equals "J11 setup: the hook recorded the peer message's block as hidden by another rule" "[false,true]" "${_peer_rec}"
    python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "${SINCE}" --projects "${PROJ}" \
        --rows "${OUT}/rows6.jsonl" --key "${OUT}/key6.jsonl" > "${OUT}/rows6.txt" 2>&1
    assert_contains "J11: a block nobody was shown is not a row, and is counted" "     1  block not displayed" "$(cat "${OUT}/rows6.txt")"
    assert_equals "J11: no row comes from that session" "0" "$(grep -c 'session-dddd0' "${OUT}/key6.jsonl")"
else
    _record_pass "J11: the peer fixture carried no process mandate here, so the hook wrote no record for it"
fi
# The other filter, alone: a record that claims its block WAS displayed, for a prompt the
# transcript labels as not typed.
printf '%s\n' '{"schema_version":1,"rule_version":2,"ts":"'"$(now)"'","session":"session-dddd0","skill":"brainstorming","would_hide":true,"mode":"shadow","displayed":true,"skills_in_block":1}' > "${LOG}/hand-5.json"
python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${OUT}/rows7.jsonl" --key "${OUT}/key7.jsonl" > "${OUT}/rows7.txt" 2>&1
assert_equals "J11: a displayed block for a prompt that was not typed is not a row either" "0" "$(grep -c 'session-dddd0' "${OUT}/key7.jsonl")"
assert_not_empty "J11: and is counted as having no typed prompt to join" "$(grep -E '^ +[1-9][0-9]* +no typed prompt within the join window' "${OUT}/rows7.txt")"
assert_contains "J11: with what the transcript called the prompt it was written for" 'of those unjoined: origin "peer"' "$(cat "${OUT}/rows7.txt")"
# INSTRUMENT FAULT. If NO displayed record joins a typed prompt, "zero rows" is not "too
# little data": the reader may no longer recognise a typed prompt. That must not be
# readable as a thin sample (found in cross-family review). Same record, alone.
mkdir -p "${OUT}/only-peer.d"; cp "${LOG}/hand-5.json" "${OUT}/only-peer.d/"
python3 "${PROBE}/rows.py" --shadow-log "${OUT}/only-peer.d" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${OUT}/rows8.jsonl" --key "${OUT}/key8.jsonl" > "${OUT}/rows8.txt" 2>&1
assert_equals "J12: displayed records, none for a typed prompt: exit 2, which is no verdict's code" "2" "$?"
assert_contains "J12: it is named as an instrument fault" "INSTRUMENT FAULT: 1 displayed records" "$(cat "${OUT}/rows8.txt")"
assert_contains "J12: with the origin the transcript gave" 'origin "peer"' "$(cat "${OUT}/rows8.txt")"
if [ -e "${OUT}/rows8.jsonl" ] || [ -e "${OUT}/key8.jsonl" ]; then _record_fail "J12: nothing is written" "a rows or key file exists"; else _record_pass "J12: nothing is written"; fi
# Control: no records at all is NOT a fault. It is an empty sample, and exits 0 with no rows.
mkdir -p "${OUT}/empty.d"
python3 "${PROBE}/rows.py" --shadow-log "${OUT}/empty.d" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${OUT}/rows9.jsonl" --key "${OUT}/key9.jsonl" > "${OUT}/rows9.txt" 2>&1
assert_equals "J12 control: an empty record directory is an empty sample (exit 0), not a fault" "0" "$?"
rm -f "${LOG}/hand-5.json"

# Prompt text never lands in a repository.
python3 "${PROBE}/rows.py" --shadow-log "${LOG}" --since "${SINCE}" --projects "${PROJ}" \
    --rows "${PROJECT_ROOT}/tests/rows-leak.jsonl" --key "${OUT}/key5.jsonl" > "${OUT}/rows5.txt" 2>&1
assert_equals "J10: writing rows inside this repository is refused (exit 2)" "2" "$?"
if [ -e "${PROJECT_ROOT}/tests/rows-leak.jsonl" ]; then
    _record_fail "J10: and nothing was written there" "tests/rows-leak.jsonl exists"; rm -f "${PROJECT_ROOT}/tests/rows-leak.jsonl"
else
    _record_pass "J10: and nothing was written there"
fi

# --- S: score.py ---------------------------------------------------------------------
# mk <dir> <hidden> <hid_not> <hid_war> <hid_war_acted> <sessions> <rest> <owner_agree> [split]
# A key of <hidden> would-hide rows spread evenly over <sessions> sessions plus <rest> other
# rows; labellers agree NOT_WARRANTED on <hid_not> hidden rows, WARRANTED on <hid_war> (the
# first <hid_war_acted> of them invoked the same turn), and DISAGREE on the remainder; the
# owner labels 20 decided rows and agrees on <owner_agree> of them.
echo "== S: score.py =="
mk() {
    mkdir -p "$1" && python3 - "$@" <<'PY'
import json, sys
d, hidden, hid_not, hid_war, acted, sessions, rest, own_agree = sys.argv[1], *map(int, sys.argv[2:9])
key, a, b = [], [], []
for i in range(hidden):
    rid = f"h{i:03d}"
    if i < hid_not:
        la = lb = "NOT_WARRANTED"
    elif i < hid_not + hid_war:
        la = lb = "WARRANTED"
    else:
        la, lb = "WARRANTED", "NOT_WARRANTED"
    key.append({"row_id": rid, "session": f"s{i % sessions}", "skill": "requesting-code-review", "would_hide": True,
                "block_chars": 3000, "invoked_same_turn": hid_not <= i < hid_not + acted})
    a.append({"row_id": rid, "label": la}); b.append({"row_id": rid, "label": lb})
for i in range(rest):
    rid = f"r{i:03d}"
    lab = "WARRANTED" if i % 4 == 0 else "NOT_WARRANTED"
    key.append({"row_id": rid, "session": f"t{i % 30}", "skill": "brainstorming", "would_hide": False,
                "block_chars": 5000, "invoked_same_turn": False})
    a.append({"row_id": rid, "label": lab}); b.append({"row_id": rid, "label": lab})
decided = [x for x, y in zip(a, b) if x["label"] == y["label"]][:20]
owner = [{"row_id": x["row_id"], "label": x["label"] if n < own_agree else ("WARRANTED" if x["label"] == "NOT_WARRANTED" else "NOT_WARRANTED")}
         for n, x in enumerate(decided)]
for name, rows in (("key", key), ("a", a), ("b", b), ("owner", owner)):
    open(f"{d}/{name}.jsonl", "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
}
score() { python3 "${PROBE}/score.py" --key "$1/key.jsonl" --labels "$1/a.jsonl" --labels "$1/b.jsonl" --owner "$1/owner.jsonl" > "$1/out.txt" 2>&1; echo $?; }

D="${TEST_TMPDIR}/s-pass"; mk "${D}" 60 54 4 3 12 240 20
assert_equals "S1: a set that meets every threshold exits 0" "0" "$(score "${D}")"
assert_contains "S1: and says PASS means the trial, not suppression" "PASS (to the randomized trial; NOT a licence to suppress)" "$(cat "${D}/out.txt")"
assert_contains "S1: hidden rows are counted" "rows the rule would hide                       60  (20.0% of mandated)" "$(cat "${D}/out.txt")"

D="${TEST_TMPDIR}/s-k1"; mk "${D}" 60 54 4 3 12 400 20
assert_equals "S2: K1 — hiding 13% of mandated rows is STOP (exit 1)" "1" "$(score "${D}")"
assert_contains "S2: and K1 is the check that failed" "FAIL K1 reach" "$(cat "${D}/out.txt")"

# K2's denominator is ALL hidden rows. 44 of 60 decided NOT_WARRANTED is 73%; of the 48
# DECIDED rows it would be 92%, which is how a weaker rule passes on the rows nobody could judge.
D="${TEST_TMPDIR}/s-k2"; mk "${D}" 60 44 4 0 12 240 20
assert_equals "S3: K2 — 44 of 60 hidden rows decided NOT_WARRANTED is STOP" "1" "$(score "${D}")"
assert_contains "S3: measured against all hidden rows" "73.3% of ALL hidden rows decided NOT_WARRANTED" "$(cat "${D}/out.txt")"
assert_not_contains "S3: K2b is not what failed" "FAIL K2b" "$(cat "${D}/out.txt")"

D="${TEST_TMPDIR}/s-k2b"; mk "${D}" 60 50 7 0 12 240 20
assert_equals "S4: K2b — 7 of 60 hidden rows decided WARRANTED is STOP" "1" "$(score "${D}")"
assert_contains "S4: and K2b is the check that failed" "FAIL K2b warranted" "$(cat "${D}/out.txt")"

D="${TEST_TMPDIR}/s-k3"; mk "${D}" 60 52 6 4 12 240 20
assert_equals "S5: K3 — 4 warranted-and-acted rows of 60 is STOP (the limit is 3)" "1" "$(score "${D}")"
assert_contains "S5: and K3 is the only check that failed" "FAIL K3 acted" "$(cat "${D}/out.txt")"
assert_equals "S5: exactly one check failed" "1" "$(grep -c '^  FAIL' "${D}/out.txt")"
D="${TEST_TMPDIR}/s-k3n"; mk "${D}" 40 36 3 3 10 160 20
assert_equals "S6: K3 scales with the sample — 3 of 40 is over the limit of 2" "1" "$(score "${D}")"
assert_contains "S6: the limit is stated for 40 rows" "limit 2 of 40" "$(cat "${D}/out.txt")"

# INCONCLUSIVE is its own exit code and is never a pass.
D="${TEST_TMPDIR}/s-few"; mk "${D}" 39 36 2 1 13 160 20
assert_equals "S7: 39 hidden rows is INCONCLUSIVE (exit 3)" "3" "$(score "${D}")"
D="${TEST_TMPDIR}/s-sess"; mk "${D}" 60 54 4 3 9 240 20
assert_equals "S8: hidden rows from 9 sessions is INCONCLUSIVE" "3" "$(score "${D}")"
D="${TEST_TMPDIR}/s-clump"; mk "${D}" 60 54 4 3 3 240 20
assert_contains "S9: one session supplying a third of the hidden rows is named" "one session supplies 33% of hidden rows" "$(score "${D}" >/dev/null; cat "${D}/out.txt")"
D="${TEST_TMPDIR}/s-owner"; mk "${D}" 60 54 4 3 12 240 15
assert_equals "S10: the owner agreeing on 15 of 20 is INCONCLUSIVE" "3" "$(score "${D}")"
assert_contains "S10: and says so" "owner agrees on 15 of 20 decided rows" "$(cat "${D}/out.txt")"
D="${TEST_TMPDIR}/s-noowner"; mk "${D}" 60 54 4 3 12 240 20; head -5 "${D}/owner.jsonl" > "${D}/o5" && mv "${D}/o5" "${D}/owner.jsonl"
assert_equals "S11: five owner labels is INCONCLUSIVE" "3" "$(score "${D}")"
# The owner must have labelled twenty rows the labellers DECIDED. Twenty labels of which
# nineteen are on rows the labellers disagreed about calibrate one row (found in review:
# this passed, "agrees on 1 of 1").
D="${TEST_TMPDIR}/s-owner-undecided"; mk "${D}" 60 34 4 3 12 240 20
python3 - "${D}" <<'PY2'
import json, sys
d = sys.argv[1]
a = {json.loads(l)["row_id"]: json.loads(l)["label"] for l in open(f"{d}/a.jsonl")}
b = {json.loads(l)["row_id"]: json.loads(l)["label"] for l in open(f"{d}/b.jsonl")}
undecided = [i for i in a if a[i] != b[i]][:19]
decided = [i for i in a if a[i] == b[i]][:1]
open(f"{d}/owner.jsonl", "w").write("".join(json.dumps({"row_id": i, "label": a[i]}) + "\n" for i in undecided + decided))
PY2
assert_equals "S11b: twenty owner labels, nineteen on rows the labellers did not decide, is INCONCLUSIVE" "3" "$(score "${D}")"
assert_contains "S11b: and says how many calibrate" "owner labelled 1 of the rows the labellers decided (20 in all; need 20 decided)" "$(cat "${D}/out.txt")"
# The kappa floor decides too, not only the printed number.
D="${TEST_TMPDIR}/s-lowkappa"; mk "${D}" 60 54 4 3 12 240 20
python3 - "${D}" <<'PY2'
import json, sys
d = sys.argv[1]
rows = [json.loads(l) for l in open(f"{d}/b.jsonl")]
for n, r in enumerate(rows):
    if r["row_id"].startswith("r") and n % 2 == 0:      # flip half of the rows the rule does not hide
        r["label"] = "WARRANTED" if r["label"] == "NOT_WARRANTED" else "NOT_WARRANTED"
open(f"{d}/b.jsonl", "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY2
assert_equals "S12b: labellers who disagree on half the other rows make it INCONCLUSIVE" "3" "$(score "${D}")"
assert_contains "S12b: and kappa is the reason given" "  - kappa " "$(cat "${D}/out.txt")"

# Kappa, against a value worked by hand: 100 rows, each labeller 50/50, agreeing on 80.
# po = 0.80, pe = 0.5*0.5 + 0.5*0.5 = 0.50, kappa = 0.30/0.50 = 0.60.
D="${TEST_TMPDIR}/s-kappa"; mkdir -p "${D}" && python3 - "${D}" <<'PY'
import json, sys
d = sys.argv[1]
key, a, b = [], [], []
for i in range(100):
    la = "WARRANTED" if i < 50 else "NOT_WARRANTED"
    lb = la if (i < 40 or i >= 60) else ("NOT_WARRANTED" if la == "WARRANTED" else "WARRANTED")
    key.append({"row_id": f"k{i}", "session": f"s{i % 20}", "skill": "x", "would_hide": i >= 40, "block_chars": 1, "invoked_same_turn": False})
    a.append({"row_id": f"k{i}", "label": la}); b.append({"row_id": f"k{i}", "label": lb})
for n, rows in (("key", key), ("a", a), ("b", b), ("owner", [{"row_id": f"k{i}", "label": "NOT_WARRANTED"} for i in range(60, 80)])):
    open(f"{d}/{n}.jsonl", "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
score "${D}" >/dev/null
assert_contains "S12: Cohen's kappa matches the value worked by hand" "labeller agreement (Cohen's kappa, all rows)   0.60" "$(cat "${D}/out.txt")"

# Unlabelled rows are an error, not a smaller sample.
D="${TEST_TMPDIR}/s-miss"; mk "${D}" 60 54 4 3 12 240 20; sed -i.bak '1d' "${D}/b.jsonl"
assert_equals "S13: a row one labeller skipped is an error (exit 2), which is no verdict's exit code" "2" "$(score "${D}")"
assert_contains "S13: and the message says what is missing" "not labelled by both labellers" "$(cat "${D}/out.txt")"
# So is every other way the inputs can be unreadable. Found in review: these raised, and an
# uncaught exception exits 1, which is STOP.
D="${TEST_TMPDIR}/s-nokey"; mk "${D}" 60 54 4 3 12 240 20; rm -f "${D}/key.jsonl"
assert_equals "S14: a missing key file exits 2" "2" "$(score "${D}")"
D="${TEST_TMPDIR}/s-badjson"; mk "${D}" 60 54 4 3 12 240 20; printf 'not json\n' > "${D}/a.jsonl"
assert_equals "S14: a label file that is not JSON exits 2" "2" "$(score "${D}")"
D="${TEST_TMPDIR}/s-nofield"; mk "${D}" 60 54 4 3 12 240 20; printf '{"label":"WARRANTED"}\n' > "${D}/b.jsonl"
assert_equals "S14: a label with no row_id exits 2" "2" "$(score "${D}")"
D="${TEST_TMPDIR}/s-badkey"; mk "${D}" 60 54 4 3 12 240 20; sed -i.bak 's/"would_hide": [a-z]*, //' "${D}/key.jsonl"
assert_equals "S14: a key with a field missing exits 2" "2" "$(score "${D}")"
# Found in cross-family review: valid JSON of the wrong SHAPE raised AttributeError, which the
# handler of the day did not list, so it exited 1 -- STOP. Nothing uncaught may be a verdict.
D="${TEST_TMPDIR}/s-shape"; mk "${D}" 60 54 4 3 12 240 20; printf '[]\n' >> "${D}/a.jsonl"
assert_equals "S15: a label line that is a JSON array exits 2" "2" "$(score "${D}")"
D="${TEST_TMPDIR}/s-shape2"; mk "${D}" 60 54 4 3 12 240 20; printf '"WARRANTED"\n' >> "${D}/owner.jsonl"
assert_equals "S15: an owner line that is a bare string exits 2" "2" "$(score "${D}")"
D="${TEST_TMPDIR}/s-shape3"; mk "${D}" 60 54 4 3 12 240 20; printf '7\n' >> "${D}/key.jsonl"
assert_equals "S15: a key line that is a number exits 2" "2" "$(score "${D}")"

# --- T: trial.py ---------------------------------------------------------------------
echo "== T: trial.py =="
rm -f "${LOG}"/*.json; TSINCE="$(now)"; sleep 1.1
session cccc0                                   # token ends in 0: the SHOW arm
prompt trial "review the PR diff for bugs"
prompt trial "go"
t_skill "superpowers:requesting-code-review"
t_bash p1 "git push origin HEAD"
t_result p1 "ok"
session ccccf                                   # token ends in f: the HIDE arm
prompt trial "review the PR diff for bugs"
prompt trial "go"
t_bash p2 "git push origin HEAD"
t_result p2 "PUSH GATE (fail-closed): pushing this branch requires requesting-code-review"
session ccccb                                   # hide arm, and it never pushes
prompt trial "review the PR diff for bugs"
prompt trial "go"
assert_equals "T setup: the real hook recorded both arms" "hide show" "$(cat "${LOG}"/*.json | jq -r '.arm' | sort -u | tr '\n' ' ' | sed 's/ $//')"
python3 "${PROBE}/trial.py" --shadow-log "${LOG}" --since "${TSINCE}" --projects "${PROJ}" > "${OUT}/trial.txt" 2>&1
assert_equals "T1: three obligations are too few for a reading (exit 3)" "3" "$?"
row() { grep -E "^$1 " "${OUT}/trial.txt" | awk '{print $(NF-1), $NF}'; }
assert_equals "T1: sessions per arm (show hide)" "1 2" "$(row 'sessions  ')"
assert_equals "T1: one obligation per session, in both arms" "1 2" "$(row 'obligations  ')"
assert_equals "T1: completed where the skill was invoked, and nowhere else" "1 0" "$(row 'obligations completed  ')"
assert_equals "T1: a session that never pushed still counts as an obligation never completed" "0 2" "$(row 'obligations never completed')"
assert_equals "T1: and is reported as not having pushed" "0 1" "$(row 'sessions with no push attempt')"
assert_equals "T1: the denied first push is counted in its arm" "0 1" "$(row 'sessions whose first push attempt was denied')"

# The decision rule, on constructed data: 22 obligations an arm.
mk_trial() {   # <dir> <show completed of 22> <hide completed of 22>
    mkdir -p "$1/projects/p" && python3 - "$@" <<'PY'
import json, sys
d, show_done, hide_done = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
log = []
for arm, done, last in (("show", show_done, "0"), ("hide", hide_done, "f")):
    for i in range(22):
        sid = f"t{arm}{i:02d}{last}"
        ts = lambda s: f"2026-11-01T10:{i:02d}:{s:02d}Z"
        entries = [{"type": "user", "timestamp": ts(0), "origin": {"kind": "human"}, "message": {"role": "user", "content": "review the PR diff for bugs"}},
                   {"type": "user", "timestamp": ts(20), "origin": {"kind": "human"}, "message": {"role": "user", "content": "go"}}]
        if i < done:
            entries.append({"type": "assistant", "timestamp": ts(30), "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "s", "name": "Skill", "input": {"skill": "superpowers:requesting-code-review"}}]}})
        open(f"{d}/projects/p/{sid}.jsonl", "w").write("".join(json.dumps(e) + "\n" for e in entries))
        log.append({"schema_version": 1, "rule_version": 2, "ts": ts(20), "session": f"session-{sid}", "skill": "requesting-code-review", "sticky": True,
                    "already_shown": True, "would_hide": True, "mode": "trial", "arm": arm, "hidden_by_rule": arm == "hide", "block_chars": 4000})
open(f"{d}/shadow.jsonl", "w").write("".join(json.dumps(r) + "\n" for r in log))
PY
}
trial() { python3 "${PROBE}/trial.py" --shadow-log "$1/shadow.jsonl" --since 2026-11-01T00:00:00Z --projects "$1/projects" > "$1/out.txt" 2>&1; echo $?; }
D="${TEST_TMPDIR}/t-same"; mk_trial "${D}" 11 11
assert_equals "T2: equal completion in both arms reads as no large harm (exit 0)" "0" "$(trial "${D}")"
assert_contains "T2: and the reading says what it cannot show" "tripwire against serious harm, not evidence that there is none" "$(cat "${D}/out.txt")"
D="${TEST_TMPDIR}/t-drop"; mk_trial "${D}" 11 8
assert_equals "T3: the hide arm completing 14 points less reads as HARM (exit 1)" "1" "$(trial "${D}")"
D="${TEST_TMPDIR}/t-edge"; mk_trial "${D}" 11 9
assert_equals "T4: 9 points less is inside the limit" "0" "$(trial "${D}")"
# Exactly ten points is "at most ten points", at every level. With 20 an arm that is two
# obligations, and a floating-point subtraction called 16/20 against 14/20 HARM and 12/20
# against 10/20 fine (found in review). mk_trial20 builds exactly twenty an arm.
mk_trial20() {   # <dir> <show completed of 20> <hide completed of 20> [hide sessions whose first push is denied]
    mkdir -p "$1/projects/p" && python3 - "$@" <<'PY'
import json, sys
d, show_done, hide_done = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
hide_denied = int(sys.argv[4]) if len(sys.argv) > 4 else 0
log = []
for arm, done, last in (("show", show_done, "0"), ("hide", hide_done, "f")):
    for i in range(20):
        sid = f"u{arm}{i:02d}{last}"
        ts = lambda s: f"2026-11-01T10:{i:02d}:{s:02d}Z"
        entries = [{"type": "user", "timestamp": ts(0), "origin": {"kind": "human"}, "message": {"role": "user", "content": "review the PR diff for bugs"}},
                   {"type": "user", "timestamp": ts(20), "origin": {"kind": "human"}, "message": {"role": "user", "content": "go"}}]
        if i < done:
            entries.append({"type": "assistant", "timestamp": ts(30), "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "s", "name": "Skill", "input": {"skill": "superpowers:requesting-code-review"}}]}})
        if arm == "hide" and i >= 20 - hide_denied:
            entries.append({"type": "assistant", "timestamp": ts(40), "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "p", "name": "Bash", "input": {"command": "git push origin HEAD"}}]}})
            entries.append({"type": "user", "timestamp": ts(41), "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "p", "content": "PUSH GATE: denied"}]}})
        open(f"{d}/projects/p/{sid}.jsonl", "w").write("".join(json.dumps(e) + "\n" for e in entries))
        log.append({"schema_version": 1, "rule_version": 2, "ts": ts(20), "session": f"session-{sid}", "skill": "requesting-code-review", "sticky": True,
                    "already_shown": True, "would_hide": True, "mode": "trial", "arm": arm, "hidden_by_rule": arm == "hide", "block_chars": 4000})
open(f"{d}/shadow.jsonl", "w").write("".join(json.dumps(r) + "\n" for r in log))
PY
}
while IFS=' ' read -r _a _b; do
    [ -n "${_a}" ] || continue
    D="${TEST_TMPDIR}/t-b-${_a}-${_b}"; mk_trial20 "${D}" "${_a}" "${_b}"
    assert_equals "T5: ${_a} of 20 against ${_b} of 20 is exactly ten points, which is inside the limit" "0" "$(trial "${D}")"
done <<EOF
12 10
16 14
8 6
9 7
11 9
EOF
D="${TEST_TMPDIR}/t-b-over"; mk_trial20 "${D}" 12 9
assert_equals "T5: three fewer of twenty (fifteen points) is over it" "1" "$(trial "${D}")"
# The other half of the reading: equal completion, but the hide arm is denied on first push.
D="${TEST_TMPDIR}/t-rise-ok"; mk_trial20 "${D}" 10 10 2
assert_equals "T6: two of twenty hide-arm sessions denied on first push (ten points) is inside the limit" "0" "$(trial "${D}")"
D="${TEST_TMPDIR}/t-rise-over"; mk_trial20 "${D}" 10 10 3
assert_equals "T6: three of twenty (fifteen points) reads as HARM though completion is equal" "1" "$(trial "${D}")"
assert_contains "T6: and the denied-push line is the one marked" "higher) -> OVER" "$(cat "${D}/out.txt")"
python3 "${PROBE}/trial.py" --shadow-log "${TEST_TMPDIR}/no-such-log" --since 2026-11-01T00:00:00Z --projects "${TEST_TMPDIR}" > /dev/null 2>&1
assert_equals "T8: a shadow log that does not exist exits 2, not a reading" "2" "$?"
# "Before the first push" is decided by the ORDER the assistant issued things, also inside
# one turn: a review invoked after the push in the same turn did not come before it. And an
# obligation whose record joins no prompt counts toward neither the rate nor the floor.
mk_order() {   # <dir>
    mkdir -p "$1/projects/p" && python3 - "$1" <<'PY'
import json, sys
d = sys.argv[1]
def session(sid, arm, blocks, rec_ts):
    ts = lambda s: f"2026-11-02T09:00:{s:02d}Z"
    entries = [{"type": "user", "timestamp": ts(0), "origin": {"kind": "human"}, "message": {"role": "user", "content": "review the PR diff for bugs"}},
               {"type": "user", "timestamp": ts(20), "origin": {"kind": "human"}, "message": {"role": "user", "content": "go"}},
               {"type": "assistant", "timestamp": ts(30), "message": {"role": "assistant", "content": blocks}}]
    open(f"{d}/projects/p/{sid}.jsonl", "w").write("".join(json.dumps(e) + "\n" for e in entries))
    return {"schema_version": 1, "rule_version": 2, "ts": rec_ts, "session": f"session-{sid}", "skill": "requesting-code-review", "sticky": True,
            "already_shown": True, "would_hide": True, "mode": "trial", "arm": arm, "hidden_by_rule": arm == "hide", "block_chars": 4000}
skill = {"type": "tool_use", "id": "s", "name": "Skill", "input": {"skill": "superpowers:requesting-code-review"}}
push = {"type": "tool_use", "id": "p", "name": "Bash", "input": {"command": "git push origin HEAD"}}
log = [session("ord-a0", "show", [skill, push], "2026-11-02T09:00:20Z"),      # review, THEN push, in one turn
       session("ord-bf", "hide", [push, skill], "2026-11-02T09:00:20Z"),      # push, THEN review, in one turn
       session("ord-cf", "hide", [skill], "2026-11-02T23:00:00Z")]            # record hours from any prompt: unjoined
open(f"{d}/shadow.jsonl", "w").write("".join(json.dumps(r) + "\n" for r in log))
PY
}
D="${TEST_TMPDIR}/t-order"; mk_order "${D}"
python3 "${PROBE}/trial.py" --shadow-log "${D}/shadow.jsonl" --since 2026-11-01T00:00:00Z --projects "${D}/projects" > "${D}/out.txt" 2>&1
trow() { grep -E "^$1 " "${D}/out.txt" | awk '{print $(NF-1), $NF}'; }
assert_equals "T9: both joined obligations were completed (show hide)" "1 1" "$(trow 'obligations completed  ')"
assert_equals "T9: only the one reviewed BEFORE its push counts as completed before the first push" "1 0" "$(trow 'obligations completed before the first push attempt')"
assert_equals "T9: the unjoined obligation is reported" "0 1" "$(trow 'obligations not joined to a prompt')"
assert_equals "T9: and is not counted as an obligation (so not toward the rate or the floor)" "1 1" "$(trow 'obligations  ')"

# A record written by a changed rule is not trial data.
D="${TEST_TMPDIR}/t-ver"; mk_trial20 "${D}" 10 10; sed -i.bak 's/"rule_version": 2/"rule_version": 1/' "${D}/shadow.jsonl"
assert_equals "T7: records of another rule version leave nothing to read (INCONCLUSIVE)" "3" "$(trial "${D}")"
# A record of the wrong SHAPE must not exit 1 (HARM). A session that is a number raised
# AttributeError, uncaught. The record is ALONE in its log on purpose: next to string
# sessions the sort fails first with a TypeError, which the old handler did catch, and the
# cell then passed without the fix (measured by mutation).
D="${TEST_TMPDIR}/t-shape"; mkdir -p "${D}/projects/p"
printf '%s\n' '{"schema_version":1,"rule_version":2,"ts":"2026-11-01T10:00:20Z","session":5,"skill":"requesting-code-review","would_hide":true,"mode":"trial","arm":"hide"}' > "${D}/shadow.jsonl"
assert_equals "T10: a trial record whose session is not a string exits 2, never a reading" "2" "$(trial "${D}")"

assert_contains "the rubric asks about the obligation, not the prompt's wording" "is REQUIRING the assistant to invoke this specific" "$(cat "${PROBE}/rubric.md")"
assert_contains "the rubric has an explicit cannot-tell label" "INSUFFICIENT_CONTEXT" "$(cat "${PROBE}/rubric.md")"

cd "${PROJECT_ROOT}" || true
teardown_test_env
print_summary

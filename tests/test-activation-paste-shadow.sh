#!/usr/bin/env bash
# test-activation-paste-shadow.sh — the pasted-content shadow record (#409, stage 1).
#
# Text inside a harness-wrapped paste scores as if the user typed it. Rule R (pre-registered
# in docs/plans/2026-11-17-paste-scoring-409-prereg.md, predicate_version 1) would keep a
# selected skill only if the prompt with every paste stripped still selects it, or sticky
# composition injected it. Stage 1 only RECORDS what R would hide. This file holds:
#
#   1. NOTHING CHANGES. Display byte-identical to ACS_PASTE_SHADOW=off, and every `.skill-*`
#      state file identical turn by turn. The comparison has power: a mutant that strips the
#      paste inside the scorer (the rejected design) must DIFFER, on the paste turn.
#   2. THE RECORD IS R. Its selected list is what the block displayed; its kept list is the
#      selection the SAME hook makes for the stripped text (oracle: the hook itself, run on
#      the parser's output), intersected, plus the sticky step.
#   3. WHEN THERE IS NO RECORD: off, no session token, an early exit, no wrapper, no lib.
#   4. THE RECORD HOLDS NO PROMPT TEXT.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-activation-paste-shadow.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available — paste-shadow cells NOT run"; exit 0
fi
setup_test_env

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
LIB="${PROJECT_ROOT}/hooks/lib/pasted-content.sh"
FIX="${PROJECT_ROOT}/tests/fixtures/routing-input/pasted-content"
ONLY="${FIX}/paste-only-escaped-inner-tag.txt"
AROUND="${FIX}/typed-before-and-after.txt"
NEG="${FIX}/negative-issue-409-body.txt"
REG="${TEST_TMPDIR}/registry.json"
jq '.skills |= map(.available = true | .enabled = true)' "${PROJECT_ROOT}/config/default-triggers.json" > "${REG}"
PASTED_CONTENT_JQ_DEF=""
[ -f "${LIB}" ] && . "${LIB}"

new_session() {
    H="$(mktemp -d "${TEST_TMPDIR}/s.XXXXXX")"
    mkdir -p "${H}/.claude" && cp "${REG}" "${H}/.claude/.skill-registry-cache.json"
    TP="${H}/${1:-sess0}.jsonl"; touch "${TP}"
    RD="${H}/.claude/.paste-shadow.d"
}
# turn <mode|-> <file> [hook] [root] : drive the hook with the file's exact bytes as the prompt;
# prints the displayed context ("" for nothing). Mode "-" leaves ACS_PASTE_SHADOW unset.
# TP empty = no transcript_path (no session token).
turn() {
    local mode="$1" file="$2" hook="${3:-${HOOK}}" root="${4:-${PROJECT_ROOT}}" pl
    if [ -n "${TP}" ]; then
        pl="$(jq -nc --rawfile p "${file}" --arg t "${TP}" '{prompt:$p, transcript_path:$t}')"
    else
        pl="$(jq -nc --rawfile p "${file}" '{prompt:$p}')"
    fi
    if [ "${mode}" = "-" ]; then
        printf '%s' "${pl}" | env -u ACS_PASTE_SHADOW HOME="${H}" CLAUDE_PLUGIN_ROOT="${root}" /bin/bash "${hook}" 2>/dev/null \
            | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
    else
        printf '%s' "${pl}" | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${root}" ACS_PASTE_SHADOW="${mode}" /bin/bash "${hook}" 2>/dev/null \
            | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
    fi
}
txt() { local f; f="$(mktemp "${TEST_TMPDIR}/p.XXXXXX")"; printf '%s' "$1" > "${f}"; printf '%s' "${f}"; }
# names <block> : the skill names on the block's Evaluate line ("**Phase: [X]** | a TAG, b TAG"),
# sorted and comma-joined. Every displayed skill is on that line whatever its role or layout.
# Only registry names are kept: an "INVOKE WHEN: <condition>" tag can itself hold commas
# (agent-team-review's does), and its words would otherwise read as skills (measured in the
# corpus replay).
SKILL_NAMES=",$(jq -r '[.skills[].name] | join(",")' "${REG}"),"
names() { local t out=""
    for t in $(printf '%s\n' "$1" | grep -m1 -F '**Phase: [' | sed 's/^.*\*\* | //' | tr ',' '\n' | awk 'NF {print $1}'); do
        case "${SKILL_NAMES}" in *",${t},"*) out="${out}${t}"$'\n' ;; esac
    done
    printf '%s' "${out}" | awk 'NF' | LC_ALL=C sort | paste -sd, -; }
# srt <list> : a comma list sorted the same way.
srt() { printf '%s' "$1" | tr ',' '\n' | awk 'NF' | LC_ALL=C sort | paste -sd, -; }
# -A: a record written with an empty token would be a dotfile (".1.<n>.json").
nrec() { ls -A "${RD}" 2>/dev/null | wc -l | tr -d ' '; }
# last <jq args...> : apply jq to the newest record (-r).
last() { local f; f="$(ls -At "${RD}" 2>/dev/null | head -1)"; [ -n "${f}" ] && jq -r "$@" "${RD}/${f}" 2>/dev/null; }
snap() {
    ( cd "${H}/.claude" && ls -A | grep -E '^\.skill-' | grep -v -E '^\.skill-registry-cache\.json$' | LC_ALL=C sort \
        | while IFS= read -r _sf; do
            printf '%s %s\n' "${_sf}" "$(sed -e 's/"updated_at": *"[^"]*"/"updated_at":"T"/' -e "s|${H}|HOME|g" "${_sf}" | cksum)"
          done )
}
# stripped <file> : a file holding the parser's output for the input (the oracle's prompt).
stripped() { local f; f="$(mktemp "${TEST_TMPDIR}/st.XXXXXX")"; jq -nj --rawfile t "$1" "${PASTED_CONTENT_JQ_DEF} \$t | paste_strip | .text" > "${f}"; printf '%s' "${f}"; }

ARM="$(txt "build a new exporter for the report module")"   # arms a chain by its own words
GO="$(txt "go")"
# DERIVED short wrapped prompt: the real wrapper of ONLY with its body cut to its first word,
# after a typed "go". Six words in all, so sticky composition is eligible.
SHORT="${TEST_TMPDIR}/short.txt"
jq -nj --rawfile o "${ONLY}" '"go" + ($o | sub("(?<op><pasted_content id=\"[0-9a-f]{4}\">)\n(?<w>[A-Za-z]+)[\\s\\S]*?(?<cl></pasted_content id=)"; "\(.op)\n\(.w)\n\(.cl)"))' > "${SHORT}"
UPPER="${TEST_TMPDIR}/upper.txt"   # DERIVED: ONLY with its id upper-cased in both tags
jq -nj --rawfile t "${ONLY}" '$t | gsub("id=\"(?<i>[0-9a-f]{4})\""; "id=\"\(.i | ascii_upcase)\"")' > "${UPPER}"
CAP="${TEST_TMPDIR}/cap.txt"       # DERIVED: ONLY with its opener repeated to 17
jq -nj --rawfile o "${ONLY}" '($o | match("<pasted_content id=\"[0-9a-f]{4}\">").string) as $op | ($op * 16) + $o' > "${CAP}"

# --- C: controls ---------------------------------------------------------------------------
echo "== C: controls =="
[ -n "${PASTED_CONTENT_JQ_DEF}" ] && _record_pass "C0: the parser lib is present" || _record_fail "C0: the parser lib is present" "${LIB}"
new_session
c1="$(turn off "${ONLY}")"
[ -n "$(names "${c1}")" ] && _record_pass "C1: the real paste-only prompt is routed today ($(names "${c1}"))" \
    || _record_fail "C1: the real paste-only prompt is routed today" "nothing displayed"
assert_equals "C2: SHORT is six words (sticky-eligible)" "6" "$(wc -w < "${SHORT}" | tr -d ' ')"
assert_equals "C3: names() ignores the words of an INVOKE WHEN condition" "agent-team-review,requesting-code-review" \
    "$(names 'Evaluate: **Phase: [REVIEW]** | requesting-code-review MUST INVOKE, agent-team-review INVOKE WHEN: diff touches 5+ files, or crosses a boundary')"

# --- SH: nothing displayed or written changes ----------------------------------------------
echo "== SH: display and state identical to off, turn by turn =="
SEQ="${ARM} ${ONLY} ${GO} ${AROUND} ${SHORT} ${NEG} ${UPPER} ${CAP}"
new_session sessA; HO="${H}"; TPO="${TP}"
new_session sessA; HS="${H}"; TPS="${TP}"
_n=0; _bad=""
for f in ${SEQ}; do
    _n=$((_n + 1))
    H="${HO}"; TP="${TPO}"; o="$(turn off "${f}")"; so="$(snap)"
    H="${HS}"; TP="${TPS}"; s="$(turn - "${f}")"; ss="$(snap)"
    [ "${o}" = "${s}" ] || _bad="${_bad} display@${_n}"
    [ "${so}" = "${ss}" ] || _bad="${_bad} state@${_n}"
done
[ -z "${_bad}" ] && _record_pass "SH1: ${_n} turns: display and every .skill-* file identical to off" \
    || _record_fail "SH1: display and state identical to off" "${_bad}"
H="${HS}"
[ "$(nrec)" -ge 5 ] && _record_pass "SH2: the default (shadow) wrote records on that run ($(nrec))" \
    || _record_fail "SH2: the default (shadow) wrote records" "$(nrec)"

# Power: the rejected design (strip inside the scorer) must change state on the paste turn.
MUT="${TEST_TMPDIR}/mutant-hook.sh"
MUT_LINE='. "${PLUGIN_ROOT}/hooks/lib/pasted-content.sh"; P="$(printf '"'"'%s'"'"' "$P" | jq -Rrs "${PASTED_CONTENT_JQ_DEF} paste_strip | .text")"' \
    awk '{print} /^P=\$\(printf / {print ENVIRON["MUT_LINE"]}' "${HOOK}" > "${MUT}"
assert_equals "SH3: control: the mutant is the hook plus one line" "1" \
    "$(diff "${HOOK}" "${MUT}" | grep -c '^>')"
new_session sessM; HM="${H}"; TPM="${TP}"
new_session sessM; HB="${H}"; TPB="${TP}"
H="${HM}"; TP="${TPM}"; turn off "${ONLY}" "${MUT}" >/dev/null; sm="$(snap)"
H="${HB}"; TP="${TPB}"; turn off "${ONLY}" >/dev/null; sb="$(snap)"
[ "${sm}" != "${sb}" ] && _record_pass "SH3: the strip-in-scorer mutant DOES change state on the paste turn" \
    || _record_fail "SH3: the strip-in-scorer mutant changes state" "identical: the identity check has no power"

# --- R: the record is rule R ---------------------------------------------------------------
echo "== R: record fields =="
oracle() { local h0="${H}" tp0="${TP}" out; new_session oracle; TP=""; out="$(names "$(turn off "$(stripped "$1")")")"; H="${h0}"; TP="${tp0}"; printf '%s' "${out}"; }
# keep <selected> <oracle> [sticky] : R's kept list, in selected order.
keep() { local s o="$2" k=""; for s in $(printf '%s' "$1" | tr ',' ' '); do
    case ",${o},${3:+$3,}" in *",${s},"*) k="${k:+${k},}${s}" ;; esac; done; printf '%s' "${k}"; }

new_session r1
b="$(turn - "${ONLY}")"
assert_equals "R1: paste-only: one record" "1" "$(nrec)"
assert_equals "R1: status/openers/pairs" "ok 1 1" "$(last '"\(.status) \(.openers) \(.pairs)"')"
assert_equals "R1: selected = the skills the block displayed" "$(names "${b}")" "$(srt "$(last .selected)")"
assert_equals "R1: kept = nothing (the stripped prompt selects nothing)" "" "$(last .kept)"
assert_equals "R1: hidden = everything selected" "$(names "${b}")" "$(srt "$(last .hidden)")"
assert_equals "R1: process kept is false; displayed is true" "false true" "$(last '"\(.process_kept) \(.displayed)"')"
assert_equals "R1: schema/predicate versions" "1 1" "$(last '"\(.schema_version) \(.predicate_version)"')"

new_session r2
b="$(turn - "${AROUND}")"; sel="$(names "${b}")"; orc="$(oracle "${AROUND}")"
exp="$(keep "${sel}" "${orc}")"
assert_equals "R2: typed around: selected = displayed" "${sel}" "$(srt "$(last .selected)")"
assert_equals "R2: kept = selected ∩ the hook's own selection for the stripped text (${orc:-none})" "${exp}" "$(srt "$(last .kept)")"
[ -n "${exp}" ] && [ "${exp}" != "${sel}" ] && _record_pass "R2: control: the oracle keeps some and hides some ('${exp}' of '${sel}')" \
    || _record_fail "R2: control: the oracle keeps some and hides some" "kept='${exp}' selected='${sel}'"

new_session r3
turn - "${ARM}" >/dev/null
b="$(turn - "${SHORT}")"; st="$(last .sticky)"
[ -n "${st}" ] && _record_pass "R3: control: the short wrapped prompt got a sticky step (${st})" \
    || _record_fail "R3: control: the short wrapped prompt got a sticky step" "record: $(last .)"
assert_equals "R3: the sticky step is kept although the stripped text selects nothing" "true" \
    "$(last --arg s "${st}" '(.kept | split(",") | index($s)) != null')"
assert_equals "R3: and the process skill counts as kept" "true" "$(last .process_kept)"

# R6, found in review: inside a live chain, "go" plus a paste. The stripped prompt is "go",
# which the real hook answers with the chain's current step (sticky composition fires on six
# words or fewer); the full prompt is too long for sticky. R must keep that step.
# DERIVED input: "go", then the real wrapper of ONLY around this file's ARM text.
GOPASTE="${TEST_TMPDIR}/gopaste.txt"
jq -nj --rawfile o "${ONLY}" --rawfile a "${ARM}" '($o | match("<pasted_content id=\"[0-9a-f]{4}\">").string) as $op
    | ($o | match("</pasted_content id=\"[0-9a-f]{4}\">").string) as $cl
    | "go\n\n" + $op + "\n" + $a + "\n" + $cl + "\n"' > "${GOPASTE}"
new_session r6o; turn off "${ARM}" >/dev/null; orc="$(names "$(turn off "$(stripped "${GOPASTE}")")")"
new_session r6;  turn - "${ARM}" >/dev/null; b="$(turn - "${GOPASTE}")"
[ -n "${orc}" ] && _record_pass "R6: control: in the same chain the stripped prompt alone is routed (${orc})" \
    || _record_fail "R6: control: in the same chain the stripped prompt alone is routed" "nothing displayed"
# inlist <name> <comma-list> : a function, because a case pattern's ")" inside $( ) ends the
# command substitution early under bash 3.2.
inlist() { case ",$2," in *",$1,"*) echo true ;; *) echo false ;; esac; }
assert_equals "R6: control: the full prompt displays that step too" "true" "$(inlist "${orc%%,*}" "$(names "${b}")")"
assert_equals "R6: kept = selected ∩ the hook's own selection for the stripped prompt in this chain" \
    "$(keep "$(names "${b}")" "${orc}")" "$(srt "$(last .kept)")"
assert_equals "R6: the process mandate counts as kept" "true" "$(last .process_kept)"

new_session r4
turn - "${UPPER}" >/dev/null
assert_equals "R4: an id the harness never wrote: status ok, pairs 0, nothing hidden (format-drift record)" "ok 0 " \
    "$(last '"\(.status) \(.pairs) \(.hidden)"')"
new_session r5
turn - "${CAP}" >/dev/null
assert_equals "R5: 17 openers: status capped, nothing hidden" "capped 17 " "$(last '"\(.status) \(.openers) \(.hidden)"')"

# --- B: the budget — a long typed prompt is not scored twice ---------------------------------
# Found in review: the second selection re-scores all typed text, and scoring cost grows faster
# than the text, so long typed text plus a paste doubled the hook's time (6.5 s -> 12.7 s at
# 39 KB, against the 10 s kill). Over 16 KB of stripped text, or 3 s already spent, the record
# says `skipped` and nothing is re-scored. DERIVED input: AROUND's typed first line repeated
# past 16 KB, then AROUND's real block.
LONG="${TEST_TMPDIR}/long.txt"
jq -nj --rawfile a "${AROUND}" '($a | split("\n")[0] + " ") as $line | ($line * ((17000 / ($line | length)) + 1))
    + ($a | .[(index("\n\n\n\n<pasted_content")):])' > "${LONG}"
assert_equals "B0: control: the derived prompt has over 16 KB of typed text and one real block" "true 1" \
    "$(jq -nr --rawfile t "${LONG}" '$t | "\((index("<pasted_content") > 16384)) \(indices("</pasted_content id=") | length)"')"
# The pin is the status, not a wall-clock bound: on this input the second pass is cheap (few
# trigger hits), so a timing cell passed before the budget existed and would only add flake.
new_session b1; turn - "${LONG}" >/dev/null
assert_equals "B1: the record says skipped and hides nothing" "skipped " "$(last '"\(.status) \(.hidden)"')"
assert_equals "B1: and keeps every selected skill" "$(srt "$(last .selected)")" "$(srt "$(last .kept)")"

# --- N: when there is no record ------------------------------------------------------------
echo "== N: no record =="
new_session n1; turn off "${ONLY}" >/dev/null
assert_equals "N1: ACS_PASTE_SHADOW=off writes no record" "0" "$(nrec)"
new_session n2; turn OFF "${ONLY}" >/dev/null
assert_equals "N2: OFF in capitals is off too" "0" "$(nrec)"
new_session n3b; TP=""; b="$(turn off "${ONLY}")"
new_session n3; TP=""; a="$(turn - "${ONLY}")"
assert_equals "N3: no session token: no record" "0" "$(nrec)"
assert_equals "N3: and the display is unchanged" "${b}" "${a}"
new_session n4; turn - "$(txt "[no-skills] $(cat "${ONLY}")")" >/dev/null
assert_equals "N4: an early exit ([no-skills]) writes no record" "0" "$(nrec)"
new_session n5; turn - "${NEG}" >/dev/null
assert_equals "N5: prose quoting the tags (no wrapper opener): no record" "0" "$(nrec)"
NOLIB="${TEST_TMPDIR}/nolib"; mkdir -p "${NOLIB}"; cp -R "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/config" "${NOLIB}/"; rm -f "${NOLIB}/hooks/lib/pasted-content.sh"
new_session n6b; b="$(turn off "${ONLY}" "${NOLIB}/hooks/skill-activation-hook.sh" "${NOLIB}")"
new_session n6; a="$(turn - "${ONLY}" "${NOLIB}/hooks/skill-activation-hook.sh" "${NOLIB}")"
[ -n "${a}" ] && _record_pass "N6: control: the lib-less copy still routes" || _record_fail "N6: control: the lib-less copy still routes" "nothing displayed"
assert_equals "N6: no lib: display as off" "${b}" "${a}"
assert_equals "N6: no lib: no record" "0" "$(nrec)"

# --- X: the hook still exits 0 on every path the shadow returns early from -------------------
# _paste_shadow is the hook's LAST call, so its status is the hook's exit status.
echo "== X: exit status =="
# xrc <mode> <file> : "<exit status> <bytes on stdout>" of one hook run. The byte count is
# the control: an empty payload also exits 0, at the hook's first early exit.
xrc() {
    local mode="$1" file="$2" pl out rc
    if [ -n "${TP}" ]; then pl="$(jq -nc --rawfile p "${file}" --arg t "${TP}" '{prompt:$p, transcript_path:$t}')"
    else pl="$(jq -nc --rawfile p "${file}" '{prompt:$p}')"; fi
    out="$(printf '%s' "${pl}" | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_PASTE_SHADOW="${mode}" /bin/bash "${HOOK}" 2>/dev/null)"
    rc=$?
    printf '%s %s' "${rc}" "$([ "${#out}" -gt 100 ] && echo routed || echo silent)"
}
new_session x1; TP="";  assert_equals "X1: no session token: exit 0 (routed)" "0 routed" "$(xrc shadow "${ONLY}")"
new_session x2;         assert_equals "X2: off: exit 0 (routed)" "0 routed" "$(xrc off "${ONLY}")"
new_session x3;         assert_equals "X3: no wrapper: exit 0 (routed)" "0 routed" "$(xrc shadow "${ARM}")"
new_session x4;         assert_equals "X4: a record written: exit 0 (routed)" "0 routed" "$(xrc shadow "${ONLY}")"

# --- T: no prompt text in the record --------------------------------------------------------
echo "== T: record text =="
new_session t1; turn - "${AROUND}" >/dev/null; f="$(ls "${RD}" | head -1)"
leak=""
# Words of the prompt (typed and pasted) that no registry skill name contains: a name like
# implementation-drift-check legitimately carries "check".
for w in PR406 Blocking maintainer contradicts below going; do grep -qF "${w}" "${RD}/${f}" && leak="${leak} ${w}"; done
assert_equals "T1: no word of the prompt appears in the record" "" "${leak}"
assert_equals "T1: every string value is a name, a token, a mode or a timestamp" "true" \
    "$(jq '[.. | strings] | all(test("^[A-Za-z0-9._,:-]*$"))' "${RD}/${f}")"

teardown_test_env
print_summary

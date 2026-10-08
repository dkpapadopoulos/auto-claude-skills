#!/usr/bin/env bash
# test-keyword-path-audit.sh — the routing hook's keyword path is measured, and what it
# admits on its own is written down (#310). scripts/keyword-path-audit.sh does the
# measuring, through the real hook; this file holds it to the tree and proves it can fail.
#
#   A*  the shipped config, fixtures and both ledgers agree, and the totals match counts
#       taken here by other means (so a run that measured nothing cannot read as clean)
#   B*  what #310 is about, each as a pair with the unchanged tree: a keyword re-added
#       beside a narrowed trigger (the prototype-lab history of PR #309), a trigger
#       narrowed until a keyword is left admitting alone, a keyword that cannot fire, a
#       decoy the keyword path selects, and a fix that leaves its ledger row behind
#   C*  a ledger that has drifted from the measurement, one finding per injected fault
#   D*  cannot-check is its own outcome, never 0 or 1: a hook that selects nothing or
#       everything, a skill with no fixture or no MATCH line the hook selects, a keyword
#       or fixture line whose probe could not be run, a keyword the hook never scores as
#       a whole prompt, a measurement that did not finish, and arguments it cannot use
#
# The fixture lines go both ways: a NO_MATCH line the hook selects (B1, B4-B6) and a MATCH
# line it does not (B7).
#
# Every mutation is made on a copy, is shown to have changed the copy, and is read by the
# real script. No prompt, regex or substring is evaluated in this file.
#
# Measured 2026-10-08 by removing one decision of the script at a time. A first
# independent review found 21 that no cell held. After those were dealt with, 56 of 62
# removals chosen here failed a cell, and a second review removed 34 of its own choosing,
# of which 12 survived; the six of those that changed a result have cells now.
#
# Known to be unheld, and named so they are not taken for held: emptying the scratch home
# between runs; passing CLAUDE_PLUGIN_ROOT to the hook; the completion line naming its
# skill; the three refusals for a comparison that did not run or printed no totals; trying
# the bare keyword before the longer prompt when confirming an inert answer; the check
# that the payload file is not empty; the --jobs throttle; the hook's place in the
# readable-file loop and that loop's -r test; and refusing a keyword that is not a string.
# That list is what two rounds found, not a proof that nothing else is.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-keyword-path-audit.sh ==="

AUDIT="${PROJECT_ROOT}/scripts/keyword-path-audit.sh"
CONFIG="${PROJECT_ROOT}/config/default-triggers.json"
FALLBACK="${PROJECT_ROOT}/config/fallback-registry.json"
FIXTURES="${PROJECT_ROOT}/tests/fixtures/routing"
LEDGER="${PROJECT_ROOT}/tests/fixtures/keyword-path/decisions.tsv"
KNOWN="${PROJECT_ROOT}/tests/fixtures/keyword-path/known-decoy-selections.tsv"
for _f in "${AUDIT}" "${CONFIG}" "${FALLBACK}" "${LEDGER}" "${KNOWN}"; do
    if [ ! -f "${_f}" ]; then
        _record_fail "file exists: ${_f#"${PROJECT_ROOT}"/}" "missing"; print_summary; exit 1
    fi
done
if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available — keyword-path cells NOT run"; exit 0
fi

setup_test_env
TAB="$(printf '\t')"

# _audit <args...>: run the real script; leaves OUT (stdout), ERR (stderr) and RC.
_audit() {
    OUT="$(bash "${AUDIT}" "$@" < /dev/null 2> "${TEST_TMPDIR}/audit.err")"
    RC=$?
    ERR="$(cat "${TEST_TMPDIR}/audit.err")"
}
_summary_field() { printf '%s\n' "${OUT}" | grep "^SUMMARY${TAB}" | tr '\t' '\n' | sed -n -e "s/^$1=//p"; }
_findings() { printf '%s\n' "${OUT}" | grep -c "^FINDING${TAB}"; }
# _changed <description> <original> <copy>: a mutation that changed nothing proves nothing.
_changed() {
    if cmp -s "$2" "$3"; then _record_fail "$1" "the copy is identical to the original"; else _record_pass "$1"; fi
}

# ---------------------------------------------------------------------------
# A. The tree as shipped.
# ---------------------------------------------------------------------------
echo "-- A: the shipped tree --"
_home_before="$(ls -A "${HOME}/.claude")"
_audit --jobs 8
OUT_FULL="${OUT}"
assert_equals "A1 the audit of the shipped tree exits 0" "0" "${RC}"
assert_equals "A2 no findings" "0" "$(_findings)"

_kw_count="$(jq '[.skills[] | (.keywords // [])[]] | length' "${CONFIG}")"
assert_equals "A3 every keyword in the config was measured" "${_kw_count}" "$(_summary_field keywords)"
assert_equals "A4 and each has a ROW line" "${_kw_count}" "$(printf '%s\n' "${OUT}" | grep -c "^ROW${TAB}")"
if [ "${_kw_count}" -gt 0 ] 2>/dev/null; then _record_pass "A5 the config holds keywords to measure (${_kw_count})"
else _record_fail "A5 the config holds keywords to measure" "counted '${_kw_count}'"; fi

_ledger_rows="$(grep -v -c -E '^[[:space:]]*(#|$)' "${LEDGER}")"
_ko="$(_summary_field keyword-only)"; _in="$(_summary_field inert)"
case "${_ko:-x}${_in:-x}" in *[!0-9]*) _uncovered="not measured" ;; *) _uncovered=$((_ko + _in)) ;; esac
assert_equals "A6 the ledger holds exactly the keyword-only and inert keywords" "${_uncovered}" "${_ledger_rows}"
for _class in covered keyword-only; do
    if [ "$(_summary_field "${_class}")" -gt 0 ] 2>/dev/null; then _record_pass "A7 the measurement can answer ${_class}"
    else _record_fail "A7 the measurement can answer ${_class}" "none measured"; fi
done

# Fixture lines: counted here straight from the fixture files of the skills that carry keywords.
_decoy_count=0
_match_count=0
while IFS= read -r _skill; do
    [ -n "${_skill}" ] || continue
    [ -f "${FIXTURES}/${_skill}.txt" ] || continue
    _n="$(grep -c -E '^[[:space:]]*NO_MATCH:' "${FIXTURES}/${_skill}.txt")"
    _decoy_count=$((_decoy_count + _n))
    _n="$(grep -c -E '^[[:space:]]*MATCH:' "${FIXTURES}/${_skill}.txt")"
    _match_count=$((_match_count + _n))
done <<EOF
$(jq -r '.skills[] | select((.keywords // []) | length > 0) | .name' "${CONFIG}")
EOF
assert_equals "A8 every NO_MATCH line of a keyword-carrying skill went through the hook" "${_decoy_count}" "$(_summary_field decoys)"
assert_equals "A8 and every MATCH line" "${_match_count}" "$(_summary_field matches)"
_known_rows="$(grep -v -c -E '^[[:space:]]*(#|$)' "${KNOWN}")"
assert_equals "A9 the decoys the hook selects are exactly the known ones" "${_known_rows}" "$(_summary_field decoys-selected)"

assert_equals "A10 both config files carry the same keywords, so one audit covers both" \
    "$(jq -S -c '[.skills[] | {name, keywords: (.keywords // [])}]' "${CONFIG}")" \
    "$(jq -S -c '[.skills[] | {name, keywords: (.keywords // [])}]' "${FALLBACK}")"
assert_equals "A11 the audit wrote nothing into the caller's home" "${_home_before}" "$(ls -A "${HOME}/.claude")"

mkdir -p "${TEST_TMPDIR}/scratch"
TMPDIR="${TEST_TMPDIR}/scratch" _audit --skill skill-scaffold
assert_equals "A12 a run scoped to one skill is clean too" "0" "${RC}"
assert_equals "A12 and leaves nothing in its scratch directory" "" "$(ls -A "${TEST_TMPDIR}/scratch")"
assert_equals "A12 and measures only that skill" \
    "$(jq '[.skills[] | select(.name == "skill-scaffold") | .keywords[]] | length' "${CONFIG}")" "$(_summary_field keywords)"

# ---------------------------------------------------------------------------
# B. The defect class, as flipping pairs against the unchanged tree (A is the control).
# ---------------------------------------------------------------------------
echo "-- B: a keyword admitting where a trigger does not --"

# B1. PR #309 narrowed prototype-lab's side-by-side trigger and had to delete the "side
# by side" keyword as well: with the keyword left in, five of six false dispatches came
# back and the suite stayed green. Put it back and the audit has to say so, twice.
assert_not_contains "B1 precondition: prototype-lab ships no \"side by side\" keyword" \
    "ROW${TAB}prototype-lab${TAB}side by side${TAB}" "${OUT_FULL}"
_m="${TEST_TMPDIR}/b1.json"
jq '(.skills[] | select(.name == "prototype-lab") | .keywords) += ["side by side"]' "${CONFIG}" > "${_m}"
_changed "B1 the keyword was added to the copy" "${CONFIG}" "${_m}"
_audit --skill prototype-lab --config "${_m}"
assert_equals "B1 the audit fails" "1" "${RC}"
assert_contains "B1 the keyword is reported as admitting on its own, undecided" \
    "FINDING${TAB}unrecorded${TAB}prototype-lab${TAB}side by side${TAB}measured keyword-only" "${OUT}"
assert_contains "B1 and a NO_MATCH line of the skill's fixture is reported selected through it" \
    "FINDING${TAB}decoy-selected${TAB}prototype-lab${TAB}show the two diffs side by side in the review ui${TAB}a NO_MATCH line of its own fixture is selected (via keywords)" "${OUT}"

# B2. The risk #310 names first: a trigger is narrowed, the regex is measured and works,
# and a keyword that used to be redundant now admits what the regex excludes.
assert_contains "B2 precondition: \"launch checklist\" is covered by a trigger today" \
    "ROW${TAB}deploy-gate${TAB}launch checklist${TAB}covered" "${OUT_FULL}"
_m="${TEST_TMPDIR}/b2.json"
jq '(.skills[] | select(.name == "deploy-gate") | .triggers[0]) |= sub("launch\\|"; "")
    | (.skills[] | select(.name == "deploy-gate") | .keywords) += ["Launch Checklist", "ship", "Deploy-Gate", "hello"]' "${CONFIG}" > "${_m}"
_changed "B2 the trigger was narrowed in the copy" "${CONFIG}" "${_m}"
assert_not_contains "B2 the copy's trigger no longer names launch" "launch" \
    "$(jq -r '.skills[] | select(.name == "deploy-gate") | .triggers[0]' "${_m}")"
_audit --skill deploy-gate --config "${_m}"
assert_equals "B2 the audit fails" "1" "${RC}"
assert_contains "B2 the keyword left admitting alone is reported" \
    "FINDING${TAB}unrecorded${TAB}deploy-gate${TAB}launch checklist${TAB}measured keyword-only" "${OUT}"
# B3. Same run: two keywords that can never fire, one for each reason the hook has.
assert_contains "B3 a keyword holding a capital is reported inert" \
    "FINDING${TAB}unrecorded${TAB}deploy-gate${TAB}Launch Checklist${TAB}measured inert" "${OUT}"
assert_contains "B3 a keyword under six characters is reported inert" \
    "FINDING${TAB}unrecorded${TAB}deploy-gate${TAB}ship${TAB}measured inert" "${OUT}"
# The skill's own name, with a capital. Typed as a prompt it selects the skill by name,
# and a trigger admits it too, so measured under the real name this dead keyword reads as
# covered. The audit renames the subject for exactly this.
assert_contains "B3 a dead keyword spelling the skill's own name is still reported inert" \
    "FINDING${TAB}unrecorded${TAB}deploy-gate${TAB}Deploy-Gate${TAB}measured inert" "${OUT}"
# A greeting too short to fire. The hook leaves early on the bare word and on the word
# followed by up to twenty characters, so it is confirmed inert on a longer prompt.
assert_contains "B3 a short greeting word is reported inert, not refused" \
    "FINDING${TAB}unrecorded${TAB}deploy-gate${TAB}hello${TAB}measured inert" "${OUT}"
assert_equals "B2/B3 five faults, five findings" "5" "$(_findings)"

# B4. A decoy the keyword path selects is a finding unless it is listed as known ...
_decoy="make this error message less generic so users understand what went wrong"
_m="${TEST_TMPDIR}/b4-known.tsv"
awk -F'\t' '!($1 == "authorial-judgment")' "${KNOWN}" > "${_m}"
_changed "B4 the known row was removed from the copy" "${KNOWN}" "${_m}"
_audit --skill authorial-judgment --known "${_m}"
assert_equals "B4 the audit fails" "1" "${RC}"
assert_contains "B4 the selected decoy is reported, with the path that selected it" \
    "FINDING${TAB}decoy-selected${TAB}authorial-judgment${TAB}${_decoy}${TAB}a NO_MATCH line of its own fixture is selected (via keywords)" "${OUT}"
assert_equals "B4 one fault, one finding" "1" "$(_findings)"
# B5. ... and once the keyword is gone, both ledgers must give their rows back.
_m="${TEST_TMPDIR}/b5.json"
jq '(.skills[] | select(.name == "authorial-judgment") | .keywords) -= ["less generic"]' "${CONFIG}" > "${_m}"
_changed "B5 the keyword was removed from the copy" "${CONFIG}" "${_m}"
_k="${TEST_TMPDIR}/b5-known.tsv"
{
    cat "${KNOWN}"
    printf 'authorial-judgment\tinjected: no fixture has this line\tinjected\n'
    printf 'authorial-judgment\tinjected: a row with a field missing\n'
} > "${_k}"
_audit --skill authorial-judgment --config "${_m}" --known "${_k}"
assert_equals "B5 the audit fails" "1" "${RC}"
assert_contains "B5 the decoy is no longer selected, and its known row is reported stale" \
    "FINDING${TAB}known-stale${TAB}authorial-judgment${TAB}${_decoy}${TAB}no longer selected" "${OUT}"
assert_contains "B5 and so is the decision row for a keyword that no longer exists" \
    "FINDING${TAB}ledger-stale${TAB}authorial-judgment${TAB}less generic${TAB}no such keyword in the config" "${OUT}"
assert_contains "B5 a known row for a line no fixture holds is reported stale" \
    "FINDING${TAB}known-stale${TAB}authorial-judgment${TAB}injected: no fixture has this line${TAB}no such NO_MATCH line in the fixture" "${OUT}"
assert_contains "B5 a known row with a field missing is reported" \
    "FINDING${TAB}known-malformed${TAB}-${TAB}-${TAB}" "${OUT}"
assert_equals "B5 one fix and two injected rows, four findings" "4" "$(_findings)"

# B6. A decoy selected for another reason is not laid at the keyword path's door.
_fx="${TEST_TMPDIR}/b6-fixtures"; mkdir -p "${_fx}"
{ cat "${FIXTURES}/skill-scaffold.txt"; printf 'NO_MATCH: run skill-scaffold now\n'; } > "${_fx}/skill-scaffold.txt"
_audit --skill skill-scaffold --fixtures "${_fx}"
assert_equals "B6 the audit fails" "1" "${RC}"
assert_contains "B6 a decoy the skill's own name selects is reported as not the keyword path" \
    "FINDING${TAB}decoy-selected${TAB}skill-scaffold${TAB}run skill-scaffold now${TAB}a NO_MATCH line of its own fixture is selected (via other)" "${OUT}"
assert_equals "B6 one fault, one finding" "1" "$(_findings)"

# B6b. The same decoy, with its payload three seconds late. The hook stops waiting for
# stdin after two, and a payload piped to it late was read as no prompt: the selected
# decoy came back unselected and the audit exited 0. The shim delays only the payload for
# this one prompt and leaves a marker, so a shim that never fired cannot pass the cell.
_shim="${TEST_TMPDIR}/shim"; mkdir -p "${_shim}"
_real_jq="$(command -v jq)"
cat > "${_shim}/jq" <<SHIM
#!/bin/bash
if [ "\$1" = "-n" ] && [ "\$4" = "run skill-scaffold now" ]; then : > "${_shim}/stalled"; sleep 3; fi
exec "${_real_jq}" "\$@"
SHIM
chmod +x "${_shim}/jq"
PATH="${_shim}:${PATH}" _audit --skill skill-scaffold --fixtures "${_fx}"
assert_file_exists "B6b the shim delayed that payload" "${_shim}/stalled"
assert_equals "B6b the audit still fails" "1" "${RC}"
assert_contains "B6b and still reports the decoy as selected" \
    "FINDING${TAB}decoy-selected${TAB}skill-scaffold${TAB}run skill-scaffold now${TAB}a NO_MATCH line of its own fixture is selected (via other)" "${OUT}"

# B8. In a scoped run a known row for another skill is not this run's business, and a
# known row with an empty field is not a row.
_k="${TEST_TMPDIR}/b8-known.tsv"
{
    cat "${KNOWN}"
    printf 'product-discovery\tinjected: a row for another skill\tinjected\n'
    printf 'skill-scaffold\t\tinjected: an empty prompt\n'
    printf 'skill-scaffold\tinjected: a row with an empty reason\t\n'
} > "${_k}"
_audit --skill skill-scaffold --known "${_k}"
assert_equals "B8 the audit fails" "1" "${RC}"
assert_equals "B8 a known row with an empty prompt and one with an empty reason are both reported" \
    "2" "$(printf '%s\n' "${OUT}" | grep -c "^FINDING${TAB}known-malformed${TAB}-${TAB}-${TAB}")"
assert_equals "B8 and the other skill's row is left alone: two findings" "2" "$(_findings)"

# B7. The other direction: a MATCH line the hook does not select. With no finding for
# it, a deleted keyword could take away a prompt the fixture says the skill must get.
_fx="${TEST_TMPDIR}/b7-fixtures"; mkdir -p "${_fx}"
{ cat "${FIXTURES}/skill-scaffold.txt"; printf 'MATCH: zzzz qqqq vvvv\n'; } > "${_fx}/skill-scaffold.txt"
_audit --skill skill-scaffold --fixtures "${_fx}"
assert_equals "B7 the audit fails" "1" "${RC}"
assert_contains "B7 a MATCH line that is not selected is reported" \
    "FINDING${TAB}match-unselected${TAB}skill-scaffold${TAB}zzzz qqqq vvvv${TAB}a MATCH line of its own fixture is not selected" "${OUT}"
assert_equals "B7 one fault, one finding" "1" "$(_findings)"

# ---------------------------------------------------------------------------
# C. A ledger that no longer describes the measurement.
# ---------------------------------------------------------------------------
echo "-- C: ledger drift --"
_m="${TEST_TMPDIR}/c1.tsv"
{
    awk -F'\t' '!($1 == "skill-scaffold" && $2 == "create skill")' "${LEDGER}"
    printf 'skill-scaffold\tnew skill\tkeyword-only\trecall\tinjected: this keyword is covered\n'
    printf 'skill-scaffold\tno such keyword\tkeyword-only\trecall\tinjected: not in the config\n'
    printf 'skill-scaffold\tskill skeleton\tkeyword-only\tkeep\tinjected: not a decision word\n'
    printf 'skill-scaffold\tscaffold\tkeyword-only\n'
} > "${_m}"
_changed "C the ledger copy differs" "${LEDGER}" "${_m}"
_audit --skill skill-scaffold --ledger "${_m}"
assert_equals "C the audit fails" "1" "${RC}"
assert_contains "C1 a missing row is reported" \
    "FINDING${TAB}unrecorded${TAB}skill-scaffold${TAB}create skill${TAB}measured keyword-only" "${OUT}"
assert_contains "C2 a row for a covered keyword is reported stale" \
    "FINDING${TAB}ledger-stale${TAB}skill-scaffold${TAB}new skill${TAB}recorded as keyword-only, measured covered" "${OUT}"
assert_contains "C3 a row for a keyword that does not exist is reported stale" \
    "FINDING${TAB}ledger-stale${TAB}skill-scaffold${TAB}no such keyword${TAB}no such keyword in the config" "${OUT}"
assert_contains "C4 an unknown decision word is reported" \
    "FINDING${TAB}ledger-malformed${TAB}skill-scaffold${TAB}skill skeleton${TAB}" "${OUT}"
assert_contains "C5 a row with fields missing is reported" \
    "FINDING${TAB}ledger-malformed${TAB}-${TAB}-${TAB}" "${OUT}"
assert_equals "C1-C5 five faults, five findings" "5" "$(_findings)"

_m="${TEST_TMPDIR}/c6.tsv"
awk -F'\t' 'BEGIN { OFS = "\t" }
    $1 == "agent-safety-review" && $2 == "lethal trifecta" { $3 = "inert"; $4 = "open" }
    $1 == "agent-safety-review" && $2 == "YOLO mode" { $4 = "recall" }
    { print }' "${LEDGER}" > "${_m}"
{
    printf 'agent-safety-review\tlethal trifecta\tkeyword-only\trecall\tinjected: a second row for one keyword\n'
    printf 'agent-safety-review\tunattended\tsometimes\topen\tinjected: not a class\n'
    printf 'agent-safety-review\temail agent\tkeyword-only\trecall\t\n'
    printf '\tbrowser agent\tkeyword-only\trecall\tinjected: no skill named\n'
} >> "${_m}"
_changed "C the second ledger copy differs" "${LEDGER}" "${_m}"
_c="${TEST_TMPDIR}/c8.json"
jq '(.skills[] | select(.name == "agent-safety-review") | .keywords) += ["agent-safety-review"]' "${CONFIG}" > "${_c}"
_changed "C8 the config copy differs" "${CONFIG}" "${_c}"
_audit --skill agent-safety-review --ledger "${_m}" --config "${_c}"
assert_equals "C the audit fails" "1" "${RC}"
assert_contains "C6 a row whose class is no longer true is reported" \
    "FINDING${TAB}class-changed${TAB}agent-safety-review${TAB}lethal trifecta${TAB}recorded as inert, measured keyword-only" "${OUT}"
assert_contains "C7 an inert keyword cannot be recorded as recall" \
    "FINDING${TAB}ledger-malformed${TAB}agent-safety-review${TAB}YOLO mode${TAB}" "${OUT}"
# The refused row is not a row: its keyword is then reported as having none.
assert_contains "C7 and the keyword behind the refused row is reported as undecided" \
    "FINDING${TAB}unrecorded${TAB}agent-safety-review${TAB}YOLO mode${TAB}measured inert" "${OUT}"
assert_contains "C9 a second row for one keyword is reported" \
    "FINDING${TAB}ledger-malformed${TAB}agent-safety-review${TAB}lethal trifecta${TAB}line" "${OUT}"
assert_contains "C10 a class that is not one is reported" \
    "FINDING${TAB}ledger-malformed${TAB}agent-safety-review${TAB}unattended${TAB}" "${OUT}"
assert_equals "C11 a row with an empty reason and a row with an empty skill are both reported" \
    "2" "$(printf '%s\n' "${OUT}" | grep -c "^FINDING${TAB}ledger-malformed${TAB}-${TAB}-${TAB}")"
# C8. A live keyword spelling the skill's own name. No trigger admits it, so it is
# keyword-only; with the trigger probe run under the real name, the name itself would
# select the skill and the keyword would read covered.
assert_contains "C8 a keyword spelling the skill's own name is measured without the name's help" \
    "FINDING${TAB}unrecorded${TAB}agent-safety-review${TAB}agent-safety-review${TAB}measured keyword-only" "${OUT}"
assert_equals "C6-C11 seven faults, eight findings" "8" "$(_findings)"

# ---------------------------------------------------------------------------
# D. Could not measure is not a result.
# ---------------------------------------------------------------------------
echo "-- D: cannot check --"
_audit --config "${TEST_TMPDIR}/no-such-config.json"
assert_equals "D1 a missing config exits 3" "3" "${RC}"
assert_contains "D1 and says which file" "not a readable file: ${TEST_TMPDIR}/no-such-config.json" "${ERR}"
_audit --ledger "${TEST_TMPDIR}/no-such-ledger.tsv"
assert_equals "D2 a missing ledger exits 3" "3" "${RC}"
assert_contains "D2 and says which file" "not a readable file: ${TEST_TMPDIR}/no-such-ledger.tsv" "${ERR}"
_audit --known "${TEST_TMPDIR}/no-such-known.tsv"
assert_equals "D2 a missing known file exits 3" "3" "${RC}"
assert_contains "D2 and says which file" "not a readable file: ${TEST_TMPDIR}/no-such-known.tsv" "${ERR}"
_audit --fixtures "${TEST_TMPDIR}/no-such-dir"
assert_equals "D2 a missing fixtures directory exits 3" "3" "${RC}"
assert_contains "D2 and says so" "not a directory" "${ERR}"
_audit --skill no-such-skill
assert_equals "D3 a skill that is not there, or has no keywords, exits 3" "3" "${RC}"
assert_contains "D3 and says so" "no skill with keywords to measure" "${ERR}"
for _bad in 0 x 04 1000; do
    _audit --skill skill-scaffold --jobs "${_bad}"
    assert_equals "D3 --jobs ${_bad} exits 3" "3" "${RC}"
    assert_contains "D3 --jobs ${_bad} says why" "--jobs needs a positive whole number" "${ERR}"
done
_audit --skill
assert_equals "D3 an option with no value exits 3" "3" "${RC}"
assert_contains "D3 and says so" "--skill needs a value" "${ERR}"
_audit --no-such-option
assert_equals "D3 an unknown argument exits 3" "3" "${RC}"
assert_contains "D3 and says so" "unknown argument: --no-such-option" "${ERR}"

# A hook that prints nothing makes every keyword look inert and every decoy unselected.
_dead="${TEST_TMPDIR}/dead/hooks"; mkdir -p "${_dead}"
printf '#!/bin/bash\ncat >/dev/null\nexit 0\n' > "${_dead}/skill-activation-hook.sh"
chmod +x "${_dead}/skill-activation-hook.sh"
_audit --skill skill-scaffold --hook "${_dead}/skill-activation-hook.sh"
assert_equals "D4 a hook that selects nothing exits 3" "3" "${RC}"
assert_contains "D4 and the refusal names the failed control" "controls failed" "${ERR}"
assert_not_contains "D4 and no summary is printed" "SUMMARY" "${OUT}"

# A hook that names every skill it was given makes every keyword look covered.
_loud="${TEST_TMPDIR}/loud/hooks"; mkdir -p "${_loud}"
printf '#!/bin/bash\ncat >/dev/null\ncat "${HOME}/.claude/.skill-registry-cache.json"\n' > "${_loud}/skill-activation-hook.sh"
chmod +x "${_loud}/skill-activation-hook.sh"
_audit --skill skill-scaffold --hook "${_loud}/skill-activation-hook.sh"
assert_equals "D5 a hook that selects everything exits 3" "3" "${RC}"
assert_contains "D5 and the refusal names the failed control" "controls failed" "${ERR}"

# The two nonsense-prompt controls, one at a time. Each wrapper answers honestly, through
# the real hook, except for the one registry it lies about.
_real_hook="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
for _lie in neutral real; do
    _w="${TEST_TMPDIR}/lie-${_lie}/hooks"; mkdir -p "${_w}"
    if [ "${_lie}" = neutral ]; then _when='!='; else _when='=='; fi
    cat > "${_w}/skill-activation-hook.sh" <<WRAP
#!/bin/bash
if jq -e '.skills[0].name ${_when} "skill-scaffold"' "\${HOME}/.claude/.skill-registry-cache.json" >/dev/null 2>&1; then
    cat >/dev/null
    cat "\${HOME}/.claude/.skill-registry-cache.json"
else
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" exec "${_real_hook}"
fi
WRAP
    chmod +x "${_w}/skill-activation-hook.sh"
    _audit --skill skill-scaffold --hook "${_w}/skill-activation-hook.sh"
    assert_equals "D5 a hook that always selects under the ${_lie} name exits 3" "3" "${RC}"
    assert_contains "D5 and the refusal names the failed control (${_lie})" "controls failed" "${ERR}"
done
assert_contains "D5 the last refusal is the real-name control alone" "selected=0, own name selected=1, nonsense prompt under the real name=1" "${ERR}"

# An unselected decoy is evidence only if the same registry can be seen to select.
_fx="${TEST_TMPDIR}/fixtures"; mkdir -p "${_fx}"
sed -e 's/^\([[:space:]]*\)MATCH:.*/\1MATCH: zzzz qqqq vvvv/' "${FIXTURES}/skill-scaffold.txt" > "${_fx}/skill-scaffold.txt"
_changed "D6 the fixture copy differs" "${FIXTURES}/skill-scaffold.txt" "${_fx}/skill-scaffold.txt"
_audit --skill skill-scaffold --fixtures "${_fx}"
assert_equals "D6 a fixture none of whose MATCH lines is selected exits 3" "3" "${RC}"
assert_contains "D6 and the refusal says why" "no MATCH line of its fixture is selected" "${ERR}"

# A skill that carries keywords and has no fixture, or no MATCH line, or only an empty
# one, had its decoys skipped and the run exit 0.
mkdir -p "${TEST_TMPDIR}/fx-none"
_audit --skill skill-scaffold --fixtures "${TEST_TMPDIR}/fx-none"
assert_equals "D6 a keyword-carrying skill with no fixture exits 3" "3" "${RC}"
assert_contains "D6 and the refusal says why" "no routing fixture" "${ERR}"
_fx="${TEST_TMPDIR}/fx-nomatch"; mkdir -p "${_fx}"
grep -v -E '^[[:space:]]*MATCH:' "${FIXTURES}/skill-scaffold.txt" > "${_fx}/skill-scaffold.txt"
_changed "D6 the fixture copy has lost its MATCH lines" "${FIXTURES}/skill-scaffold.txt" "${_fx}/skill-scaffold.txt"
_audit --skill skill-scaffold --fixtures "${_fx}"
assert_equals "D6 a fixture with no MATCH line exits 3" "3" "${RC}"
assert_contains "D6 and the refusal says why" "no MATCH line of its fixture is selected" "${ERR}"
printf 'MATCH:\n' >> "${_fx}/skill-scaffold.txt"
_audit --skill skill-scaffold --fixtures "${_fx}"
assert_equals "D6 a fixture whose only MATCH line is empty exits 3" "3" "${RC}"
for _kind in MATCH NO_MATCH; do
    _fx="${TEST_TMPDIR}/fx-tab-${_kind}"; mkdir -p "${_fx}"
    { cat "${FIXTURES}/skill-scaffold.txt"; printf '%s: one\ttwo\n' "${_kind}"; } > "${_fx}/skill-scaffold.txt"
    _audit --skill skill-scaffold --fixtures "${_fx}"
    assert_equals "D6 a ${_kind} prompt holding a tab exits 3" "3" "${RC}"
    assert_contains "D6 and the refusal says why (${_kind})" "holds a tab" "${ERR}"
done
# A tab that only indents the line is not in the prompt, and an empty directive is not a
# prompt: neither is refused, and neither is counted.
_audit --skill skill-scaffold
_plain_matches="$(_summary_field matches)"; _plain_decoys="$(_summary_field decoys)"
_fx="${TEST_TMPDIR}/fx-indent"; mkdir -p "${_fx}"
{ sed -e "s/^NO_MATCH: /${TAB}NO_MATCH: /" -e "s/^MATCH: /${TAB}MATCH: /" "${FIXTURES}/skill-scaffold.txt"; printf 'MATCH:\nNO_MATCH:\n'; } > "${_fx}/skill-scaffold.txt"
_changed "D6 the indented fixture copy differs" "${FIXTURES}/skill-scaffold.txt" "${_fx}/skill-scaffold.txt"
_audit --skill skill-scaffold --fixtures "${_fx}"
assert_equals "D6 tab-indented lines and empty directives are read, not refused" "0" "${RC}"
assert_equals "D6 the same MATCH lines are counted" "${_plain_matches}" "$(_summary_field matches)"
assert_equals "D6 the same NO_MATCH lines are counted" "${_plain_decoys}" "$(_summary_field decoys)"

# A fixture line whose registry is gone when its turn comes is not an unselected line.
# The wrapper answers through the real hook, then removes the audit's copy of the skill's
# entry once the injected decoy's first answer is out.
_fx="${TEST_TMPDIR}/fx-gone"; mkdir -p "${_fx}"
{ cat "${FIXTURES}/skill-scaffold.txt"; printf 'NO_MATCH: run skill-scaffold now\n'; } > "${_fx}/skill-scaffold.txt"
_w="${TEST_TMPDIR}/gone/hooks"; mkdir -p "${_w}"
cat > "${_w}/skill-activation-hook.sh" <<WRAP
#!/bin/bash
_payload="\$(cat)"
printf '%s' "\${_payload}" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" "${_real_hook}"
case "\${_payload}" in *"run skill-scaffold now"*)
    case "\${HOME}" in */keyword-path-audit.*/*/home) rm -f "\${HOME%/home}/entry.json" ;; esac ;;
esac
WRAP
chmod +x "${_w}/skill-activation-hook.sh"
_audit --skill skill-scaffold --fixtures "${_fx}" --hook "${_w}/skill-activation-hook.sh"
assert_equals "D6 a decoy that could not be measured exits 3" "3" "${RC}"
assert_contains "D6 and the refusal says why" "a NO_MATCH line could not be measured: run skill-scaffold now" "${ERR}"
# The same for a MATCH line: one that could not be run is not a line that was not selected.
# The fixture copy keeps MATCH lines only, so nothing else can refuse the run first.
_fx="${TEST_TMPDIR}/fx-gone-match"; mkdir -p "${_fx}"
grep -E '^[[:space:]]*MATCH:' "${FIXTURES}/skill-scaffold.txt" > "${_fx}/skill-scaffold.txt"
sed -n -e 's/^[[:space:]]*MATCH:[[:space:]]*//p' "${_fx}/skill-scaffold.txt" | head -1 > "${TEST_TMPDIR}/first-match.txt"
if [ "$(grep -c -E '^[[:space:]]*MATCH:' "${_fx}/skill-scaffold.txt")" -ge 2 ] && [ -s "${TEST_TMPDIR}/first-match.txt" ]; then
    _record_pass "D6 the fixture copy holds at least two MATCH lines and nothing else"
else
    _record_fail "D6 the fixture copy holds at least two MATCH lines and nothing else" "it does not"
fi
_w="${TEST_TMPDIR}/gone-match/hooks"; mkdir -p "${_w}"
cat > "${_w}/skill-activation-hook.sh" <<WRAP
#!/bin/bash
_payload="\$(cat)"
printf '%s' "\${_payload}" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" "${_real_hook}"
if printf '%s' "\${_payload}" | grep -q -F -f "${TEST_TMPDIR}/first-match.txt"; then
    case "\${HOME}" in */keyword-path-audit.*/*/home) rm -f "\${HOME%/home}/entry.json" ;; esac
fi
WRAP
chmod +x "${_w}/skill-activation-hook.sh"
_audit --skill skill-scaffold --fixtures "${_fx}" --hook "${_w}/skill-activation-hook.sh"
assert_equals "D6 a MATCH line that could not be measured exits 3" "3" "${RC}"
assert_contains "D6 and the refusal says why" "a MATCH line could not be measured" "${ERR}"

# A measurement that lost its output is not a short measurement. The stub removes the
# audit's own row files (and only those: the path has to be the audit's scratch).
_cut="${TEST_TMPDIR}/cut/hooks"; mkdir -p "${_cut}"
cat > "${_cut}/skill-activation-hook.sh" <<'STUB'
#!/bin/bash
cat >/dev/null
case "${HOME}" in */keyword-path-audit.*/*/home) rm -f "${HOME%/*/home}"/*.rows ;; esac
STUB
chmod +x "${_cut}/skill-activation-hook.sh"
_audit --skill skill-scaffold --hook "${_cut}/skill-activation-hook.sh"
assert_equals "D7 a measurement whose output is gone exits 3" "3" "${RC}"
assert_contains "D7 and the refusal says it did not finish" "did not finish" "${ERR}"

_m="${TEST_TMPDIR}/d8.json"
jq '.skills += [.skills[] | select(.name == "skill-scaffold")]' "${CONFIG}" > "${_m}"
_changed "D8 the config copy differs" "${CONFIG}" "${_m}"
_audit --skill skill-scaffold --config "${_m}"
assert_equals "D8 a skill with two config entries exits 3" "3" "${RC}"
assert_contains "D8 and the refusal says why" "not exactly one config entry" "${ERR}"

_m="${TEST_TMPDIR}/d9.json"
jq '(.skills[] | select(.name == "skill-scaffold") | .keywords) += ["two\nlines"]' "${CONFIG}" > "${_m}"
_changed "D9 the config copy differs" "${CONFIG}" "${_m}"
_audit --skill skill-scaffold --config "${_m}"
assert_equals "D9 a keyword that spans lines exits 3" "3" "${RC}"
assert_contains "D9 and the refusal says why" "not a one-line string" "${ERR}"
_m="${TEST_TMPDIR}/d9b.json"
jq '(.skills[] | select(.name == "skill-scaffold") | .keywords) += [""]' "${CONFIG}" > "${_m}"
_changed "D9 the second config copy differs" "${CONFIG}" "${_m}"
_audit --skill skill-scaffold --config "${_m}"
assert_equals "D9 an empty keyword exits 3" "3" "${RC}"
assert_contains "D9 and the refusal says why" "or is empty" "${ERR}"

# The hook leaves before scoring on a bare greeting, so a keyword shaped like one would
# read inert while firing inside a longer prompt. It is refused, not classified.
_m="${TEST_TMPDIR}/d11.json"
jq '(.skills[] | select(.name == "skill-scaffold") | .keywords) += ["thanks team"]' "${CONFIG}" > "${_m}"
_changed "D11 the config copy differs" "${CONFIG}" "${_m}"
_audit --skill skill-scaffold --config "${_m}"
assert_equals "D11 a keyword the hook never scores when it is the whole prompt exits 3" "3" "${RC}"
assert_contains "D11 and the refusal names it" 'keyword "thanks team" could not be measured' "${ERR}"
# The same, where a longer prompt IS scored and the keyword fires in it: the hook's
# greeting rule allows twenty characters after the greeting, and the probe's nonsense
# words carry this keyword past them. Reading it inert there would be the false answer.
_m="${TEST_TMPDIR}/d11b.json"
jq '(.skills[] | select(.name == "skill-scaffold") | .keywords) += ["thanks everybody"]' "${CONFIG}" > "${_m}"
_changed "D11 the second config copy differs" "${CONFIG}" "${_m}"
_audit --skill skill-scaffold --config "${_m}"
assert_equals "D11 a keyword that fires only once the prompt is long enough to be scored exits 3" "3" "${RC}"
assert_contains "D11 and the refusal names it" 'keyword "thanks everybody" could not be measured' "${ERR}"
# And where no longer prompt is scored either: a leading slash stops the hook however much
# follows it, so nothing shows whether this keyword fires in the middle of a prompt.
_m="${TEST_TMPDIR}/d11c.json"
jq '(.skills[] | select(.name == "skill-scaffold") | .keywords) += ["/scaffold now"]' "${CONFIG}" > "${_m}"
_changed "D11 the third config copy differs" "${CONFIG}" "${_m}"
_audit --skill skill-scaffold --config "${_m}"
assert_equals "D11 a keyword no prompt starting with it is ever scored for exits 3" "3" "${RC}"
assert_contains "D11 and the refusal names it" 'keyword "/scaffold now" could not be measured' "${ERR}"

# awk takes an operand shaped name=value for an assignment and never opens the file.
_d="${TEST_TMPDIR}/d12"; mkdir -p "${_d}"
{ cat "${KNOWN}"; printf 'skill-scaffold\tinjected: no fixture has this line\tinjected\n'; } > "${_d}/k=v.tsv"
OUT="$(cd "${_d}" && bash "${AUDIT}" --skill skill-scaffold --known "k=v.tsv" < /dev/null 2> "${TEST_TMPDIR}/audit.err")"
RC=$?
assert_equals "D12 a known file named like an assignment is still read" "1" "${RC}"
assert_contains "D12 and its stale row is reported" \
    "FINDING${TAB}known-stale${TAB}skill-scaffold${TAB}injected: no fixture has this line${TAB}" "${OUT}"
{ cat "${LEDGER}"; printf 'skill-scaffold\tno such keyword\tkeyword-only\trecall\tinjected\n'; } > "${_d}/l=1.tsv"
OUT="$(cd "${_d}" && bash "${AUDIT}" --skill skill-scaffold --ledger "l=1.tsv" < /dev/null 2> "${TEST_TMPDIR}/audit.err")"
RC=$?
assert_equals "D12 a ledger named like an assignment is still read" "1" "${RC}"
assert_contains "D12 and its stale row is reported" \
    "FINDING${TAB}ledger-stale${TAB}skill-scaffold${TAB}no such keyword${TAB}" "${OUT}"

# The hook is run through its own shebang. One that cannot be executed is not measured
# through some other interpreter instead.
_noexec="${TEST_TMPDIR}/noexec/hooks"; mkdir -p "${_noexec}"
cp "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" "${_noexec}/skill-activation-hook.sh"
chmod -x "${_noexec}/skill-activation-hook.sh"
_audit --skill skill-scaffold --hook "${_noexec}/skill-activation-hook.sh"
assert_equals "D10 a hook that is not executable exits 3" "3" "${RC}"
assert_contains "D10 and the refusal says why" "not executable" "${ERR}"

teardown_test_env
print_summary

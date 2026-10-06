#!/usr/bin/env bash
# test-activation-sticky-repeat.sh — the sticky-repeat rule (#333).
#
# Once a prompt arms a composition chain, the activation hook re-emits the chain's CURRENT
# step as MUST INVOKE on every later short prompt that selects no process skill of its own
# ("sticky composition"). The rule under test hides such a block when the session has
# already been shown that step on that chain.
#
# It is not known to be an improvement, so it ships in SHADOW: the default displays exactly
# as before and records what the rule would hide. `ACS_STICKY_REPEAT` selects shadow |
# trial | suppress | off. This file holds four things:
#
#   1. SHADOW CHANGES NOTHING the model sees (byte-identical display to `off`).
#   2. WHAT IS HIDDEN in suppress mode, and above all what is NOT: a step's first display,
#      a prompt whose own words select the skill, a block that carries any other skill the
#      prompt selected, a step on a different chain, a step after a compaction (manual OR
#      auto), a step of a new task after a cancel, and anything at all when the marker is
#      missing.
#   3. DISPLAY-ONLY. Every state file the hook wrote before this rule existed is identical,
#      turn by turn, between `off` and each other mode. The comparison is not vacuous: an
#      exit-early mutant of the same hook must DIFFER (X1), and the state must be seen to
#      move on the very turns that are hidden (ID control). The push gate's decision is
#      pinned separately in tests/test-push-gate-display-suppression.sh.
#   4. THE RECORD says what happened: each shadow record is checked against the display the
#      same turn actually produced, and it carries no prompt text.
#   5. THE MARKER IS BELIEVED ONLY WHEN IT SHOULD BE (cells F, from cross-family review of
#      the first cut): not for another chain, not when no chain was walked, not when it is
#      a directory, unreadable or a symlink; its read is bounded; nothing is written
#      through a symlink onto a state file; and shadow adds nothing to stderr either.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-activation-sticky-repeat.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
COMPACT="${PROJECT_ROOT}/hooks/compact-recovery-hook.sh"
PRECOMPACT="${PROJECT_ROOT}/hooks/pre-compact-hook.sh"
FIX="${PROJECT_ROOT}/tests/fixtures/routing-input"

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available — sticky-repeat cells NOT run"; exit 0
fi

setup_test_env
REG="${TEST_TMPDIR}/registry.json"
jq '.skills |= map(.available = true | .enabled = true)' "${PROJECT_ROOT}/config/default-triggers.json" > "${REG}"

# new_session [token-suffix] : a fresh HOME whose transcript basename becomes the session
# token (session-<suffix>). The suffix's last character decides the trial arm.
new_session() {
    H="$(mktemp -d "${TEST_TMPDIR}/s.XXXXXX")"
    mkdir -p "${H}/.claude" && cp "${REG}" "${H}/.claude/.skill-registry-cache.json"
    TP="${H}/${1:-sess0}.jsonl"; touch "${TP}"
    TOK="session-${1:-sess0}"
    LOGD="${H}/.claude/.sticky-repeat-shadow.d"   # the hook writes one small file per record
    LOG="${H}/records.jsonl"                      # those files, oldest first, for the cells to read
    MARK="${H}/.claude/.sticky-repeat-shown-${TOK}"
}
# sync_log : rebuild ${H}/records.jsonl from the record directory of the CURRENT home.
sync_log() {
    local d="${H}/.claude/.sticky-repeat-shadow.d" _lf
    : > "${H}/records.jsonl"
    [ -d "${d}" ] || return 0
    for _lf in $(ls -tr "${d}" 2>/dev/null); do cat "${d}/${_lf}" >> "${H}/records.jsonl"; done
}
# turn <mode|-> <prompt> [hook] : drive the hook; prints what it displayed ("" for nothing).
# Mode "-" leaves ACS_STICKY_REPEAT unset, which is how the default is tested.
turn() {
    local mode="$1" prompt="$2" hook="${3:-${HOOK}}"
    if [ "${mode}" = "-" ]; then
        jq -nc --arg p "${prompt}" --arg t "${TP}" '{prompt:$p, transcript_path:$t}' \
            | env -u ACS_STICKY_REPEAT HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${hook}" 2>/dev/null \
            | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
    else
        jq -nc --arg p "${prompt}" --arg t "${TP}" '{prompt:$p, transcript_path:$t}' \
            | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT="${mode}" /bin/bash "${hook}" 2>/dev/null \
            | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
    fi
    sync_log
}
proc() { printf '%s\n' "$1" | sed -n 's/^Process: \([^ ]*\) ->.*/\1/p' | head -1; }
rec()  { jq -r "$1" "${H}/records.jsonl" 2>/dev/null | tail -1; }            # a field of the LAST record
recs() { jq -r "$1" "${H}/records.jsonl" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
# snap : every routing state file the hook wrote (the whole `.skill-*` family), name and
# checksum, timestamp normalised. The registry cache is an input. The rule's own two files
# are named `.sticky-repeat-*` precisely so that this family needs no exception.
snap() {
    ( cd "${H}/.claude" && ls -A | grep -E '^\.skill-' | grep -v -E '^\.skill-registry-cache\.json$' | LC_ALL=C sort \
        | while IFS= read -r _sf; do
            printf '%s %s\n' "${_sf}" "$(sed -e 's/"updated_at": *"[^"]*"/"updated_at":"T"/' -e "s|${H}|HOME|g" "${_sf}" | cksum)"
          done )
}

ARM="build a new exporter for the report module"    # selects brainstorming by its own words; arms a chain

# --- C: the behaviour the rule is about exists --------------------------------------
echo "== C: controls =="
new_session
c1="$(turn off "${ARM}")"
assert_equals "C1: the arming prompt is mandated brainstorming by its own words" "brainstorming" "$(proc "${c1}")"
c2="$(turn off "go")"
assert_equals "C2: a bare 'go' then gets the chain's step again (sticky composition)" "brainstorming" "$(proc "${c2}")"
[ "${#c2}" -gt 1000 ] && _record_pass "C2: and that block is large (${#c2} characters)" \
    || _record_fail "C2: and that block is large" "only ${#c2} characters"
[ ! -e "${LOGD}" ] && [ ! -e "${MARK}" ] && _record_pass "C3: off writes neither the record nor the marker" \
    || _record_fail "C3: off writes neither the record nor the marker" "found $(ls -A "${H}/.claude" | tr '\n' ' ')"
new_session
assert_equals "C4: in a session with no chain, the same 'go' gets nothing" "" "$(turn off "go")"

# --- SH: shadow, the default, changes nothing that is displayed -----------------------
echo "== SH: shadow displays exactly what off displays =="
new_session; HO="${H}"; TPO="${TP}"
new_session; HS="${H}"; TPS="${TP}"; LOGS="${LOG}"; MARKS="${MARK}"
_n=0
while IFS= read -r _p; do
    [ -n "${_p}" ] || continue
    _n=$((_n + 1))
    H="${HO}"; TP="${TPO}"; _o="$(turn off "${_p}")"
    H="${HS}"; TP="${TPS}"; _s="$(turn - "${_p}")"
    assert_equals "SH turn ${_n}: default (shadow) display is byte-identical to off" "${_o}" "${_s}"
done <<EOF
${ARM}
go
yes
option 1, go ahead
yes
thanks
EOF
LOG="${LOGS}"; MARK="${MARKS}"; H="${HS}"
assert_equals "SH: one record per mandated block" "6" "$(grep -c . "${LOG}" 2>/dev/null)"
assert_equals "SH: every record says shadow" "shadow" "$(jq -r '.mode' "${LOG}" | sort -u | tr '\n' ' ' | sed 's/ $//')"
assert_equals "SH: every block was displayed" "true" "$(jq -r '.displayed' "${LOG}" | sort -u | tr '\n' ' ' | sed 's/ $//')"
assert_equals "SH: the rule would have hidden turns 2, 4 and 6" "false true false true false true" "$(recs '.would_hide')"
assert_equals "SH: and hid none of them" "false" "$(jq -r '.hidden_by_rule' "${LOG}" | sort -u | tr '\n' ' ' | sed 's/ $//')"
if jq -e . "${LOG}" >/dev/null 2>&1; then _record_pass "SH: every record is valid JSON"; else _record_fail "SH: every record is valid JSON" "jq could not parse the log"; fi
assert_not_contains "SH: the record carries no prompt text" "exporter" "$(cat "${LOG}")"
assert_equals "SH: a mode that is a typo is shadow, not suppression" "brainstorming" \
    "$(new_session; turn off "${ARM}" >/dev/null; proc "$(turn supress "go")")"

# --- SU: suppress — what is hidden, and what is not ---------------------------------
echo "== SU: suppress =="
new_session
d1="$(turn suppress "${ARM}")"
assert_equals "SU1: a step's FIRST display is shown" "brainstorming" "$(proc "${d1}")"
d2="$(turn suppress "go")"
assert_equals "SU2: the same step again, on a prompt that asked for nothing, is hidden" "" "${d2}"
assert_equals "SU2: recorded as sticky, already shown, hidden by the rule" "true true true false" \
    "$(rec '[.sticky,.already_shown,.hidden_by_rule,.displayed] | map(tostring) | join(" ")')"
d3="$(turn suppress "yes")"
assert_equals "SU3: when the chain reaches its NEXT step, that step's first display is shown" "writing-plans" "$(proc "${d3}")"
assert_equals "SU3: though it is sticky too" "true false" "$(rec '[.sticky,.already_shown] | map(tostring) | join(" ")')"
assert_equals "SU4: and its repeat is hidden" "" "$(turn suppress "option 1, go ahead")"

new_session; turn suppress "${ARM}" >/dev/null
d5="$(turn suppress "build it")"
assert_equals "SU5: a SHORT prompt whose own words select the already-shown skill is displayed" "brainstorming" "$(proc "${d5}")"
assert_equals "SU5: because it is not sticky" "false true false" "$(rec '[.sticky,.already_shown,.hidden_by_rule] | map(tostring) | join(" ")')"
d6="$(turn suppress "build another new exporter for the billing module as well")"
assert_equals "SU6: so is a long one" "brainstorming" "$(proc "${d6}")"

# A different chain is a different obligation.
new_session; turn suppress "${ARM}" >/dev/null; turn suppress "go" >/dev/null
d7="$(turn suppress "now debug the failing exporter test")"
assert_equals "SU7 setup: a prompt that selects another chain's skill is displayed" "systematic-debugging" "$(proc "${d7}")"
d8="$(turn suppress "ok")"
[ -n "${d8}" ] && _record_pass "SU8: back on the first chain, its step is shown again once ($(proc "${d8}"))" \
    || _record_fail "SU8: back on the first chain, its step is shown again once" "nothing was displayed"
assert_equals "SU8: recorded as a new chain" "true" "$(rec '.new_chain')"

# Compaction: the earlier display may be gone from the model's context.
# The compaction comes straight after the arming prompt, so the bare reply that follows
# asks for the SAME step again (SU2 shows that reply hidden with no compaction). A reply
# one turn later reaches the chain's NEXT step, which is displayed whatever the marker
# says -- an earlier version of these cells did that and passed with the removal deleted.
new_session; turn suppress "${ARM}" >/dev/null
assert_equals "SU9 setup: the marker lists the step just shown" "brainstorming" "$(sed 1d "${MARK}" | tr '\n' ' ' | sed 's/ $//')"
jq -nc --arg t "${TP}" '{transcript_path:$t}' | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${COMPACT}" >/dev/null 2>&1
[ ! -e "${MARK}" ] && _record_pass "SU9: the real compact-recovery hook removes the marker" \
    || _record_fail "SU9: the real compact-recovery hook removes the marker" "it is still there"
_c9="$(turn suppress "go")"
assert_equals "SU9: so the bare reply is shown that same step again" "brainstorming" "$(proc "${_c9}")"
assert_equals "SU9: recorded as sticky and not already shown" "true false" "$(rec '[.sticky,.already_shown] | map(tostring) | join(" ")')"

# AUTO compaction. SessionStart(compact) does not fire for it, so the hook above never runs;
# only PreCompact does. Found in review: with the removal only in compact-recovery-hook.sh
# the marker survived every auto-compaction, which is the common kind. The pre-compact hook
# is run as the existing compaction test runs it: a PATH with no cozempic on it.
new_session; turn suppress "${ARM}" >/dev/null
assert_equals "SU9b setup: the marker lists the step just shown" "brainstorming" "$(sed 1d "${MARK}" | tr '\n' ' ' | sed 's/ $//')"
jq -nc --arg t "${TP}" '{transcript_path:$t, trigger:"auto"}' \
    | env HOME="${H}" PATH="$(isolated_tool_path)" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${PRECOMPACT}" >/dev/null 2>&1
[ ! -e "${MARK}" ] && _record_pass "SU9b: the real pre-compact hook removes the marker (the only hook that fires for auto-compaction)" \
    || _record_fail "SU9b: the real pre-compact hook removes the marker" "it is still there"
_c9b="$(turn suppress "go")"
assert_equals "SU9b: so after an auto-compaction the bare reply is shown that same step again" "brainstorming" "$(proc "${_c9b}")"

# A new task. The user cancels, then orders something else that arms the SAME chain: its
# signature is identical, so only the reset on the user's own words (and on the cancel)
# stops the first task's entries hiding the second task's steps. Found in review.
new_session
turn suppress "${ARM}" >/dev/null; turn suppress "go" >/dev/null
_w1="$(turn suppress "yes")"
assert_equals "SU12 setup: the first task reached its planning step and was shown it" "writing-plans" "$(proc "${_w1}")"
turn suppress "cancel" >/dev/null
[ ! -e "${MARK}" ] && _record_pass "SU12: a cancel forgets what was shown" || _record_fail "SU12: a cancel forgets what was shown" "the marker is still there"
# (The unrelated prompt in between matters: straight after a cancel the next chain inherits
# the cancelled task's recorded progress -- pre-existing walker behaviour, not this rule's --
# and skips its planning step altogether. This is the sequence review reproduced.)
turn suppress "update the readme documentation wording for install section" >/dev/null
turn suppress "build a new importer for the billing module" >/dev/null
turn suppress "go" >/dev/null; turn suppress "yes" >/dev/null
# The planning step must have been DISPLAYED once for each task. Under the defect the second
# task's was hidden and this reads 1.
assert_equals "SU12: the planning step was displayed once for the first task and once for the new one" "2" \
    "$(jq -s '[.[] | select(.skill == "writing-plans" and .displayed == true)] | length' "${H}/records.jsonl")"
assert_equals "SU12: and the new task's first sight of it was not hidden" "true" \
    "$(jq -s '[.[] | select(.skill == "writing-plans")] | (.[1].displayed)' "${H}/records.jsonl")"
# The same, without the cancel: the reset on the user's own words must do it alone.
new_session
turn suppress "${ARM}" >/dev/null; turn suppress "go" >/dev/null; turn suppress "yes" >/dev/null
assert_equals "SU12b setup: the first task's planning step is now a repeat (hidden)" "" "$(turn suppress "option 1, go ahead")"
_b="$(turn suppress "build a new importer for the billing module")"
assert_equals "SU12b: a new order in the user's own words is displayed" "brainstorming" "$(proc "${_b}")"
assert_equals "SU12b: and restarts the list with that step alone" "brainstorming" "$(sed 1d "${MARK}" | tr '\n' ' ' | sed 's/ $//')"

# A block that carries something the prompt DID ask for. A short prompt can select a domain
# skill by its own words and still get the chain's step injected beside it; hiding the block
# would hide the skill the user asked for. Found in review.
new_session
turn off "${ARM}" >/dev/null; turn off "go" >/dev/null; turn off "yes" >/dev/null
_d_off="$(turn off "update the readme documentation wording")"
if printf '%s' "${_d_off}" | grep -q '^ *Domain:' && [ -n "$(proc "${_d_off}")" ]; then
    _record_pass "SU13 precondition: this short prompt selects a domain skill AND gets the chain's step ($(proc "${_d_off}"))"
    new_session
    turn suppress "${ARM}" >/dev/null; turn suppress "go" >/dev/null; turn suppress "yes" >/dev/null
    _d_sup="$(turn suppress "update the readme documentation wording")"
    assert_equals "SU13: the block is displayed, byte for byte as with the rule off" "${_d_off}" "${_d_sup}"
    assert_equals "SU13: recorded as sticky and already shown, but NOT as something the rule would hide" "true true false false" \
        "$(rec '[.sticky,.already_shown,.would_hide,.hidden_by_rule] | map(tostring) | join(" ")')"
    [ "$(rec '.skills_in_block')" -ge 2 ] 2>/dev/null && _record_pass "SU13: and the record says the block held $(rec '.skills_in_block') skills" \
        || _record_fail "SU13: the record says how many skills the block held" "skills_in_block=$(rec '.skills_in_block')"
else
    _record_fail "SU13 precondition: this short prompt selects a domain skill AND gets the chain's step" "the fixture no longer reaches the case"
fi

# The four mode words in any letter case.
new_session; turn OFF "${ARM}" >/dev/null
[ ! -e "${LOGD}" ] && _record_pass "SU14: OFF in capitals is off (no record)" || _record_fail "SU14: OFF in capitals is off" "records were written"
new_session; turn Suppress "${ARM}" >/dev/null
assert_equals "SU14: Suppress in mixed case hides the repeat" "" "$(turn Suppress "go")"

# A missing marker fails toward display.
new_session; turn suppress "${ARM}" >/dev/null; rm -f "${MARK}"
[ -n "$(turn suppress "go")" ] && _record_pass "SU10: with the marker gone, the block is displayed" \
    || _record_fail "SU10: with the marker gone, the block is displayed" "nothing was displayed"

# A block hidden for ANOTHER reason is not remembered as shown.
if [ -s "${FIX}/peer-bare-block.txt" ]; then
    new_session
    assert_equals "SU11 setup: a peer message is hidden by the non-human rule" "" "$(turn suppress "$(cat "${FIX}/peer-bare-block.txt")")"
    if [ -s "${LOG}" ]; then
        assert_equals "SU11: that block is recorded as hidden by another rule, not this one" "true false false" \
            "$(rec '[.other_suppression,.hidden_by_rule,.displayed] | map(tostring) | join(" ")')"
        _skill="$(rec '.skill')"
        if grep -qxF -- "${_skill}" "${MARK}" 2>/dev/null; then
            _record_fail "SU11: and its step is NOT remembered as shown" "${_skill} is in the marker"
        else
            _record_pass "SU11: and its step is NOT remembered as shown"
        fi
    else
        _record_pass "SU11: the peer message carried no process mandate here, so there is nothing to remember"
    fi
else
    _record_fail "SU11: fixture peer-bare-block.txt present" "missing or empty"
fi

# --- F: when the marker is NOT believed -----------------------------------------------
echo "== F: the marker is believed only for its own chain, and only as a plain file =="
# both <mode> <prompt> : like turn, but also captures the hook's stderr in ${H}/err.
both() {
    jq -nc --arg p "$2" --arg t "${TP}" '{prompt:$p, transcript_path:$t}' \
        | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT="$1" /bin/bash "${HOOK}" 2>"${H}/err" \
        | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
    sync_log
}
CHAIN_SIG=""
new_session; turn suppress "${ARM}" >/dev/null
CHAIN_SIG="$(sed -n '1s/^#chain //p' "${MARK}")"
assert_not_empty "F setup: the marker's first line names the chain" "${CHAIN_SIG}"

# F1: the step is listed, but under ANOTHER chain's header.
new_session; turn suppress "${ARM}" >/dev/null
printf '#chain some-other|chain\nbrainstorming\n' > "${MARK}"
[ -n "$(turn suppress "go")" ] && _record_pass "F1: a step listed under another chain's header is displayed" \
    || _record_fail "F1: a step listed under another chain's header is displayed" "it was hidden"

# F2: the chain the hook walks NOW is not the chain the marker was written for. The
# session's state still names the full chain, so sticky composition fires, but the registry
# no longer links the skills, so the walk yields a one-step "chain". The marker lists the
# step under the FULL chain's header and must not be believed.
# (The case review actually named is an EMPTY signature, where the first cut skipped the
# header check altogether. No fixture here reaches an empty signature through the real hook
# -- a process skill's walk yields at least itself -- so that guard is defensive and is
# pinned only by this neighbouring case. Said plainly rather than claimed as covered.)
new_session; turn suppress "${ARM}" >/dev/null
jq '.skills |= map(.precedes = [] | .requires = [])' "${REG}" > "${H}/.claude/.skill-registry-cache.json"
_f2="$(turn suppress "go")"
if [ -s "${LOG}" ] && [ "$(rec '.sticky')" = "true" ] && [ "$(rec '.chain' | tr '>' '|')" != "${CHAIN_SIG}" ]; then
    _record_pass "F2 precondition: sticky fired on a chain signature that is not the marker's ($(rec '.chain'))"
    [ -n "${_f2}" ] && _record_pass "F2: the marker written for the full chain is not believed, and the block is displayed" \
        || _record_fail "F2: the marker written for the full chain is not believed" "the block was hidden"
    assert_equals "F2: recorded as not already shown" "false false" "$(rec '[.already_shown,.hidden_by_rule] | map(tostring) | join(" ")')"
else
    _record_fail "F2 precondition: sticky fired on a different chain signature" "sticky=$(rec '.sticky') chain='$(rec '.chain')' — the fixture no longer reaches the case"
fi

# F3: the marker is a directory.
new_session; turn suppress "${ARM}" >/dev/null; rm -f "${MARK}"; mkdir "${MARK}"
[ -n "$(turn suppress "go")" ] && _record_pass "F3: a marker that is a directory is ignored (displayed)" \
    || _record_fail "F3: a marker that is a directory is ignored (displayed)" "it was hidden"

# F4: the marker is unreadable. Displayed, and in SHADOW the hook's stderr is exactly what
# off's is: `done < file 2>/dev/null` opens the file BEFORE putting stderr away.
new_session; turn off "${ARM}" >/dev/null; both off "go" >/dev/null; _err_off="$(cat "${H}/err")"
new_session; turn shadow "${ARM}" >/dev/null; chmod 000 "${MARK}"
_f4="$(both shadow "go")"; _err_sha="$(cat "${H}/err")"; chmod 600 "${MARK}"
[ -n "${_f4}" ] && _record_pass "F4 setup: shadow displays (as it always does; the stderr comparison below is the cell)" || _record_fail "F4 setup: shadow displays" "nothing was displayed"
assert_equals "F4: and shadow prints nothing to stderr that off does not" "${_err_off}" "${_err_sha}"
new_session; turn suppress "${ARM}" >/dev/null; chmod 000 "${MARK}"
_f4b="$(both suppress "go")"; chmod 600 "${MARK}"
[ -n "${_f4b}" ] && _record_pass "F4: in suppress too, an unreadable marker displays" || _record_fail "F4: in suppress too, an unreadable marker displays" "it was hidden"

# F5: the marker NAME is aliased onto a STATE file -- by a symlink, then by a hard link.
# Nothing is modified in place, so in both cases the state file must come out exactly as
# `off` writes it. A hard link is the case a pathname check cannot see.
new_session; H_REF="${H}"; turn off "${ARM}" >/dev/null; turn off "go" >/dev/null
_ref_state="$(sed 's/"updated_at": *"[^"]*"/"updated_at":"T"/' "${H_REF}/.claude/.skill-composition-state-${TOK}")"
for _kind in symlink hardlink; do
    new_session; turn suppress "${ARM}" >/dev/null
    rm -f "${MARK}"
    if [ "${_kind}" = "symlink" ]; then ln -s "${H}/.claude/.skill-composition-state-${TOK}" "${MARK}"
    else ln "${H}/.claude/.skill-composition-state-${TOK}" "${MARK}"; fi
    [ -n "$(turn suppress "go")" ] && _record_pass "F5 ${_kind}: a marker aliased onto a state file is not believed (displayed)" \
        || _record_fail "F5 ${_kind}: a marker aliased onto a state file is not believed (displayed)" "it was hidden"
    assert_equals "F5 ${_kind}: and that state file is exactly what off wrote (nothing written through the link)" \
        "${_ref_state}" "$(sed 's/"updated_at": *"[^"]*"/"updated_at":"T"/' "${H}/.claude/.skill-composition-state-${TOK}")"
done

# F6: the RECORD directory is a symlink into the state directory itself. Each record is a
# new file created exclusively, so nothing that already exists there can be written into.
new_session; H_REF="${H}"; turn off "${ARM}" >/dev/null; turn off "go" >/dev/null; _ref_snap="$(snap)"
new_session; ln -s "${H}/.claude" "${LOGD}"
turn suppress "${ARM}" >/dev/null; turn suppress "go" >/dev/null
assert_equals "F6: with the record directory aliased onto the state directory, every state file is what off wrote" "${_ref_snap}" "$(snap)"
[ "$(ls "${H}/.claude" | grep -c '\.json$')" -ge 2 ] && _record_pass "F6: and the records were created as new files beside them" \
    || _record_fail "F6: and the records were created as new files" "found $(ls -A "${H}/.claude" | tr '\n' ' ')"

# F6b: a FIFO where the marker should be. The plain-file check ignores it; and if that
# check is bypassed (a FIFO swapped in after it -- the race review named), the open must
# still not block: the state writes come after it. MUTF is the hook without that check.
MUTF="${TEST_TMPDIR}/no-plain-file-check-hook.sh"
sed 's/ \&\& \[\[ -f "\${_sr_file}" \]\] \&\& \[\[ ! -L "\${_sr_file}" \]\]; then$/; then/' "${HOOK}" > "${MUTF}"
new_session; turn suppress "${ARM}" >/dev/null; rm -f "${MARK}"; mkfifo "${MARK}"
[ -n "$(turn suppress "go")" ] && _record_pass "F6b: a FIFO marker is ignored (displayed)" || _record_fail "F6b: a FIFO marker is ignored (displayed)" "it was hidden"
if cmp -s "${HOOK}" "${MUTF}"; then
    _record_fail "F6b: the no-plain-file-check mutation applies" "sed changed nothing"
else
    new_session; turn suppress "${ARM}" >/dev/null; rm -f "${MARK}"; mkfifo "${MARK}"
    _t0="${SECONDS}"
    ( jq -nc --arg p "go" --arg t "${TP}" '{prompt:$p, transcript_path:$t}' \
        | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT=suppress /bin/bash "${MUTF}" > "${H}/out" 2>/dev/null ) &
    _pid=$!; _w=0
    while kill -0 "${_pid}" 2>/dev/null && [ "${_w}" -lt 100 ]; do sleep 0.1; _w=$((_w + 1)); done
    if kill -0 "${_pid}" 2>/dev/null; then
        kill "${_pid}" 2>/dev/null; _record_fail "F6b: with the check bypassed, opening a FIFO does not block the hook" "still running after 10s"
    else
        _record_pass "F6b: with the check bypassed, opening a FIFO does not block the hook (finished in $((SECONDS - _t0))s)"
    fi
    # The walker's own progress is in .assumed now (.completed is real Skill returns only),
    # so that is the list that shows this turn's state write happened.
    assert_equals "F6b: and the state the gate reads was still written" "true" \
        "$(jq -r '(.assumed | length) >= 1' "${H}/.claude/.skill-composition-state-${TOK}" 2>/dev/null)"
fi

# F7: the read is bounded at 64 lines. The step IS listed, at line 72: it is not believed.
# (Seventy fillers, not thousands: a very long file is also stopped by the two-second
# budget, and then this cell cannot tell which bound did the work -- found by mutation,
# when the fixture had 5,000 lines and passed with the line bound removed.)
new_session; turn suppress "${ARM}" >/dev/null
{ printf '#chain %s\n' "${CHAIN_SIG}"; i=0; while [ "${i}" -lt 70 ]; do printf 'filler-%s\n' "${i}"; i=$((i + 1)); done; printf 'brainstorming\n'; } > "${MARK}"
[ -n "$(turn suppress "go")" ] && _record_pass "F7: an entry beyond the read bound is not believed (displayed)" \
    || _record_fail "F7: an entry beyond the read bound is not believed (displayed)" "it was hidden"
# F7b: `read -n 1025` returns chunks. A physical line of exactly 1025 filler characters
# followed by the step's name comes back as two reads, the second of which IS the name.
# Not believed. (The filler must be 1025, the chunk size: with 1024 the name is split
# across the boundary and the cell passes with the protection deleted -- found by mutation.)
new_session; turn suppress "${ARM}" >/dev/null
{ printf '#chain %s\n' "${CHAIN_SIG}"; printf '%01025d' 0; printf 'brainstorming\n'; } > "${MARK}"
[ -n "$(turn suppress "go")" ] && _record_pass "F7b: a step name that is only the tail of an over-long line is not believed (displayed)" \
    || _record_fail "F7b: a step name that is only the tail of an over-long line is not believed" "it was hidden"
# ...and the control: the same entry inside the bound IS believed, so F1-F7 are not passing
# because the rule never hides anything.
new_session; turn suppress "${ARM}" >/dev/null
printf '#chain %s\nfiller\nbrainstorming\n' "${CHAIN_SIG}" > "${MARK}"
assert_equals "F control: the same entry under the right header and inside the bound IS believed (hidden)" "" "$(turn suppress "go")"

# F8: a corrupt prompt counter does not break the record. What holds this is the hook's
# OWN pre-existing check on the counter file; the record's separate number check is
# defensive and no input reaches it (said plainly: removing it leaves this file green).
new_session; turn shadow "${ARM}" >/dev/null
printf 'not-a-number' > "${H}/.claude/.skill-prompt-count-${TOK}"
turn shadow "go" >/dev/null
if tail -1 "${LOG}" | jq -e '(.prompt_count | type) == "number"' >/dev/null 2>&1; then
    _record_pass "F8: with a corrupt prompt counter the record is still valid JSON with a numeric count"
else
    _record_fail "F8: with a corrupt prompt counter the record is still valid JSON" "$(tail -1 "${LOG}" | head -c 200)"
fi

# F9: ~/.claude is not writable, so a compaction could not have removed the marker. It is
# not believed. (Root ignores directory permissions, so the cell is announced and skipped.)
if [ "$(id -u)" = "0" ]; then
    echo "  SKIP: F9 (running as root; directory permissions do not bind)"
else
    new_session; turn suppress "${ARM}" >/dev/null
    chmod 555 "${H}/.claude"
    _f9="$(turn suppress "go")"
    chmod 755 "${H}/.claude"
    [ -n "${_f9}" ] && _record_pass "F9: with ~/.claude unwritable the marker is not believed (displayed)" \
        || _record_fail "F9: with ~/.claude unwritable the marker is not believed (displayed)" "it was hidden"
fi

# F10: a marker that is a directory is not written INTO.
new_session; turn suppress "${ARM}" >/dev/null; rm -f "${MARK}"; mkdir "${MARK}"
turn suppress "go" >/dev/null
assert_equals "F10: nothing is created inside a marker that is a directory" "" "$(ls -A "${MARK}")"

# F11: a line that is not a step name is not carried into the rewritten marker.
new_session; turn suppress "${ARM}" >/dev/null
printf '#chain %s\nbrainstorming\nnot a step name; rm -rf\n' "${CHAIN_SIG}" > "${MARK}"
turn suppress "go" >/dev/null                       # hidden: brainstorming is believed
_n="$(turn suppress "yes")"                         # the next step is shown and the marker rewritten
assert_equals "F11 setup: the next step was displayed, so the marker was rewritten" "writing-plans" "$(proc "${_n}")"
assert_equals "F11: the rewritten marker holds step names only" "brainstorming writing-plans" "$(sed 1d "${MARK}" | tr '\n' ' ' | sed 's/ $//')"

# F12: the read has a time budget. A FIFO behind a bypassed check, fed its header and then
# one line every half second, must not hold the hook near its ten-second kill (hooks.json):
# measured in review at 14 s before the budget existed.
if cmp -s "${HOOK}" "${MUTF}"; then
    _record_fail "F12: the no-plain-file-check mutation applies" "sed changed nothing"
else
    new_session; turn suppress "${ARM}" >/dev/null; rm -f "${MARK}"; mkfifo "${MARK}"
    ( { printf '#chain %s\n' "${CHAIN_SIG}"; _i=0; while [ "${_i}" -lt 40 ]; do printf 'filler-%s\n' "${_i}"; sleep 0.5; _i=$((_i + 1)); done; } > "${MARK}" 2>/dev/null ) &
    _feeder=$!
    _t0="${SECONDS}"
    jq -nc --arg p "go" --arg t "${TP}" '{prompt:$p, transcript_path:$t}' \
        | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" ACS_STICKY_REPEAT=shadow /bin/bash "${MUTF}" >/dev/null 2>&1
    _took=$((SECONDS - _t0))
    kill "${_feeder}" 2>/dev/null; wait "${_feeder}" 2>/dev/null
    [ "${_took}" -le 6 ] && _record_pass "F12: a slowly fed FIFO holds the hook ${_took}s, well inside its ten-second limit" \
        || _record_fail "F12: a slowly fed FIFO does not hold the hook near its ten-second limit" "it took ${_took}s"
fi

# --- TR: the trial arm is fixed by the session ---------------------------------------
echo "== TR: trial =="
new_session sess0; turn trial "${ARM}" >/dev/null
[ -n "$(turn trial "go")" ] && _record_pass "TR1: a session whose token ends in 0 is in the show arm" \
    || _record_fail "TR1: a session whose token ends in 0 is in the show arm" "the repeat was hidden"
assert_equals "TR1: recorded with its arm, and as a block the rule would hide" "show true false" \
    "$(rec '[.arm,.would_hide,.hidden_by_rule] | map(tostring) | join(" ")')"
new_session sessf; turn trial "${ARM}" >/dev/null
assert_equals "TR2: a session whose token ends in f is in the hide arm" "" "$(turn trial "go")"
assert_equals "TR2: recorded" "hide true true" "$(rec '[.arm,.would_hide,.hidden_by_rule] | map(tostring) | join(" ")')"
_hide=0; _show=0
for _c in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
    new_session "x${_c}"; turn trial "${ARM}" >/dev/null
    if [ -z "$(turn trial "go")" ]; then _hide=$((_hide + 1)); else _show=$((_show + 1)); fi
done
assert_equals "TR3: the sixteen hex digits split eight and eight" "8 8" "${_hide} ${_show}"

# --- ID: display-only ---------------------------------------------------------------
# Same prompts, turn by turn, in separate homes. Every pre-existing state file must be
# identical to `off` in every mode. `moved` proves the state CHANGES on the hidden turns,
# so "identical" is not "nothing happened".
echo "== ID: every pre-existing state file is identical to off, turn by turn =="
MUT="${TEST_TMPDIR}/exit-early-hook.sh"
sed 's/^        suppress) _sr_hide_now=1 ;;$/        suppress) exit 0 ;;/' "${HOOK}" > "${MUT}"
new_session;       H_OFF="${H}"; TP_OFF="${TP}"
new_session;       H_SUP="${H}"; TP_SUP="${TP}"
new_session;       H_SHA="${H}"; TP_SHA="${TP}"
new_session sessf; H_TRI="${H}"; TP_TRI="${TP}"
new_session;       H_MUT="${H}"; TP_MUT="${TP}"
_n=0; _moved=0; _mut_diff=0; _prev=""
while IFS= read -r _p; do
    [ -n "${_p}" ] || continue
    _n=$((_n + 1))
    H="${H_OFF}"; TP="${TP_OFF}"; turn off "${_p}" >/dev/null;            _s_off="$(snap)"
    H="${H_SUP}"; TP="${TP_SUP}"; _d_sup="$(turn suppress "${_p}")";      _s_sup="$(snap)"
    H="${H_SHA}"; TP="${TP_SHA}"; turn shadow "${_p}" >/dev/null;         _s_sha="$(snap)"
    H="${H_TRI}"; TP="${TP_TRI}"; turn trial "${_p}" >/dev/null;          _s_tri="$(snap | sed 's/session-sessf/session-sess0/g')"
    H="${H_MUT}"; TP="${TP_MUT}"; turn suppress "${_p}" "${MUT}" >/dev/null; _s_mut="$(snap)"
    assert_equals "ID turn ${_n}: suppress writes the state off writes" "${_s_off}" "${_s_sup}"
    assert_equals "ID turn ${_n}: shadow writes the state off writes" "${_s_off}" "${_s_sha}"
    # The trial home has a different token, so file NAMES differ; contents are compared by
    # renaming. Checksums of files that embed nothing session-specific must match.
    assert_equals "ID turn ${_n}: trial (hide arm) writes the state off writes" \
        "$(printf '%s\n' "${_s_off}" | grep -v 'session-token')" "$(printf '%s\n' "${_s_tri}" | grep -v 'session-token')"
    # The prompt counter changes on every turn, so the whole snapshot always "moves". The
    # control is on the composition-state line alone: that is the file the gate reads.
    _c_off="$(printf '%s\n' "${_s_off}" | grep 'composition-state')"
    if [ -z "${_d_sup}" ] && [ "${_c_off}" != "${_prev}" ]; then _moved=$((_moved + 1)); fi
    [ "${_s_mut}" != "${_s_off}" ] && _mut_diff=$((_mut_diff + 1))
    _prev="${_c_off}"
done <<EOF
${ARM}
go
yes
option 1, go ahead
yes
thanks
EOF
[ "${_moved}" -ge 1 ] && _record_pass "ID control: the composition state itself moved on ${_moved} of the turns suppress hid" \
    || _record_fail "ID control: the composition state moved on a turn suppress hid" "it never did, so identity was not exercised where it matters"
if cmp -s "${HOOK}" "${MUT}"; then
    _record_fail "X1: the exit-early mutation applies" "sed changed nothing"
else
    [ "${_mut_diff}" -ge 1 ] && _record_pass "X1: an exit-early version of the rule writes DIFFERENT state on ${_mut_diff} turns (so the comparison can fail)" \
        || _record_fail "X1: an exit-early version of the rule writes different state" "it matched off on every turn: the identity cells above prove nothing"
fi

# --- AU: the record against what was actually displayed ------------------------------
echo "== AU: each record agrees with the display of its own turn =="
new_session
_n=0
while IFS= read -r _p; do
    [ -n "${_p}" ] || continue
    _n=$((_n + 1))
    _d="$(turn suppress "${_p}")"
    _shown="false"; [ -n "${_d}" ] && _shown="true"
    assert_equals "AU turn ${_n}: .displayed is what happened" "${_shown}" "$(rec '.displayed')"
    if [ -n "${_d}" ]; then
        assert_equals "AU turn ${_n}: .skill is the block's process skill" "$(proc "${_d}")" "$(rec '.skill')"
        assert_equals "AU turn ${_n}: .block_chars is the block's length" "${#_d}" "$(rec '.block_chars')"
    fi
done <<EOF
${ARM}
go
yes
option 1, go ahead
now debug the failing exporter test
ok
EOF
assert_equals "AU: one record per turn, numbered by the hook's own prompt counter" "1 2 3 4 5 6" "$(recs '.prompt_count')"

cd "${PROJECT_ROOT}" || true
teardown_test_env
print_summary

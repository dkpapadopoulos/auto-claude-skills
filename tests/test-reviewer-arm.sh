#!/usr/bin/env bash
# test-reviewer-arm.sh — the reviewer classifier's matching ARM (allowlisted
# subagent_type vs description word) travels from dispatch, through the pairing
# record, into the branch ledger's `reviewer-returned` milestone, and the lib
# functions the guard will use read it back.
#
# Spec: openspec/changes/review-credit-from-evidence/design.md decision 3.
# Binding ruling F3: completion-time HEAD is NEVER substituted for a missing
# dispatch sha — the milestone records `-` and never credits.
#
# Both hooks are driven as the REAL scripts with payload shapes copied from
# tests/test-reviewer-completion-hook.sh (captured live from CLI 2.1.236), in
# throwaway repos that each carry their own `origin` remote, so the ledger key
# is the remote-URL key production uses. Cells are flat, not functions, so no
# cell can be defined and never run.
# Bash 3.2.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-reviewer-arm.sh ==="

HOOK="${PROJECT_ROOT}/hooks/reviewer-completion-hook.sh"
DISPATCH_HOOK="${PROJECT_ROOT}/hooks/reviewer-evidence-hook.sh"
setup_test_env

# Physical path: the hooks key on `git rev-parse --show-toplevel`, which
# resolves symlinks (macOS TMPDIR is under /var -> /private/var). $1=unborn
# leaves the repo with no commit (HEAD unresolvable, branch still named).
# mktemp, not a counter: this runs inside `$( )`, where a counter increment is
# lost and every call would re-init the SAME repo (the first draft did).
_mkrepo() {
    local d
    d="$(mktemp -d "${TEST_TMPDIR}/repo.XXXXXX")"; d="$(cd "$d" && pwd -P)"
    ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git remote add origin "https://example.invalid/$(basename "$d").git" ) >/dev/null 2>&1
    if [ "${1:-}" != "unborn" ]; then
        ( cd "$d" && git commit -q --allow-empty -m init ) >/dev/null 2>&1
    fi
    printf '%s' "$d"
}
_REPO="$(_mkrepo)"
_SID="0f5b1a2c-aaaa-4222-8333-444455556666"

_completion_payload() {
    jq -n --arg ai "$1" --arg lm "$2" --arg sid "$3" \
      '{hook_event_name:"SubagentStop", session_id:$sid, agent_id:$ai, agent_type:"general-purpose",
        agent_transcript_path:"/nonexistent/agent.jsonl",
        transcript_path:"/nonexistent/parent.jsonl",
        last_assistant_message:$lm, stop_hook_active:false}'
}
_dispatch_payload() {
    jq -n --arg ai "$1" --arg d "$2" --arg sid "$3" --arg st "${4:-general-purpose}" \
      '{tool_name:"Agent", session_id:$sid,
        tool_response:{is_error:false, agentId:$ai, status:"completed"},
        tool_input:{subagent_type:$st, description:$d}}'
}
_run_completion() {  # agent_id msg ; repo in _CWD
    _completion_payload "$1" "$2" "$_SID" \
        | ( cd "${_CWD}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${HOOK}" ) >/dev/null 2>&1
}
_run_dispatch() {    # agent_id description [subagent_type]
    _dispatch_payload "$1" "$2" "$_SID" "${3:-general-purpose}" \
        | ( cd "${_CWD}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${DISPATCH_HOOK}" ) >/dev/null 2>&1
}
_dispatch_file() { printf '%s' "${HOME}/.claude/.skill-reviewer-dispatch-session-${_SID}"; }
_reset() {
    rm -rf "$HOME"/.claude/.skill-branch-ledger-*
    rm -f "$HOME"/.claude/.skill-reviewer-dispatch-* "$HOME"/.claude/.skill-reviewer-complete-* "$HOME"/.claude/.skill-reviewer-saturated-*
    _CWD="$_REPO"
}
_head() { git -C "${1:-$_REPO}" rev-parse HEAD 2>/dev/null; }
_commit() {  # repo [file]
    if [ -n "${2:-}" ]; then
        mkdir -p "$(dirname "$1/$2")"; printf 'x%s\n' "$RANDOM" >> "$1/$2"
        git -C "$1" add -- "$2" >/dev/null 2>&1
        git -C "$1" commit -q -m "touch $2" >/dev/null 2>&1
    else
        git -C "$1" commit -q --allow-empty -m "later" >/dev/null 2>&1
    fi
}

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh"
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/credited-skills.sh"

_tag()  { branch_ledger_tag "reviewer-returned" "${1:-$_REPO}" 2>/dev/null; }
_lsha() { branch_ledger_sha "reviewer-returned" "${1:-$_REPO}" 2>/dev/null; }
_has()  { branch_ledger_has "reviewer-returned" "${1:-$_REPO}"; }

# ===========================================================================
# A1/A2 the allowlisted arm, BOTH firing orders
# ===========================================================================
# A commit lands between dispatch and completion, so "dispatch HEAD" and
# "completion HEAD" differ and the sha assertion can tell them apart.
_reset
_D1="$(_head)"
_run_dispatch "a1-bg" "Task 4: add the parser" "pr-review-toolkit:code-reviewer"
_commit "$_REPO"
_run_completion "a1-bg" "Findings: 0"
assert_equals "A1 background order: tag is arm=allowlist" "arm=allowlist" "$(_tag)"
if [ "$_D1" = "$(_head)" ]; then
    _record_fail "A1 background order: sha is the dispatch HEAD" "harness did not move HEAD — cell proves nothing"
else
    assert_equals "A1 background order: sha is the dispatch HEAD" "$_D1" "$(_lsha)"
fi

_reset
_run_completion "a2-fg" "Findings: 0"
_D2="$(_head)"
_run_dispatch "a2-fg" "Task 4: add the parser" "pr-review-toolkit:code-reviewer"
assert_equals "A2 foreground order: tag is arm=allowlist" "arm=allowlist" "$(_tag)"
assert_equals "A2 foreground order: sha is the dispatch HEAD" "$_D2" "$(_lsha)"

# ===========================================================================
# A3 the description arm, both orders
# ===========================================================================
_reset
_run_dispatch "a3-bg" "Task 1 review: spec"
_run_completion "a3-bg" "Findings: 1"
assert_equals "A3 description arm, background order: tag" "arm=description" "$(_tag)"

_reset
_run_completion "a3-fg" "Findings: 1"
_run_dispatch "a3-fg" "Task 1 review: spec"
assert_equals "A3 description arm, foreground order: tag" "arm=description" "$(_tag)"

# A3b the dispatch record itself carries the arm (the pairing half of the trip)
_reset
_run_dispatch "a3-rec" "Task 1 review: spec"
assert_equals "A3b dispatch record carries arm=description" "description" \
    "$(reviewer_pairing_dispatch_arm "$_SID" "a3-rec")"
_run_dispatch "a3-rec2" "Task 4: add the parser" "feature-dev:code-reviewer"
assert_equals "A3b dispatch record carries arm=allowlist" "allowlist" \
    "$(reviewer_pairing_dispatch_arm "$_SID" "a3-rec2")"

# ===========================================================================
# A4 legacy three-field dispatch line: milestone, but no arm and no credit
# ===========================================================================
_reset
_KEY="$(cd "$_REPO" && branch_ledger_key)"
printf '%s %s %s\n' "a4-old" "$_KEY" "$(_head)" > "$(_dispatch_file)"
_run_completion "a4-old" "Findings: 0"
if _has; then _record_pass "A4 legacy line: milestone still recorded"
else _record_fail "A4 legacy line: milestone still recorded" "no reviewer-returned"; fi
assert_equals "A4 legacy line: tag is empty" "" "$(_tag)"
review_reviewer_returned_sha "$_REPO" >/dev/null 2>&1
assert_equals "A4 legacy line: review_reviewer_returned_sha returns 1" "1" "$?"
assert_equals "A4 legacy line: reviewer_pairing_dispatch_arm prints nothing" "" \
    "$(reviewer_pairing_dispatch_arm "$_SID" "a4-old" 2>/dev/null)"

# A4b POSITIVE CONTROL: the identical planted line PLUS an allowlist arm DOES
# credit through the same harness, so A4's refusal is the missing arm alone.
_reset
printf '%s %s %s %s\n' "a4-new" "$_KEY" "$(_head)" "allowlist" > "$(_dispatch_file)"
_run_completion "a4-new" "Findings: 0"
_A4B="$(review_reviewer_returned_sha "$_REPO" 2>/dev/null)"; _A4RC=$?
assert_equals "A4b control: same line with arm credits (rc)" "0" "$_A4RC"
assert_equals "A4b control: same line with arm credits (sha)" "$(_head)" "$_A4B"

# ===========================================================================
# A5 reviewer-ran is unchanged: exactly `<sha> <ts>`
# ===========================================================================
_reset
_run_dispatch "a5" "Task 4: add the parser" "pr-review-toolkit:code-reviewer"
_RAN_FILE="$(branch_ledger_dir "$_REPO")/reviewer-ran"
_RAN="$(cat "$_RAN_FILE" 2>/dev/null)"
if printf '%s\n' "$_RAN" | grep -Eq '^[0-9a-f]{40} [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'; then
    _record_pass "A5 reviewer-ran is exactly two fields"
else
    _record_fail "A5 reviewer-ran is exactly two fields" "content: '${_RAN}'"
fi

# ===========================================================================
# A6 review_reviewer_returned_sha
# ===========================================================================
_reset
_H="$(_head)"
( cd "$_REPO" && branch_ledger_record "reviewer-returned" "" "$_H" "arm=allowlist" )
_OUT="$(review_reviewer_returned_sha "$_REPO" 2>/dev/null)"; _RC=$?
assert_equals "A6 allowlist => 0" "0" "$_RC"
assert_equals "A6 allowlist => prints the sha" "$_H" "$_OUT"

( cd "$_REPO" && branch_ledger_record "reviewer-returned" "" "$_H" "arm=description" )
_OUT="$(review_reviewer_returned_sha "$_REPO" 2>/dev/null)"; _RC=$?
assert_equals "A6 description => 1" "1" "$_RC"
assert_equals "A6 description => prints nothing" "" "$_OUT"

( cd "$_REPO" && branch_ledger_record "reviewer-returned" "" "not-hex" "arm=allowlist" )
assert_equals "A6 control: a corrupt sha is stored as unknown" "unknown" "$(_lsha)"
review_reviewer_returned_sha "$_REPO" >/dev/null 2>&1
assert_equals "A6 allowlist with sha unknown => 1" "1" "$?"

( cd "$_REPO" && branch_ledger_record "reviewer-returned" "" "-" "arm=allowlist" )
assert_equals "A6 control: an absent dispatch sha is stored as -" "-" "$(_lsha)"
review_reviewer_returned_sha "$_REPO" >/dev/null 2>&1
assert_equals "A6 allowlist with sha - => 1" "1" "$?"

_reset
review_reviewer_returned_sha "$_REPO" >/dev/null 2>&1
assert_equals "A6 no milestone => 1" "1" "$?"

( cd "$_REPO" && branch_ledger_record "reviewer-returned" "" "$_H" "arm=allowlist" )
( unset -f branch_ledger_tag; review_reviewer_returned_sha "$_REPO" ) >/dev/null 2>&1
assert_equals "A6 branch_ledger_tag undefined => 1" "1" "$?"
( unset -f branch_ledger_sha; review_reviewer_returned_sha "$_REPO" ) >/dev/null 2>&1
assert_equals "A6 branch_ledger_sha undefined => 1" "1" "$?"
review_reviewer_returned_sha "" >/dev/null 2>&1
assert_equals "A6 empty ledger root => 1" "1" "$?"

# ===========================================================================
# A7 review_reviewer_covers
# ===========================================================================
_R7="$(_mkrepo)"
_reset
_S0="$(_head "$_R7")"
( cd "$_R7" && branch_ledger_record "reviewer-returned" "" "$_S0" "arm=allowlist" )
_OUT="$(review_reviewer_covers "$_R7" "$_R7" HEAD 2>/dev/null)"; _RC=$?
assert_equals "A7 reviewer at HEAD covers (rc)" "0" "$_RC"
assert_equals "A7 reviewer at HEAD covers (prints sha)" "$_S0" "$_OUT"

_commit "$_R7" "docs/x.md"
review_reviewer_covers "$_R7" "$_R7" HEAD >/dev/null 2>&1
assert_equals "A7 later docs/x.md-only commit still covered" "0" "$?"

_commit "$_R7" "src.sh"
_OUT="$(review_reviewer_covers "$_R7" "$_R7" HEAD 2>/dev/null)"; _RC=$?
assert_equals "A7 later src.sh commit is not covered (rc)" "1" "$_RC"
assert_equals "A7 later src.sh commit prints nothing" "" "$_OUT"

# The same covering sha under the description arm never covers.
_S1="$(_head "$_R7")"
( cd "$_R7" && branch_ledger_record "reviewer-returned" "" "$_S1" "arm=description" )
review_reviewer_covers "$_R7" "$_R7" HEAD >/dev/null 2>&1
assert_equals "A7 description arm at HEAD does not cover" "1" "$?"

# ===========================================================================
# A8 empty dispatch sha (F3): `-` with its arm, never completion-time HEAD
# ===========================================================================
# An unborn branch has a ledger key (origin URL + branch name) but no HEAD, so
# the dispatch hook's `git rev-parse HEAD` comes back empty through the REAL
# hook. The commit before completion makes HEAD resolvable at completion time —
# the exact value F3 forbids stamping.
_R8="$(_mkrepo unborn)"
_reset; _CWD="$_R8"
_K8="$(cd "$_R8" && branch_ledger_key)"
_run_dispatch "a8-bg" "Task 4: add the parser" "pr-review-toolkit:code-reviewer"
assert_equals "A8 dispatch line is '<aid> <key> - allowlist'" "a8-bg ${_K8} - allowlist" \
    "$(grep '^a8-bg ' "$(_dispatch_file)" 2>/dev/null)"
reviewer_pairing_dispatch_sha "$_SID" "a8-bg" >/dev/null 2>&1
assert_equals "A8 reviewer_pairing_dispatch_sha returns 1 for -" "1" "$?"
assert_equals "A8 reviewer_pairing_dispatch_sha prints nothing for -" "" \
    "$(reviewer_pairing_dispatch_sha "$_SID" "a8-bg" 2>/dev/null)"
_commit "$_R8"
_H8="$(_head "$_R8")"
_run_completion "a8-bg" "Findings: 0"
if [ -z "$_H8" ]; then
    _record_fail "A8 completion records - (not HEAD)" "harness has no HEAD at completion — cell proves nothing"
else
    assert_equals "A8 completion records - (not completion HEAD ${_H8})" "-" "$(_lsha "$_R8")"
fi
assert_equals "A8 completion keeps arm=allowlist" "arm=allowlist" "$(_tag "$_R8")"
review_reviewer_returned_sha "$_R8" >/dev/null 2>&1
assert_equals "A8 a - sha never credits" "1" "$?"
review_reviewer_covers "$_R8" "$_R8" HEAD >/dev/null 2>&1
assert_equals "A8 a - sha never covers" "1" "$?"

# A8b foreground order in an unborn repo: the dispatch hook's own credit path.
_R8B="$(_mkrepo unborn)"
_reset; _CWD="$_R8B"
_run_completion "a8-fg" "Findings: 0"
_run_dispatch "a8-fg" "Task 4: add the parser" "pr-review-toolkit:code-reviewer"
assert_equals "A8b foreground: milestone sha is -" "-" "$(_lsha "$_R8B")"
assert_equals "A8b foreground: tag is arm=allowlist" "arm=allowlist" "$(_tag "$_R8B")"

# A8c a legacy TWO-field dispatch line (no sha, no arm) also records `-`:
# F3 forbids the HEAD substitution outright, not only when an arm is present.
_reset
printf '%s %s\n' "a8-old" "$_KEY" > "$(_dispatch_file)"
_run_completion "a8-old" "Findings: 0"
assert_equals "A8c legacy two-field line records -, not HEAD" "-" "$(_lsha)"
assert_equals "A8c legacy two-field line has no tag" "" "$(_tag)"

# ===========================================================================
# A9 branch_ledger_record tag validation and byte-identity
# ===========================================================================
_reset
( cd "$_REPO" && branch_ledger_record m9 "" "" "bad tag;x" )
_C9="$(cat "$(branch_ledger_dir "$_REPO")/m9" 2>/dev/null)"
assert_equals "A9 an invalid tag is dropped: two fields" "2" "$(printf '%s\n' "$_C9" | awk '{print NF}')"
assert_equals "A9 an invalid tag is not written" "" "$(printf '%s' "$_C9" | grep -F 'bad')"
( cd "$_REPO" && branch_ledger_record m9b "" "" "arm=allowlist" )
_C9B="$(cat "$(branch_ledger_dir "$_REPO")/m9b" 2>/dev/null)"
assert_equals "A9 control: a valid tag is the third field" "arm=allowlist" "$(printf '%s\n' "$_C9B" | awk '{print $3}')"
( cd "$_REPO" && branch_ledger_record m9c )
_C9C="$(cat "$(branch_ledger_dir "$_REPO")/m9c" 2>/dev/null)"
if printf '%s\n' "$_C9C" | grep -Eq '^[0-9a-f]{40} [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'; then
    _record_pass "A9 omitted tag is today's two-field line"
else
    _record_fail "A9 omitted tag is today's two-field line" "content: '${_C9C}'"
fi
( cd "$_REPO" && branch_ledger_record m9d "" "" "a/b" )
assert_equals "A9 a slash-bearing tag is dropped" "" "$(branch_ledger_tag m9d "$_REPO")"
assert_equals "A9 branch_ledger_tag of an untagged milestone is empty" "" "$(branch_ledger_tag m9c "$_REPO")"
assert_equals "A9 branch_ledger_tag of a missing milestone is empty" "" "$(branch_ledger_tag nosuch "$_REPO")"
# A four-field file is malformed, not a tag.
printf '%s %s %s %s\n' "$(_head)" "2026-01-01T00:00:00Z" "arm=allowlist" "extra" > "$(branch_ledger_dir "$_REPO")/m9e"
assert_equals "A9 a four-field line yields no tag" "" "$(branch_ledger_tag m9e "$_REPO")"

# ===========================================================================
# A10 note_dispatch arm argument: omitted / invalid => today's line
# ===========================================================================
_reset
reviewer_pairing_note_dispatch "$_SID" "a10-a" "$_KEY" "$(_head)"
reviewer_pairing_note_dispatch "$_SID" "a10-b" "$_KEY" "$(_head)" "bogus"
reviewer_pairing_note_dispatch "$_SID" "a10-c" "$_KEY" "" "description"
assert_equals "A10 omitted arm => today's three-field line" "a10-a ${_KEY} $(_head)" "$(grep '^a10-a ' "$(_dispatch_file)")"
assert_equals "A10 invalid arm => today's three-field line" "a10-b ${_KEY} $(_head)" "$(grep '^a10-b ' "$(_dispatch_file)")"
assert_equals "A10 empty sha with arm => '-' placeholder" "a10-c ${_KEY} - description" "$(grep '^a10-c ' "$(_dispatch_file)")"
printf '%s %s %s %s\n' "a10-d" "$_KEY" "$(_head)" "allowlist;x" >> "$(_dispatch_file)"
reviewer_pairing_dispatch_arm "$_SID" "a10-d" >/dev/null 2>&1
assert_equals "A10 reader rejects an arm outside the vocabulary" "1" "$?"

# ===========================================================================
# A11 structural pins
# ===========================================================================
_lastfn() { grep -o '^[a-z_][a-z_]*() {' "$1" | tail -1 | sed 's/() {//'; }
assert_equals "A11 reviewer_pairing_note_mismatch is still reviewer-pairing.sh's last definition" \
    "reviewer_pairing_note_mismatch" "$(_lastfn "${PROJECT_ROOT}/hooks/lib/reviewer-pairing.sh")"
assert_equals "A11 review_reviewer_covers is credited-skills.sh's last definition" \
    "review_reviewer_covers" "$(_lastfn "${PROJECT_ROOT}/hooks/lib/credited-skills.sh")"
_OUT="$(bash -u -c ". '${PROJECT_ROOT}/hooks/lib/credited-skills.sh'; review_reviewer_returned_sha; review_reviewer_covers; echo survived" 2>/dev/null </dev/null)"
assert_contains "A11 new credited-skills functions are set -u clean" "survived" "$_OUT"
for _f in hooks/lib/branch-ledger.sh hooks/lib/reviewer-pairing.sh hooks/reviewer-evidence-hook.sh \
          hooks/reviewer-completion-hook.sh hooks/lib/credited-skills.sh; do
    if /bin/bash -n "${PROJECT_ROOT}/${_f}" 2>/dev/null; then _record_pass "A11 /bin/bash -n ${_f}"
    else _record_fail "A11 /bin/bash -n ${_f}" "syntax error"; fi
done

teardown_test_env
print_summary
exit $?

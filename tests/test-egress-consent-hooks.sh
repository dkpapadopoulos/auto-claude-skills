#!/usr/bin/env bash
# test-egress-consent-hooks.sh — the two AskUserQuestion hooks that turn a user's answer
# into a single-use egress receipt.
#
# Payload shapes are taken from a LIVE capture (2026-09-16, temporary hook in
# .claude/settings.local.json), not invented:
#   PreToolUse : tool_input = {questions}; payload carries tool_use_id, transcript_path,
#                agent_id (null on the main thread).
#   PostToolUse: tool_response = {questions, answers, annotations}; answers maps question
#                text -> selected LABEL; annotations[q].preview is the selected option's
#                preview. The harness has also copied answers/annotations into tool_input.
#
# The safety cases here were written before the hooks existed and watched fail.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-egress-consent-hooks.sh ==="

ASK_HOOK="${PROJECT_ROOT}/hooks/egress-consent-ask-hook.sh"
RCPT_HOOK="${PROJECT_ROOT}/hooks/egress-consent-receipt-hook.sh"
assert_file_exists "ask hook exists" "${ASK_HOOK}"
assert_file_exists "receipt hook exists" "${RCPT_HOOK}"

T="$(mktemp -d "${TMPDIR:-/tmp}/egress-hooks.XXXXXX")" || exit 1
trap 'rm -rf "${T}"' EXIT
H="${T}/home"; mkdir -p "${H}/.claude/projects/p"
TP="${H}/.claude/projects/p/conv-A.jsonl"
TOK="session-conv-A"
# A singleton naming ANOTHER conversation: hooks must never use it.
printf 'session-FOREIGN' > "${H}/.claude/.skill-session-token"

_sha() { printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1; }
PKG=$'Question: is this migration safe?\n\nRead-only: do not modify any file.\n```\nALTER TABLE t ADD COLUMN c int;\n```'
D="$(_sha "${PKG}")"
Q="Send this package to Codex (OpenAI)? [egress-consent:${D}]"
L="Approve and send"

# pre <tool_use_id> [jq filter applied to the payload]
pre_payload() {
    jq -nc --arg id "$1" --arg tp "${TP}" --arg q "${Q}" --arg p "${PKG}" --arg l "${L}" '
      {session_id:"conv-A", transcript_path:$tp, cwd:"/x", permission_mode:"auto",
       hook_event_name:"PreToolUse", tool_name:"AskUserQuestion", tool_use_id:$id,
       agent_id:null,
       tool_input:{questions:[{question:$q, header:"Egress", multiSelect:false,
         options:[{label:"Do not send", description:"Nothing leaves this machine"},
                  {label:$l, description:"Send exactly the package shown", preview:$p}]}]}}' \
    | jq -c "${2:-.}"
}
# post <tool_use_id> <selected label> [jq filter]
post_payload() {
    local _ann='{}'
    [ "$2" = "${L}" ] && _ann="$(jq -nc --arg q "${Q}" --arg p "${PKG}" '{($q):{preview:$p}}')"
    pre_payload "$1" | jq -c --arg q "${Q}" --arg sel "$2" --argjson ann "${_ann}" '
      .hook_event_name="PostToolUse"
      | .tool_input.answers={($q):$sel} | .tool_input.annotations=$ann
      | .tool_response={questions:.tool_input.questions, answers:{($q):$sel}, annotations:$ann}' \
    | jq -c "${3:-.}"
}
run_ask()  { printf '%s' "$1" | env ${2:+PATH="$2"} HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${ASK_HOOK}" 2>/dev/null; }
run_rcpt() { printf '%s' "$1" | env ${2:+PATH="$2"} HOME="${H}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${RCPT_HOOK}" 2>/dev/null; }
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "unparseable"; }
ask_file()  { printf '%s/.claude/.skill-egress-ask-%s.%s' "${H}" "${TOK}" "$1"; }
rcpt_count() { find "${H}/.claude" -maxdepth 1 -name ".skill-egress-receipt-${TOK}.${D}.*" ! -name '*.consumed' ! -name '*.revoked' | wc -l | tr -d ' '; }
reset_state() { rm -f "${H}"/.claude/.skill-egress-* 2>/dev/null; }

# A PATH with every tool the hooks use EXCEPT jq (/usr/bin/jq exists on macOS, so a
# plain PATH=/bin:/usr/bin would not remove it).
NOJQ="${T}/nojq"; mkdir -p "${NOJQ}"
for tool in bash sh cat mv rm date basename dirname shasum sha256sum perl sed tr cut \
            mkdir chmod stat find head tail wc env mktemp cmp grep printf ln; do
    src="$(command -v "${tool}" 2>/dev/null)"; [ -n "${src}" ] && [ -x "${src}" ] && ln -sf "${src}" "${NOJQ}/${tool}"
done
WITHJQ="${T}/withjq"; cp -R "${NOJQ}" "${WITHJQ}"; ln -sf "$(command -v jq)" "${WITHJQ}/jq"

echo "-- ask hook: clean ask --"
reset_state
out="$(run_ask "$(pre_payload toolu_clean1)")"
assert_equals "clean marked ask is allowed silently" "" "${out}"
assert_equals "clean ask writes a snapshot" "true" "$([ -f "$(ask_file toolu_clean1)" ] && echo true || echo false)"
assert_equals "snapshot records the marker digest" "${D}" "$(jq -r .digest "$(ask_file toolu_clean1)" 2>/dev/null)"
assert_equals "snapshot records the exact question" "${Q}" "$(jq -r .question "$(ask_file toolu_clean1)" 2>/dev/null)"
assert_equals "snapshot is owner-only" "600" "$(stat -f '%Lp' "$(ask_file toolu_clean1)" 2>/dev/null)"
assert_equals "snapshot is keyed by the PAYLOAD token, not the singleton" "0" \
    "$(find "${H}/.claude" -name '.skill-egress-ask-session-FOREIGN*' | wc -l | tr -d ' ')"

echo "-- ask hook: denials (each must also write NO snapshot) --"
deny_case() { # $1 name $2 id $3 filter $4 expected reason fragment
    reset_state
    local o; o="$(run_ask "$(pre_payload "$2" "$3")")"
    assert_equals "$1: denied" "deny" "$(decision "${o}")"
    assert_contains "$1: reason names the rule" "$4" "${o}"
    assert_equals "$1: no snapshot" "false" "$([ -f "$(ask_file "$2")" ] && echo true || echo false)"
}
deny_case "pre-filled answers"      toolu_d1 ".tool_input.answers={}" "pre-answered"
deny_case "pre-filled annotations"  toolu_d2 ".tool_input.annotations={}" "pre-answered"
deny_case "subagent ask"            toolu_d3 ".agent_id=\"agent-1\"" "subagent"
deny_case "two marked questions"    toolu_d4 ".tool_input.questions += [.tool_input.questions[0] | .question += \" again\"]" "multiple-marked-questions"
deny_case "duplicate question text" toolu_d5 ".tool_input.questions += [{question:\"Other?\",header:\"x\",multiSelect:false,options:[{label:\"a\",description:\"a\"},{label:\"b\",description:\"b\"}]},{question:\"Other?\",header:\"y\",multiSelect:false,options:[{label:\"a\",description:\"a\"},{label:\"b\",description:\"b\"}]}]" "duplicate-question-text"
deny_case "two markers in one question" toolu_d6 ".tool_input.questions[0].question += \" [egress-consent:${D}]\"" "multiple-markers"
deny_case "malformed marker"        toolu_d7 ".tool_input.questions[0].question = \"Send? [egress-consent:ABC]\"" "malformed-marker"
deny_case "multiSelect"             toolu_d8 ".tool_input.questions[0].multiSelect=true" "multiselect"
deny_case "marker inside an option" toolu_d9 ".tool_input.questions[0].options[0].description = \"[egress-consent:${D}]\"" "marker-in-option"
deny_case "two approve labels"      toolu_d10 ".tool_input.questions[0].options[0].label = \"${L}\"" "approve-label-count"
deny_case "approve label missing"   toolu_d11 ".tool_input.questions[0].options[1].label = \"Yes\"" "approve-label-count"
deny_case "approve preview missing" toolu_d12 "del(.tool_input.questions[0].options[1].preview)" "approve-preview-missing"
deny_case "approve is the default (first) option" toolu_d14 ".tool_input.questions[0].options |= reverse" "approve-option-first"
deny_case "preview is not the package" toolu_d13 ".tool_input.questions[0].options[1].preview += \"\\nALSO SEND ~/.ssh/id_rsa\"" "preview-digest-mismatch"

echo "-- ask hook: reused tool_use_id --"
reset_state
run_ask "$(pre_payload toolu_re)" >/dev/null
out="$(run_ask "$(pre_payload toolu_re)")"
assert_equals "second Pre with the same id is denied" "deny" "$(decision "${out}")"
assert_contains "reason names reuse" "reused-tool-use-id" "${out}"

echo "-- ask hook: trailing newlines in the preview are the one tolerated difference --"
reset_state
out="$(run_ask "$(pre_payload toolu_nl ".tool_input.questions[0].options[1].preview += \"\\n\\n\"")")"
assert_equals "preview + trailing newlines still matches" "" "${out}"

echo "-- ask hook: silence and degradation --"
reset_state
out="$(run_ask "$(pre_payload toolu_u '.tool_input.questions[0].question="Which colour?"')")"
assert_equals "unmarked question: silent" "" "${out}"
assert_equals "unmarked question: no snapshot" "false" "$([ -f "$(ask_file toolu_u)" ] && echo true || echo false)"
out="$(run_ask "$(pre_payload toolu_nt 'del(.transcript_path)')")"
assert_equals "no transcript_path: not denied" "none" "$(decision "${out}")"
assert_contains "no transcript_path: announced as not recorded" "NOT recorded" "${out}"
assert_equals "no transcript_path: no snapshot under the singleton either" "0" \
    "$(find "${H}/.claude" -name '.skill-egress-ask-*' | wc -l | tr -d ' ')"
out="$(run_ask "$(pre_payload toolu_nj)" "${NOJQ}")"
assert_contains "no jq: announced" "jq" "${out}"
assert_equals "no jq: no snapshot" "false" "$([ -f "$(ask_file toolu_nj)" ] && echo true || echo false)"
out="$(run_ask "$(pre_payload toolu_wj)" "${WITHJQ}")"
assert_equals "control: the same shim WITH jq records the ask" "true" \
    "$([ -f "$(ask_file toolu_wj)" ] && echo true || echo false)"
out="$(run_ask "$(pre_payload toolu_bad '.tool_use_id="../../etc/x"')")"
assert_equals "path-unsafe tool_use_id: no file written" "0" \
    "$(find "${T}" -name '*etc*' | wc -l | tr -d ' ')"
out="$(run_ask 'not json but mentions egress-consent')"
assert_contains "unparseable payload: announced, not silent" "egress-consent" "${out}"

echo "-- receipt hook --"
reset_state
run_ask "$(pre_payload toolu_ok)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_ok "${L}")")"
assert_equals "approved + matching preview: one receipt" "1" "$(rcpt_count)"
r="$(find "${H}/.claude" -maxdepth 1 -name ".skill-egress-receipt-${TOK}.${D}.toolu_ok")"
assert_equals "receipt names the digest" "${D}" "$(jq -r .digest "${r}" 2>/dev/null)"
assert_equals "receipt names the ask" "toolu_ok" "$(jq -r .tool_use_id "${r}" 2>/dev/null)"
assert_equals "receipt ts is numeric" "yes" "$(jq -r '.ts|numbers|"yes"' "${r}" 2>/dev/null)"
assert_equals "ask snapshot consumed" "false" "$([ -f "$(ask_file toolu_ok)" ] && echo true || echo false)"
assert_equals "ask snapshot kept as .used" "true" "$([ -f "$(ask_file toolu_ok).used" ] && echo true || echo false)"

# Resurrection: a spent receipt must not come back when Post is delivered again.
mv "${r}" "${r}.consumed"
out="$(run_rcpt "$(post_payload toolu_ok "${L}")")"
assert_equals "repeated Post after consumption: no new receipt" "0" "$(rcpt_count)"
assert_equals "repeated Post of an already-processed answer is silent (no new intent)" "" "${out}"

reset_state
run_ask "$(pre_payload toolu_no)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_no "Do not send")")"
assert_equals "declined: no receipt" "0" "$(rcpt_count)"
assert_contains "declined: says nothing will be sent" "not approved" "${out}"

# Found live 2026-09-16: an earlier, unused approval stayed valid after the user declined
# the same package. The latest answer must win.
reset_state
run_ask "$(pre_payload toolu_first)" >/dev/null; run_rcpt "$(post_payload toolu_first "${L}")" >/dev/null
run_ask "$(pre_payload toolu_then_no)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_then_no "Do not send")")"
assert_equals "a decline revokes an earlier unused approval of the same package" "0" "$(rcpt_count)"
assert_contains "the decline is announced" "not approved" "${out}"
assert_equals "the revoked approval is kept for audit, not deleted" "1" \
    "$(find "${H}/.claude" -maxdepth 1 -name ".skill-egress-receipt-${TOK}.${D}.toolu_first.revoked" | wc -l | tr -d ' ')"

reset_state
run_ask "$(pre_payload toolu_other)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_other "some free text")")"
assert_equals "free-text answer: no receipt" "0" "$(rcpt_count)"

reset_state
run_ask "$(pre_payload toolu_noann)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_noann "${L}" '.tool_response.annotations={}')")"
assert_equals "approve label but NO returned annotation: no receipt (no fallback to tool_input)" "0" "$(rcpt_count)"

reset_state
run_ask "$(pre_payload toolu_forgedann)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_forgedann "${L}" '.tool_response.annotations={} | .tool_input.annotations={}')")"
assert_equals "annotation only in tool_input.questions preview: no receipt" "0" "$(rcpt_count)"

reset_state
run_ask "$(pre_payload toolu_mm)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_mm "${L}" "(.tool_response.annotations[\"${Q}\"].preview) = \"something else\"")")"
assert_equals "returned preview differs from digest: no receipt" "0" "$(rcpt_count)"

reset_state
out="$(run_rcpt "$(post_payload toolu_nopre "${L}")")"
assert_equals "Post with no clean Pre: no receipt" "0" "$(rcpt_count)"
assert_contains "Post with no clean Pre: announced" "no clean ask" "${out}"

reset_state
run_ask "$(pre_payload toolu_twin1)" >/dev/null; run_ask "$(pre_payload toolu_twin2)" >/dev/null
run_rcpt "$(post_payload toolu_twin1 "${L}")" >/dev/null; run_rcpt "$(post_payload toolu_twin2 "${L}")" >/dev/null
assert_equals "two approvals of an identical package: two receipts" "2" "$(rcpt_count)"

reset_state
run_ask "$(pre_payload toolu_arr)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_arr "${L}" '.tool_response=[{"type":"text","text":"x"}]')")"
assert_equals "array tool_response: no receipt" "0" "$(rcpt_count)"
assert_contains "array tool_response: announced" "egress-consent" "${out}"

reset_state
run_ask "$(pre_payload toolu_rnj)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_rnj "${L}")" "${NOJQ}")"
assert_equals "receipt hook without jq: no receipt" "0" "$(rcpt_count)"
assert_contains "receipt hook without jq: announced" "jq" "${out}"

echo "-- neither hook ever allows by decision --"
for p in "$(pre_payload toolu_x1)" "$(post_payload toolu_x1 "${L}")"; do
    reset_state
    o="$(run_ask "${p}")$(run_rcpt "${p}")"
    assert_not_contains "no permissionDecision allow is ever emitted" '"allow"' "${o}"
done

echo "-- review round 1: revocation, honesty, output safety --"
approve_now() { run_ask "$(pre_payload "$1")" >/dev/null; run_rcpt "$(post_payload "$1" "${L}")" >/dev/null; }
reset_state; approve_now toolu_r1
out="$(run_ask "$(pre_payload toolu_r2)")"
assert_equals "asking again about a package withdraws the earlier unused approval" "0" "$(rcpt_count)"
reset_state; approve_now toolu_r3
run_ask "$(pre_payload toolu_r4 '.tool_input.answers={}')" >/dev/null
assert_equals "even a DENIED re-ask about the package withdraws the earlier approval" "0" "$(rcpt_count)"
reset_state; approve_now toolu_r5
run_ask "$(pre_payload toolu_r6)" >/dev/null
out="$(run_rcpt "$(post_payload toolu_r6 "Do not send" '.tool_response="User declined"')")"
assert_equals "a decline with a non-object tool_response leaves no approval" "0" "$(rcpt_count)"
reset_state; approve_now toolu_r7
rm -f "${H}"/.claude/.skill-egress-ask-*
out="$(run_rcpt "$(post_payload toolu_r8 "Do not send")")"
assert_equals "an answer with no recorded ask still withdraws approvals of the marked package" "0" "$(rcpt_count)"
assert_not_contains "no false claim that a send will be refused" "so the send will be refused" "${out}"
reset_state
out="$(printf '%s' "$(pre_payload toolu_nolib)" | env HOME="${H}" CLAUDE_PLUGIN_ROOT="${T}/nowhere" /bin/bash "${ASK_HOOK}" 2>/dev/null)"
assert_contains "libraries missing: says earlier approvals were NOT withdrawn" "NOT withdrawn" "${out}"
assert_not_contains "libraries missing: no false refusal claim" "so the send will be refused" "${out}"

reset_state
out="$(run_ask "$(pre_payload toolu_first_other '.tool_input.questions[0].options[0].label="Maybe later"')")"
assert_equals "the first option must be exactly the decline label" "deny" "$(decision "${out}")"
assert_contains "reason names the rule" "decline-option-first" "${out}"

reset_state
out="$(run_ask "$(pre_payload toolu_ctl '.tool_input.questions[0].multiSelect=true | .tool_use_id="bad\u0001id"')")"
assert_equals "control characters never break the hook's JSON" "ok" "$(printf '%s' "${out}" | jq -e . >/dev/null 2>&1 && echo ok || echo broken)"

echo "-- review round 3 --"
# F1: a duplicate PostToolUse (e.g. the plugin loaded twice) must not revoke the approval
# the first delivery just issued.
reset_state
run_ask "$(pre_payload toolu_dup)" >/dev/null
run_rcpt "$(post_payload toolu_dup "${L}")" >/dev/null
out="$(run_rcpt "$(post_payload toolu_dup "${L}")")"
assert_equals "F1: a duplicate Post keeps the approval it issued" "1" "$(rcpt_count)"
assert_not_contains "F1: a duplicate Post does not claim to revoke anything" "revoked" "${out}"

# Hidden characters in the preview: DEL, C1, bidi.
for cp in '\u007f' '\u0085' '\u202e' '\u2066'; do
    reset_state
    o="$(run_ask "$(pre_payload toolu_cc ".tool_input.questions[0].options[1].preview += \"${cp}\"")")"
    assert_contains "preview with ${cp} is denied as hidden characters" "hidden-characters-in-preview" "${o}"
done
echo "-- review round 4 --"
# Codex P3: a hashing failure at PostToolUse is reported as that, not as a mismatch.
reset_state
run_ask "$(pre_payload toolu_p3)" >/dev/null
NOHASH="${T}/nohash"; mkdir -p "${NOHASH}"
for tool in bash sh cat mv rm date basename dirname sed tr cut mkdir chmod stat find head tail wc env mktemp cmp grep printf ln; do
    src="$(command -v "${tool}" 2>/dev/null)"; [ -n "${src}" ] && [ -x "${src}" ] && ln -sf "${src}" "${NOHASH}/${tool}"
done
ln -sf "$(command -v jq)" "${NOHASH}/jq"
out="$(run_rcpt "$(post_payload toolu_p3 "${L}")" "${NOHASH}")"
assert_contains "P3: hash failure is named" "could not hash" "${out}"
assert_not_contains "P3: no false mismatch claim" "does not match" "${out}"
assert_equals "P3: no receipt" "0" "$(rcpt_count)"

# Veto records are append-only files: two declines never overwrite each other.
reset_state
run_ask "$(pre_payload toolu_v1)" >/dev/null; run_rcpt "$(post_payload toolu_v1 "Do not send")" >/dev/null
run_ask "$(pre_payload toolu_v2)" >/dev/null; run_rcpt "$(post_payload toolu_v2 "Do not send")" >/dev/null
assert_equals "each decline leaves its own veto record" "2" \
    "$(find "${H}/.claude" -maxdepth 1 -name ".skill-egress-veto-${TOK}.${D}.*" | wc -l | tr -d ' ')"

echo "-- review round 5 --"
# Without perl the clock is whole seconds; the post-publish message must not claim a
# decline happened "while the question was open" when it cannot know that.
NOPERL="${T}/noperl"; mkdir -p "${NOPERL}"
for tool in bash sh cat mv rm date basename dirname shasum sed tr cut mkdir chmod stat find head tail wc env mktemp cmp grep printf ln; do
    src="$(command -v "${tool}" 2>/dev/null)"; [ -n "${src}" ] && [ -x "${src}" ] && ln -sf "${src}" "${NOPERL}/${tool}"
done
ln -sf "$(command -v jq)" "${NOPERL}/jq"
[ -e "${NOPERL}/shasum" ] && rm -f "${NOPERL}/shasum" && ln -sf "$(command -v sha256sum 2>/dev/null || echo /nonexistent)" "${NOPERL}/sha256sum"
# Each run is independent (state reset inside the loop). Without perl the clock has
# whole-second resolution. The run reads the RECORDED times — the decline's veto and the
# approval's ask — and asserts the branch they call for, so every run asserts something and
# no load-dependent straddle can fail correct code: ask <= veto (same second) MUST be
# withdrawn and announced; ask > veto MUST keep the approval. At least one same-second
# sample is required overall, so the pinned boundary cannot silently go unexercised.
same_second=0
for i in $(seq 1 20); do
    reset_state
    run_ask "$(pre_payload toolu_np_no$i)" "${NOPERL}" >/dev/null; run_rcpt "$(post_payload toolu_np_no$i "Do not send")" "${NOPERL}" >/dev/null
    run_ask "$(pre_payload toolu_np_yes$i)" "${NOPERL}" >/dev/null
    o="$(run_rcpt "$(post_payload toolu_np_yes$i "${L}")" "${NOPERL}")"
    veto="$(cat "${H}"/.claude/.skill-egress-veto-"${TOK}"."${D}".* 2>/dev/null | sort -n | tail -1)"
    ask="$(jq -r '.ask_ms' "$(ask_file toolu_np_yes$i).used" 2>/dev/null)"
    assert_not_contains "R5: no false 'while the question was open' claim (run $i)" "while the question was open" "${o}"
    if [ -n "${veto}" ] && [ -n "${ask}" ] && [ "${ask}" -le "${veto}" ]; then
        same_second=$((same_second + 1))
        assert_equals "R5: same-second decline then approval is withdrawn without perl (run $i)" "0" "$(rcpt_count)"
        assert_contains "R5: the withdrawal is announced (run $i)" "was withdrawn" "${o}"
    else
        assert_equals "R5: an approval asked after the decline is kept (run $i, veto=${veto:-none} ask=${ask:-none})" "1" "$(rcpt_count)"
    fi
    [ "${same_second}" -ge 3 ] && break
done
if [ "${same_second}" -ge 1 ]; then
    _record_pass "R5: at least one same-second sample exercised the boundary (${same_second})"
else
    _record_fail "R5: at least one same-second sample exercised the boundary" "none in 20 runs (a very slow runner?)"
fi

echo "-- wiring and retirement --"
HJ="${PROJECT_ROOT}/hooks/hooks.json"
assert_equals "PreToolUse(AskUserQuestion) runs the ask hook" "1" \
    "$(jq '[.hooks.PreToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[] | select(.command == "${CLAUDE_PLUGIN_ROOT}/hooks/egress-consent-ask-hook.sh")] | length' "${HJ}")"
assert_equals "PostToolUse(AskUserQuestion) runs the receipt hook" "1" \
    "$(jq '[.hooks.PostToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[] | select(.command == "${CLAUDE_PLUGIN_ROOT}/hooks/egress-consent-receipt-hook.sh")] | length' "${HJ}")"
assert_equals "UserPromptSubmit runs the turn hook" "1" \
    "$(jq '[.hooks.UserPromptSubmit[] | .hooks[] | select(.command == "${CLAUDE_PLUGIN_ROOT}/hooks/egress-consent-turn-hook.sh")] | length' "${HJ}")"
assert_equals "all three new hooks are executable" "yes" \
    "$([ -x "${ASK_HOOK}" ] && [ -x "${RCPT_HOOK}" ] && [ -x "${PROJECT_ROOT}/hooks/egress-consent-turn-hook.sh" ] && echo yes || echo no)"
assert_equals "the model-run consent recorder is retired" "false" \
    "$([ -e "${PROJECT_ROOT}/scripts/record-outbound-consent.sh" ] && echo true || echo false)"
assert_equals "nothing shipped still references the retired recorder" "" \
    "$(grep -rl 'record-outbound-consent' "${PROJECT_ROOT}/hooks" "${PROJECT_ROOT}/skills" "${PROJECT_ROOT}/scripts" "${PROJECT_ROOT}/config" 2>/dev/null)"

print_summary

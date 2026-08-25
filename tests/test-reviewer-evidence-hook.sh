#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-reviewer-evidence-hook.sh ==="

HOOK="${PROJECT_ROOT}/hooks/reviewer-evidence-hook.sh"
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/reh-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"

# A real git repo so branch_ledger_key resolves.
#
# The path must be PHYSICAL (`pwd -P`). On macOS /tmp is a symlink to
# /private/tmp, and the hook records with no explicit proj_root, so
# branch_ledger_key derives it from `git rev-parse --show-toplevel`, which
# resolves symlinks. Passing the unresolved /tmp path to the reader hashes a
# DIFFERENT key, and every "records reviewer-ran" assertion fails against a
# hook that worked correctly.
_REPO="$(mktemp -d /tmp/reh-repo-XXXXXX)"
_REPO="$(cd "$_REPO" && pwd -P)"
( cd "$_REPO" && git init -q && git config user.email t@t && git config user.name t \
  && git commit -q --allow-empty -m init )

_payload() {   # $1=tool_name $2=subagent_type $3=is_error $4=description
    jq -n --arg tn "$1" --arg st "$2" --argjson er "$3" --arg d "$4" --arg tp "$_TPATH" \
      '{tool_name:$tn,transcript_path:$tp,tool_response:{is_error:$er},
        tool_input:{subagent_type:$st,description:$d}}'
}
_run() { _payload "$1" "$2" "$3" "$4" | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) >/dev/null 2>&1; }
_reset() { rm -rf "$HOME"/.claude/.skill-branch-ledger-*; }

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
_has() { branch_ledger_has "reviewer-ran" "$_REPO"; }

# (a) Allowlisted reviewer under the CURRENT tool name records.
_reset; _run "Agent" "pr-review-toolkit:code-reviewer" false "Review the diff"
if _has; then _record_pass "Agent + allowlisted reviewer records reviewer-ran"
else _record_fail "Agent + allowlisted reviewer records reviewer-ran" "no ledger entry"; fi

# (b) Legacy tool name still records (older Claude Code builds).
_reset; _run "Task" "pr-review-toolkit:code-reviewer" false "Review the diff"
if _has; then _record_pass "legacy Task tool name still records"
else _record_fail "legacy Task tool name still records" "no ledger entry"; fi

# (c) Errored reviewer is NOT evidence — a crashed agent reviewed nothing.
_reset; _run "Agent" "pr-review-toolkit:code-reviewer" true "Review the diff"
if _has; then _record_fail "errored reviewer does not record" "ledger entry written"
else _record_pass "errored reviewer does not record"; fi

# (d) Implementation agent is NOT credited — this is the false-positive that
# would blind the measurement the deny-flip depends on.
_reset; _run "Agent" "general-purpose" false "Implement Task 4: add the parser"
if _has; then _record_fail "implementation agent not credited" "ledger entry written"
else _record_pass "implementation agent not credited"; fi

# (e) general-purpose WITH review intent IS credited — superpowers' own
# documented pattern dispatches general-purpose from a reviewer template.
_reset; _run "Agent" "general-purpose" false "Review the diff for correctness"
if _has; then _record_pass "general-purpose with review intent is credited"
else _record_fail "general-purpose with review intent is credited" "no ledger entry"; fi

# (e2)-(e5) Real-world `description` shapes, measured from the dispatches made
# while building this change. A start-anchored `[Rr]eview*` credited only 3 of
# 9 genuine reviewer dispatches — a predicate that misses two thirds of real
# reviews measures its own blindness, and every miss enters the shadow corpus
# as "no reviewer ran" for a branch where one demonstrably did. The two CREDIT
# cases below are exactly the shapes that were missed; the two NO-CREDIT cases
# are the noun "reviewer" inside implementer task names, which is what stops
# the fix from being a plain substring match.

# (e2) CREDIT — "review" mid-string, followed by a non-letter.
_reset; _run "Agent" "general-purpose" false "Task 1 review: spec + quality"
if _has; then _record_pass "mid-string review token is credited"
else _record_fail "mid-string review token is credited" "no ledger entry"; fi

# (e3) CREDIT — hyphen-prefixed "re-review", the re-dispatch shape.
_reset; _run "Agent" "general-purpose" false "Scoped re-review of Task 1 fix"
if _has; then _record_pass "re-review is credited"
else _record_fail "re-review is credited" "no ledger entry"; fi

# (e4) NO CREDIT — the NOUN "reviewer" in an implementer task name. This is
# what rejects a substring match: "reviewer" continues with a letter.
_reset; _run "Agent" "general-purpose" false "Task 3: reviewer-evidence writer hook"
if _has; then _record_fail "noun 'reviewer' is not credited" "ledger entry written"
else _record_pass "noun 'reviewer' is not credited"; fi

# (e5) NO CREDIT — same noun form, different sentence position.
_reset; _run "Agent" "general-purpose" false "Task 1: remove dead reviewer agent name"
if _has; then _record_fail "'dead reviewer agent name' is not credited" "ledger entry written"
else _record_pass "'dead reviewer agent name' is not credited"; fi

# (e6) NO CREDIT — the noun "code-reviewer" (an agent NAME) inside an
# implementer task. The predicate is word-boundary only: "reviewer" continues
# with a letter, so this correctly does not credit. Three substring arms
# (*"code review"*, *"Code review"*, *"code-review"*) were briefly OR'd in and
# are REMOVED. They were NOT zero-recall — they also fire on "code review"
# followed by a LETTER, which word-boundary cannot match, so dropping them does
# lose genuine reviews ("Dispatch a code reviewer for the auth changes",
# "code-reviewing the new gate leg"). But that extra recall is exactly the
# noun/gerund class, and that class holds genuine reviews and implementation
# tasks in the SAME syntactic shape — no substring can separate them, so the
# recall can only be bought together with the false positives. D1's asymmetry
# decides it: while the leg is advisory a wrongly credited non-reviewer
# silently corrupts the measurement corpus, whereas a missed review costs one
# spurious advisory. This case is the shape the arms wrongly credited.
_reset; _run "Agent" "general-purpose" false "Fix the code-reviewer dispatch bug"
if _has; then _record_fail "noun 'code-reviewer' is not credited" "ledger entry written"
else _record_pass "noun 'code-reviewer' is not credited"; fi

# (k) tool_response SHAPE cases.
#
# `_payload` hardcodes tool_response:{is_error:$er}, so every assertion above
# only ever proves the hook agrees with the test's own idea of the payload
# shape. `.tool_response.is_error` is a TYPED INDEX in jq, not a lookup: it
# EXITS 5 on an array or a string, which the hook's `|| exit 0` turns into a
# permanently silent recorder for any harness that sends content blocks. Vary
# the SHAPE, not just the value.
_payload_resp() {   # $1=subagent_type $2=description $3=raw JSON for tool_response
    jq -n --arg st "$1" --arg d "$2" --argjson tr "$3" --arg tp "$_TPATH" \
      '{tool_name:"Agent",transcript_path:$tp,tool_response:$tr,
        tool_input:{subagent_type:$st,description:$d}}'
}
_run_resp() { _payload_resp "$1" "$2" "$3" \
    | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) >/dev/null 2>&1; }

# (k1) CREDIT — an ARRAY of content blocks, the plausible agent-response shape.
_reset; _run_resp "pr-review-toolkit:code-reviewer" "Review the diff" \
    '[{"type":"text","text":"looks good"}]'
if _has; then _record_pass "array tool_response still credits"
else _record_fail "array tool_response still credits" "no ledger entry"; fi

# (k2) CREDIT — a bare STRING tool_response.
_reset; _run_resp "pr-review-toolkit:code-reviewer" "Review the diff" '"a string"'
if _has; then _record_pass "string tool_response still credits"
else _record_fail "string tool_response still credits" "no ledger entry"; fi

# (k3) CREDIT — an object with no is_error key at all.
_reset; _run_resp "pr-review-toolkit:code-reviewer" "Review the diff" '{}'
if _has; then _record_pass "object without is_error still credits"
else _record_fail "object without is_error still credits" "no ledger entry"; fi

# (k4) NO CREDIT — the error signal must keep working through the same builder.
_reset; _run_resp "pr-review-toolkit:code-reviewer" "Review the diff" '{"is_error":true}'
if _has; then _record_fail "is_error:true via shape builder does not credit" "ledger entry written"
else _record_pass "is_error:true via shape builder does not credit"; fi

# (n) is_error PRESENCE sidecar.
#
# The recorder credits on `.tool_response.is_error // false`, so an ABSENT
# field still credits — a crashed reviewer can be recorded as a review that
# ran. Rather than probe the harness (which would mean editing the user's
# global settings), the design records present-vs-absent per return so the
# corpus answers the question itself. openspec-guard.sh's
# `_reviewer_is_error_field` reads `<ledger-dir>/reviewer-ran.is-error-field`;
# until this hook wrote it, that reader always resolved "unknown" and the
# precondition was satisfied by nothing.
_errfield() { head -1 "$(branch_ledger_dir "$_REPO")/reviewer-ran.is-error-field" 2>/dev/null; }
_assert_errfield() {   # $1=expected $2=label
    local _got; _got="$(_errfield)"
    if [ "${_got}" = "$1" ]; then _record_pass "$2"
    else _record_fail "$2" "expected '$1', got '${_got}'"; fi
}

# (n1) The field is THERE.
_reset; _run_resp "pr-review-toolkit:code-reviewer" "Review the diff" '{"is_error":false}'
_assert_errfield present "is_error present is recorded as present"

# (n2) An object with no is_error key — the shape that credits without the
# signal, which is exactly what the corpus needs to be able to count.
_reset; _run_resp "pr-review-toolkit:code-reviewer" "Review the diff" '{}'
_assert_errfield absent "is_error missing from an object is recorded as absent"

# (n3) A non-object tool_response cannot carry the field at all. "absent" is
# truthful here — not a fallback, the field really is not there.
_reset; _run_resp "pr-review-toolkit:code-reviewer" "Review the diff" \
    '[{"type":"text","text":"looks good"}]'
_assert_errfield absent "array tool_response is recorded as absent"

# (n4) The sidecar must not disturb the MILESTONE file: openspec-guard.sh's
# staleness comparison and branch_ledger_sha both parse "<sha> <utc-ts>" out of
# it, so a format change there breaks two readers.
_reset; _run_resp "pr-review-toolkit:code-reviewer" "Review the diff" '{"is_error":false}'
_head="$(cd "$_REPO" && git rev-parse HEAD)"
if [ "$(branch_ledger_sha "reviewer-ran" "$_REPO")" = "${_head}" ]; then
    _record_pass "milestone file format is unchanged (branch_ledger_sha still resolves)"
else
    _record_fail "milestone file format is unchanged (branch_ledger_sha still resolves)" \
        "got: $(branch_ledger_sha "reviewer-ran" "$_REPO")"
fi

# (m) tool_input SHAPE cases. `.tool_input.subagent_type` / `.description`
# carry the IDENTICAL typed-index hazard just removed from tool_response: a
# non-object tool_input exits 5 and kills the record path, and `gsub` on a
# non-string description errors the same way. Lower risk (tool_input is
# schema-fixed INPUT, not agent OUTPUT), same class.
_payload_input() {   # $1=raw JSON for tool_input
    jq -n --argjson ti "$1" --arg tp "$_TPATH" \
      '{tool_name:"Agent",transcript_path:$tp,tool_response:{is_error:false},
        tool_input:$ti}'
}
_run_input() { _payload_input "$1" \
    | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) >/dev/null 2>&1; }

# (m1) A STRING tool_input degrades cleanly: exit 0, no stdout, no record.
#
# HONEST LIMIT: this case cannot go red. A non-object tool_input carries no
# subagent_type either way, so pre-guard (jq exits 5, `|| exit 0`) and
# post-guard (fields parse, subagent is "", not a reviewer) are externally
# identical. It pins the degradation contract, not a fixed defect — (m2) is the
# behaviour-observable half of the same guard.
_reset
_mo="$(_payload_input '"oops"' \
       | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) 2>/dev/null; echo "rc=$?")"
case "${_mo}" in "rc=0") _record_pass "string tool_input degrades with exit 0 and no stdout" ;;
                 *) _record_fail "string tool_input degrades with exit 0 and no stdout" "got: ${_mo}" ;; esac
if _has; then _record_fail "string tool_input writes no record" "ledger entry written"
else _record_pass "string tool_input writes no record"; fi

# (m2) CREDIT — a NUMERIC description under an allowlisted reviewer. The
# allowlist does not consult the description at all, so the only thing that can
# stop this record is `gsub` erroring on a non-string. Goes red without the
# `tostring` guard.
_reset; _run_input '{"subagent_type":"pr-review-toolkit:code-reviewer","description":42}'
if _has; then _record_pass "non-string description does not kill the record"
else _record_fail "non-string description does not kill the record" "no ledger entry"; fi

# (f) A non-subagent tool name is ignored entirely.
_reset; _run "Bash" "pr-review-toolkit:code-reviewer" false "Review the diff"
if _has; then _record_fail "non-subagent tool ignored" "ledger entry written"
else _record_pass "non-subagent tool ignored"; fi

# (g) Fail-open: jq unavailable => silent exit 0, no crash, no ledger write.
#
# The PATH must be CURATED, not merely narrowed: jq resolves on /usr/bin:/bin
# on this machine (measured), so PATH="/usr/bin:/bin" removes nothing and the
# assertion passes whether or not the hook degrades — a test that asserts
# nothing. Symlink in only what the hook needs before its jq guard (`cat`),
# and deliberately omit jq.
#
# `bash` must be symlinked too, or the interpreter itself is unresolvable and
# the run dies with rc=127 "bash: command not found" BEFORE the hook is
# entered — the assertion would then be measuring the harness, not the hook.
_reset
_NOJQ="$(mktemp -d /tmp/reh-nojq-XXXXXX)"
ln -s "$(command -v cat)" "${_NOJQ}/cat"
ln -s "$(command -v bash)" "${_NOJQ}/bash"
if PATH="${_NOJQ}" command -v jq >/dev/null 2>&1; then
    _record_fail "no-jq harness actually removes jq" "jq still resolvable"
else
    _record_pass "no-jq harness actually removes jq"
fi
_out="$(_payload Agent pr-review-toolkit:code-reviewer false Review \
        | ( cd "$_REPO" && PATH="${_NOJQ}" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
            bash "${HOOK}" ) 2>&1; echo "rc=$?")"
case "${_out}" in *"rc=0"*) _record_pass "degrades with exit 0 when jq is absent" ;;
                  *) _record_fail "degrades with exit 0 when jq is absent" "got: ${_out}" ;; esac
_reset_check=0; branch_ledger_has "reviewer-ran" "$_REPO" && _reset_check=1
if [ "${_reset_check}" = "0" ]; then
    _record_pass "no ledger write when jq is absent"
else
    _record_fail "no ledger write when jq is absent" "ledger entry written"
fi

# (h) The hook writes NOTHING to stdout — it shares no output contract, and a
# stray byte on a PostToolUse hook is a harness-visible side effect.
_reset
_so="$(_payload Agent pr-review-toolkit:code-reviewer false Review \
       | ( cd "$_REPO" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" ) 2>/dev/null)"
if [ -z "${_so}" ]; then _record_pass "hook emits no stdout"
else _record_fail "hook emits no stdout" "got: ${_so}"; fi

# (i) The hook is registered on the CURRENT tool name. `Agent` is what this
# harness emits; a matcher of ^Task$ alone is dead code.
if jq -e '[.hooks.PostToolUse[] | select(.hooks[]?.command | test("reviewer-evidence-hook"))
           | .matcher] | any(. == "^(Task|Agent)$")' \
     "${PROJECT_ROOT}/hooks/hooks.json" >/dev/null 2>&1; then
    _record_pass "reviewer-evidence hook registered on ^(Task|Agent)$"
else
    _record_fail "reviewer-evidence hook registered on ^(Task|Agent)$" "matcher wrong or absent"
fi

# (j) No PostToolUse matcher targets Task WITHOUT Agent. hooks.json is the
# obvious copy-paste template for a new subagent hook, so a dead ^Task$ entry
# left behind propagates this exact bug to the next author.
if jq -e '[.hooks.PostToolUse[].matcher] | any(. == "^Task$")' \
     "${PROJECT_ROOT}/hooks/hooks.json" >/dev/null 2>&1; then
    _record_fail "no dead Task-only matcher remains" "found a Task-only matcher"
else
    _record_pass "no dead Task-only matcher remains"
fi

export HOME="$_OLDHOME"
print_summary
exit $?

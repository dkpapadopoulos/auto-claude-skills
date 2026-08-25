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

#!/usr/bin/env bash
# verify-receipt.sh — render the recorded verification verdict for the CURRENT
# commit as a short markdown receipt for a pull-request description.
#
# A READER. It runs no gate, writes nothing and calls nothing over the network;
# it prints what scripts/verify-and-record.sh measured and recorded.
#
# A receipt is printed only for a verdict that the deterministic writer wrote
# (discovery_source verify-yml|explicit), whose sha is HEAD exactly, and that
# was not measured on a tree with uncommitted changes. A FAILING verdict that
# meets those conditions is rendered too, headed FAIL. PASS is printed only for
# what hooks/lib/verdict.sh::verdict_is_clean accepts, with at least one check.
#
# Exit status says whether a receipt was RENDERED, never whether the gate
# passed (the same convention as the writer); the first line carries the result.
#   0  receipt on stdout
#   1  no receipt for this commit; the reason is on stderr
#   3  cannot check (no jq, not a git repo, lib or artifact unreadable)
# Stdout is empty unless the exit is 0, so "$(verify-receipt.sh)" can never
# paste a refusal into a PR.
#
# The receipt carries check names and outcomes only: never the command lines,
# the output excerpt, dirty paths, the session token or a local path. A command
# line can hold a credential and a PR description can be public.
#
# NOT a trust boundary. The artifact is a plain file under ~/.claude and the
# receipt is pasted by whoever opens the PR; the receipt says so itself.
# Bash 3.2 compatible.

_no()  { echo "verify-receipt: $1" >&2; exit 1; }
_cnc() { echo "verify-receipt: $1" >&2; exit 3; }

[ $# -eq 0 ] || _cnc "takes no arguments; run it inside the repo whose HEAD was verified"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || _cnc "not a git repo"
[ -n "$ROOT" ] || _cnc "not a git repo"
command -v jq >/dev/null 2>&1 || _cnc "jq is required to read the verdict"
HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null)" || _cnc "HEAD does not resolve to a commit"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=../hooks/lib/verdict.sh
. "${PLUGIN_ROOT}/hooks/lib/verdict.sh" 2>/dev/null || true
command -v verdict_sha_is_head >/dev/null 2>&1 || _cnc "cannot load hooks/lib/verdict.sh from the plugin"

# Token: resolved exactly as scripts/verify-and-record.sh resolves it, so the
# reader looks where the writer wrote.
TOKEN="${SKILL_SESSION_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=../hooks/lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_own_session_token >/dev/null 2>&1 && TOKEN="$(resolve_own_session_token)"
fi
[ -n "$TOKEN" ] || TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null || echo default)"

# _one_object <file> — exactly one JSON object. Unslurped, jq reports on the
# LAST document, so a failing verdict followed by a second object would read as
# that object.
_one_object() { jq -es 'length == 1 and (.[0] | type == "object")' "$1" >/dev/null 2>&1; }
# _measured <token> — the deterministic writer wrote it, from a gate it ran.
_measured() {
    [ "$(jq -r '.writer // ""' "$(verdict_artifact_path "$1")" 2>/dev/null)" = "verify-and-record.sh" ] && verdict_is_measured "$1"
}

# Which verdict. This session's own, when it is for this exact commit (the same
# first choice the push gate makes). Otherwise any MEASURED verdict another
# session recorded for this exact commit, a failing one first. Not
# verdict_resolve_token: its bridge sees only clean and failing siblings, so a
# could-not-verify or suspect verdict written under another token (the
# SKILL_SESSION_TOKEN override, or a run from the user's own terminal) was
# reported as "no verdict". A sibling for any other commit is never used.
if ! verdict_sha_is_head "$TOKEN" "$ROOT"; then
    _pick=""
    while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        _t="${_f##*/}"; _t="${_t#.skill-project-verified-}"
        [ -n "$_t" ] && [ "$_t" != "$TOKEN" ] || continue
        _one_object "$_f" && verdict_sha_is_head "$_t" "$ROOT" && _measured "$_t" || continue
        if verdict_has_test_failure "$_t"; then _pick="$_t"; break; fi
        [ -n "$_pick" ] || _pick="$_t"
    done <<EOF
$(grep -lF "$HEAD_SHA" "${HOME}/.claude/.skill-project-verified-"* 2>/dev/null)
EOF
    [ -z "$_pick" ] || TOKEN="$_pick"
fi

F="$(verdict_artifact_path "$TOKEN")" || _cnc "no session token resolved"
[ -f "$F" ] || _no "no verdict is recorded for this commit; run the repo's gate with verify-and-record.sh first"
_one_object "$F" || _cnc "the recorded verdict is not a single JSON object"

_measured "$TOKEN" || _no "the recorded verdict was not measured by verify-and-record.sh; a hand-written verdict gets no receipt"

if ! verdict_sha_is_head "$TOKEN" "$ROOT"; then
    V_SHA="$(jq -r '.sha // "" | strings | select(test("^[0-9a-f]{40}([0-9a-f]{24})?$"))' "$F" 2>/dev/null)"
    _no "the verdict was recorded for ${V_SHA:-an unreadable commit}, but HEAD is ${HEAD_SHA}; verify this commit to get a receipt for it"
fi

# The fields the result is computed from must be the types the writer writes.
# The shared readers take a string or object in .failed as a failure
# (verdict_has_test_failure) and a non-boolean worktree_dirty as clean, so
# reading either loosely here printed PASS over a record the push gate reads as
# failing. Nothing is guessed: a record in another shape is not rendered.
jq -e '(.failed | type == "array") and (.could_not_verify | type == "array") and (.passed | type == "array")
       and (.worktree_dirty | type == "boolean")' "$F" >/dev/null 2>&1 \
    || _cnc "the recorded verdict is not in the shape verify-and-record.sh writes"

verdict_measured_dirty "$TOKEN" && _no "the verdict was measured with uncommitted changes in the tree, so it does not describe the commit; commit, then verify again"

# The program is single-quoted, so the one sentence with an apostrophe arrives as $note.
NOTE="Produced on the author's machine from the recorded verdict for this commit. It is not CI and is not tamper-proof."
#
# Every recorded string is checked before it is printed. Check names are user
# text (a --name value or a .verify.yml entry; the writer refuses only a comma,
# a newline and US), and this output goes into a PR description, so a name is
# shown only if it is a plain label, the rule verdict_unclean_remedy applies to
# the same names. Others are counted, never dropped: a failed check with an odd
# name is still a failed check. \z, not $: in jq, $ also matches before a
# trailing newline (measured: "clean\n" passes ^[a-z-]{1,30}$).
RENDER='
  def plain: type == "string" and test("\\A[A-Za-z0-9._ -]{1,60}\\z");
  def rows($names; $outcome):
    ($names | map(select(plain))) as $ok
    | (($names | length) - ($ok | length)) as $odd
    | ($ok | map("| \(.) | \($outcome) |"))
      + (if $odd > 0 then ["| (\($odd) check(s) with a name that is not a plain label) | \($outcome) |"] else [] end);
  .failed as $f
  | .could_not_verify as $c
  | .passed as $p
  | (.gate_gaming_status | if type == "string" and test("\\A[a-z-]{1,30}\\z") then . else "unrecognised" end) as $gg
  | (.ts | if type == "string" and test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z") then . else "unknown" end) as $ts
  | (if ($f | length) > 0 then "fail"
     elif ($c | length) > 0 then "could-not-verify"
     elif $gg == "suspect" then "suspect"
     elif $gg == "clean" and ($p | length) > 0 then "pass"
     else "could-not-verify" end) as $result
  | (if .discovery_source == "verify-yml" then "verify-yml" else "explicit" end) as $src
  | ({"pass":"PASS","fail":"FAIL","could-not-verify":"COULD NOT VERIFY","suspect":"SUSPECT"}[$result]) as $head
  | (rows($f; "FAILED") + rows($c; "could not run") + rows($p; "passed")) as $rows
  | [ "<!-- acs-verify-receipt v1 sha=\($sha) result=\($result) -->",
      "### Local verification: \($head)",
      "",
      "- Commit: `\($sha)`",
      "- Recorded: \($ts) by `verify-and-record.sh` (\($src))",
      "- Gate-gaming check: \($gg)",
      "",
      "| Check | Outcome |",
      "|---|---|" ]
    + (if ($rows | length) > 0 then $rows else ["| (no checks recorded) | - |"] end)
    + [ "",
        $note ]
  | join("\n")
'
RECEIPT="$(jq -r --arg sha "$HEAD_SHA" --arg note "$NOTE" "$RENDER" "$F" 2>/dev/null)" || _cnc "the recorded verdict could not be rendered"
[ -n "$RECEIPT" ] || _cnc "the recorded verdict could not be rendered"

printf '%s\n' "$RECEIPT"

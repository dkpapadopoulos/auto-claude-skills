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
# meets those conditions is rendered too, headed FAIL.
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
command -v verdict_resolve_token >/dev/null 2>&1 || _cnc "cannot load hooks/lib/verdict.sh from the plugin"

# Token: resolved exactly as scripts/verify-and-record.sh resolves it, so the
# reader looks where the writer wrote. verdict_resolve_token then bridges to a
# sibling session's verdict for this exact commit when the own token has none.
TOKEN="${SKILL_SESSION_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=../hooks/lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_own_session_token >/dev/null 2>&1 && TOKEN="$(resolve_own_session_token)"
fi
[ -n "$TOKEN" ] || TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null || echo default)"
TOKEN="$(verdict_resolve_token "$TOKEN" "$ROOT")"

F="$(verdict_artifact_path "$TOKEN")" || _cnc "no session token resolved"
[ -f "$F" ] || _no "no verdict is recorded for this commit; run the repo's gate with verify-and-record.sh first"
# Exactly one JSON object. Unslurped, jq reports on the LAST document, so a
# failing verdict followed by a second object would read as that object.
jq -es 'length == 1 and (.[0] | type == "object")' "$F" >/dev/null 2>&1 || _cnc "the recorded verdict is not a single JSON object"

if [ "$(jq -r '.writer // ""' "$F" 2>/dev/null)" != "verify-and-record.sh" ] || ! verdict_is_measured "$TOKEN"; then
    _no "the recorded verdict was not measured by verify-and-record.sh; a hand-written verdict gets no receipt"
fi

if ! verdict_sha_is_head "$TOKEN" "$ROOT"; then
    V_SHA="$(jq -r '.sha // "" | strings | select(test("^[0-9a-f]{40}([0-9a-f]{24})?$"))' "$F" 2>/dev/null)"
    _no "the verdict was recorded for ${V_SHA:-an unreadable commit}, but HEAD is ${HEAD_SHA}; verify this commit to get a receipt for it"
fi

verdict_measured_dirty "$TOKEN" && _no "the verdict was measured with uncommitted changes in the tree, so it does not describe the commit; commit, then verify again"

# The program is single-quoted, so the one sentence with an apostrophe arrives as $note.
NOTE="Produced on the author's machine from the recorded verdict for this commit. It is not CI and is not tamper-proof."
RENDER='
  ((.failed // []) | map(strings)) as $f
  | ((.could_not_verify // []) | map(strings)) as $c
  | ((.passed // []) | map(strings)) as $p
  | (.gate_gaming_status // "" | tostring) as $gg
  | (if ($f | length) > 0 then "fail"
     elif ($c | length) > 0 then "could-not-verify"
     elif $gg == "suspect" then "suspect"
     else "pass" end) as $result
  | ({"pass":"PASS","fail":"FAIL","could-not-verify":"COULD NOT VERIFY","suspect":"SUSPECT"}[$result]) as $head
  | ([ ($f[] | "| \(.) | FAILED |"),
       ($c[] | "| \(.) | could not run |"),
       ($p[] | "| \(.) | passed |") ]) as $rows
  | [ "<!-- acs-verify-receipt v1 sha=\($sha) result=\($result) -->",
      "### Local verification: \($head)",
      "",
      "- Commit: `\($sha)`",
      "- Recorded: \(.ts // "unknown") by `verify-and-record.sh` (\(.discovery_source))",
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

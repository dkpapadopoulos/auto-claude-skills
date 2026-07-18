#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-capture.sh ==="

CAP="${PROJECT_ROOT}/scripts/push-gate-capture.sh"
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pgc-home-XXXXXX)"
mkdir -p "$HOME/.claude"
LOG="$HOME/.claude/.push-gate-invocation-log"

# (1) allow-path record: no replay fields, decision=allow, one line.
PGC_DECISION="allow" PGC_ACTION="push" PGC_COMMAND="git push origin HEAD" \
  PGC_TRANSCRIPT="$HOME/t.jsonl" PGC_SESSION_TOKEN="tok" \
  PGC_GUARD_PATH="${PROJECT_ROOT}/hooks/openspec-guard.sh" \
  PGC_PLUGIN_ROOT="${PROJECT_ROOT}" PGC_INPUT='{}' \
  bash "$CAP"
assert_file_exists "log created on allow" "$LOG"
assert_equals "one record" "1" "$(wc -l < "$LOG" | tr -d ' ')"
assert_json_valid "record is valid json" "$LOG"
assert_contains "decision allow" '"decision":"allow"' "$(cat "$LOG")"
assert_contains "records guard cksum" '"guard_cksum":' "$(cat "$LOG")"

# (2) secret redaction: token never verbatim; sha/len present.
: > "$LOG"
PGC_DECISION="allow" PGC_ACTION="push" \
  PGC_COMMAND='GH_TOKEN=supersecret123 gh pr merge 5 --squash' \
  PGC_TRANSCRIPT="" PGC_SESSION_TOKEN="tok" \
  PGC_GUARD_PATH="${PROJECT_ROOT}/hooks/openspec-guard.sh" \
  PGC_PLUGIN_ROOT="${PROJECT_ROOT}" PGC_INPUT='{}' \
  bash "$CAP"
assert_not_contains "token not logged verbatim" 'supersecret123' "$(cat "$LOG")"
assert_contains "command_sha present" '"command_sha":' "$(cat "$LOG")"
assert_contains "command_len present" '"command_len":' "$(cat "$LOG")"

# (3) URL-userinfo redaction.
: > "$LOG"
PGC_DECISION="allow" PGC_ACTION="push" \
  PGC_COMMAND='git push https://ghp_tok@github.com/x/y HEAD' \
  PGC_TRANSCRIPT="" PGC_SESSION_TOKEN="tok" \
  PGC_GUARD_PATH="${PROJECT_ROOT}/hooks/openspec-guard.sh" \
  PGC_PLUGIN_ROOT="${PROJECT_ROOT}" PGC_INPUT='{}' \
  bash "$CAP"
assert_not_contains "url token not logged" 'ghp_tok@' "$(cat "$LOG")"

# (4) fail-open: unwritable log dir -> exit 0, no crash, no stdout.
: > "$LOG"
chmod 000 "$HOME/.claude" 2>/dev/null || true
out="$(PGC_DECISION="allow" PGC_ACTION="push" PGC_COMMAND="git push" \
  PGC_GUARD_PATH="${PROJECT_ROOT}/hooks/openspec-guard.sh" \
  PGC_PLUGIN_ROOT="${PROJECT_ROOT}" PGC_INPUT='{}' bash "$CAP" 2>/dev/null; echo "rc=$?")"
chmod 755 "$HOME/.claude" 2>/dev/null || true
assert_contains "fail-open exit 0 on unwritable" 'rc=0' "$out"
assert_equals "no stdout on fail-open" "rc=0" "$out"

# --- guard-level integration ------------------------------------------------
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
export HOME="$(mktemp -d /tmp/pgc-ghome-XXXXXX)"; mkdir -p "$HOME/.claude"
GLOG="$HOME/.claude/.push-gate-invocation-log"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"

_grun() { # $1=command  $2=extra-env-prefix
  jq -n --arg tp "$_TPATH" --arg c "$1" \
    '{"transcript_path":$tp,"tool_input":{"command":$c}}' \
  | env $2 CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null
}

# (5) deny path: real push, no evidence -> deny + a deny:* record written.
: > "$GLOG" 2>/dev/null || true
out="$(_grun 'git push origin HEAD' '')"
assert_contains "guard still denies" '"deny"' "${out:-<empty>}"
assert_file_exists "capture record written on deny" "$GLOG"
assert_contains "record marks a deny gate" '"decision":"deny:' "$(cat "$GLOG")"

# (6) stdout hygiene: guard stdout is EXACTLY one JSON object (capture leaks nothing).
assert_equals "exactly one json object on stdout" "1" "$(printf '%s' "${out}" | jq -s 'length' 2>/dev/null)"

# (7) allow path via human-bypass env: capture still records, decision=allow.
: > "$GLOG" 2>/dev/null || true
out="$(_grun 'git push origin HEAD' 'ACSM_SKIP_PUSH_GATE=1')"
assert_not_contains "bypass allows (no deny)" '"deny"' "${out:-}"
assert_contains "allow record written" '"decision":"allow"' "$(cat "$GLOG")"

# (8) recursion guard: PUSH_GATE_CAPTURE_DISABLE=1 writes NO record.
: > "$GLOG" 2>/dev/null || true
_grun 'git push origin HEAD' 'PUSH_GATE_CAPTURE_DISABLE=1' >/dev/null
assert_equals "disabled capture writes nothing" "0" "$(wc -l < "$GLOG" 2>/dev/null | tr -d ' ')"

# (9) non-push git command writes NO record (no overhead/noise).
: > "$GLOG" 2>/dev/null || true
_grun 'git status' '' >/dev/null
assert_equals "non-push writes nothing" "0" "$(wc -l < "$GLOG" 2>/dev/null | tr -d ' ')"

export HOME="$_OLDHOME"
print_summary
exit $?

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

_cap() { # env-prefix... via caller; runs the capture subprocess
  PGC_GUARD_PATH="${PROJECT_ROOT}/hooks/openspec-guard.sh" \
  PGC_PLUGIN_ROOT="${PROJECT_ROOT}" PGC_INPUT='{}' bash "$CAP"
}

# (1) allow-path record: decision=allow, one valid line, coarse label, NO raw command.
PGC_DECISION="allow" PGC_ACTION="push" PGC_COMMAND="git push origin HEAD" \
  PGC_TRANSCRIPT="$HOME/t.jsonl" PGC_SESSION_TOKEN="tok" _cap
assert_file_exists "log created on allow" "$LOG"
assert_equals "one record" "1" "$(wc -l < "$LOG" | tr -d ' ')"
assert_json_valid "record is valid json" "$LOG"
assert_contains "decision allow" '"decision":"allow"' "$(cat "$LOG")"
assert_contains "records guard cksum" '"guard_cksum":' "$(cat "$LOG")"
assert_contains "coarse command_label" '"command_label":"git push"' "$(cat "$LOG")"
assert_contains "raw command empty by default" '"command":""' "$(cat "$LOG")"

# (2) secret safety: raw command NOT logged by default; sha/len present.
: > "$LOG"
PGC_DECISION="allow" PGC_ACTION="push" \
  PGC_COMMAND='GH_TOKEN=supersecret123 gh pr merge 5 --squash' \
  PGC_SESSION_TOKEN="tok" _cap
assert_not_contains "token not logged (default no command)" 'supersecret123' "$(cat "$LOG")"
assert_contains "command_sha present" '"command_sha":' "$(cat "$LOG")"
assert_contains "command_len present" '"command_len":' "$(cat "$LOG")"

# (2b) full-command opt-in redacts env/inline secrets; still no verbatim token.
: > "$LOG"
PGC_DECISION="allow" PGC_ACTION="push" PUSH_GATE_CAPTURE_FULL_CMD=1 \
  PGC_COMMAND='GH_TOKEN=supersecret123 git -c http.extraHeader="Authorization: Bearer tok_abc" push' \
  PGC_SESSION_TOKEN="tok" _cap
assert_contains "full-cmd logs command text" '"command":"' "$(cat "$LOG")"
assert_not_contains "full-cmd redacts env token" 'supersecret123' "$(cat "$LOG")"
assert_not_contains "full-cmd redacts bearer token" 'tok_abc' "$(cat "$LOG")"

# (3) URL-userinfo never logged verbatim (default drops command entirely).
: > "$LOG"
PGC_DECISION="allow" PGC_ACTION="push" \
  PGC_COMMAND='git push https://ghp_tok@github.com/x/y HEAD' PGC_SESSION_TOKEN="tok" _cap
assert_not_contains "url token not logged" 'ghp_tok@' "$(cat "$LOG")"

# (4) fail-open: unwritable log dir -> exit 0, no crash, no stdout.
: > "$LOG"
chmod 000 "$HOME/.claude" 2>/dev/null || true
out="$(PGC_DECISION="allow" PGC_ACTION="push" PGC_COMMAND="git push" \
  PGC_GUARD_PATH="${PROJECT_ROOT}/hooks/openspec-guard.sh" \
  PGC_PLUGIN_ROOT="${PROJECT_ROOT}" PGC_INPUT='{}' bash "$CAP" 2>/dev/null; echo "rc=$?")"
chmod 755 "$HOME/.claude" 2>/dev/null || true
assert_equals "no stdout + exit 0 on unwritable" "rc=0" "$out"

# (4b) log secured 0600 even if it pre-existed 0644.
rm -f "$LOG"; touch "$LOG"; chmod 0644 "$LOG"
PGC_DECISION="allow" PGC_ACTION="push" PGC_COMMAND="git push" PGC_SESSION_TOKEN="tok" _cap
_perms="$(stat -f '%Lp' "$LOG" 2>/dev/null || stat -c '%a' "$LOG" 2>/dev/null)"
assert_equals "log is mode 0600" "600" "${_perms}"

# --- replay classification (issue #127 core value) via stub guards ----------
_stub() { printf '#!/bin/bash\n%s\n' "$2" > "$1"; chmod +x "$1"; }

# (5r) sentinel-only replay => allow (on-disk would allow => drift if live denied).
_stub "$HOME/stub-allow.sh" 'printf "__PGC_EVALUATED__\n"; exit 0'
: > "$LOG"
PGC_DECISION="deny:global-failclosed" PGC_ACTION="push" PGC_COMMAND="git push" \
  PGC_GUARD_PATH="$HOME/stub-allow.sh" PGC_PLUGIN_ROOT="$HOME/none" PGC_INPUT='{}' bash "$CAP"
assert_contains "sentinel replay classified allow" '"ondisk_replay_decision":"allow"' "$(cat "$LOG")"

# (6r) deny-json replay => deny (on-disk agrees).
_stub "$HOME/stub-deny.sh" 'printf "%s\n" "{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\"}}"; exit 0'
: > "$LOG"
PGC_DECISION="deny:global-failclosed" PGC_ACTION="push" PGC_COMMAND="git push" \
  PGC_GUARD_PATH="$HOME/stub-deny.sh" PGC_PLUGIN_ROOT="$HOME/none" PGC_INPUT='{}' bash "$CAP"
assert_contains "deny replay classified deny" '"ondisk_replay_decision":"deny"' "$(cat "$LOG")"

# (7r) empty replay (no sentinel, no deny) => incomplete + capture_error (NOT a false drift signal).
_stub "$HOME/stub-empty.sh" 'exit 0'
: > "$LOG"
PGC_DECISION="deny:global-failclosed" PGC_ACTION="push" PGC_COMMAND="git push" \
  PGC_GUARD_PATH="$HOME/stub-empty.sh" PGC_PLUGIN_ROOT="$HOME/none" PGC_INPUT='{}' bash "$CAP"
assert_contains "empty replay classified incomplete" '"ondisk_replay_decision":"incomplete"' "$(cat "$LOG")"
assert_contains "incomplete sets capture_error" 'replay_incomplete' "$(cat "$LOG")"

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

# (8) deny path: real push, no evidence -> deny + a deny:* record written.
: > "$GLOG" 2>/dev/null || true
out="$(_grun 'git push origin HEAD' '')"
assert_contains "guard still denies" '"deny"' "${out:-<empty>}"
assert_file_exists "capture record written on deny" "$GLOG"
assert_contains "record marks a deny gate" '"decision":"deny:' "$(cat "$GLOG")"

# (9) stdout hygiene: guard stdout is EXACTLY one JSON object (no sentinel/capture leak live).
assert_equals "exactly one json object on stdout" "1" "$(printf '%s' "${out}" | jq -s 'length' 2>/dev/null)"

# (10) allow path via human-bypass env: capture still records, decision=allow.
: > "$GLOG" 2>/dev/null || true
out="$(_grun 'git push origin HEAD' 'ACSM_SKIP_PUSH_GATE=1')"
assert_not_contains "bypass allows (no deny)" '"deny"' "${out:-}"
assert_contains "allow record written" '"decision":"allow"' "$(cat "$GLOG")"

# (11) recursion guard: PUSH_GATE_CAPTURE_DISABLE=1 writes NO record.
: > "$GLOG" 2>/dev/null || true
_grun 'git push origin HEAD' 'PUSH_GATE_CAPTURE_DISABLE=1' >/dev/null
assert_equals "disabled capture writes nothing" "0" "$(wc -l < "$GLOG" 2>/dev/null | tr -d ' ')"

# (11b) GOVERNANCE: the disable flag must NOT weaken enforcement — a no-evidence
# push still DENIES with capture disabled (the flag gates only diagnostics).
out="$(_grun 'git push origin HEAD' 'PUSH_GATE_CAPTURE_DISABLE=1')"
assert_contains "disable flag does not weaken the gate" '"deny"' "${out:-<empty>}"

# (12) non-push git command writes NO record (no overhead/noise).
: > "$GLOG" 2>/dev/null || true
_grun 'git status' '' >/dev/null
assert_equals "non-push writes nothing" "0" "$(wc -l < "$GLOG" 2>/dev/null | tr -d ' ')"

# (13) diagnostic-only: capture script MUST NOT be on the canary manifest.
_hook="${PROJECT_ROOT}/hooks/session-start-hook.sh"
assert_not_contains "capture excluded from _GATE_ENFORCE_LIBS canary" \
  "push-gate-capture" "$(grep '_GATE_ENFORCE_LIBS=' "$_hook")"

export HOME="$_OLDHOME"
print_summary
exit $?

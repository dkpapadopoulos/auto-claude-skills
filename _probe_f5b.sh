#!/usr/bin/env bash
set -u
ROOT="/private/tmp/acs-254-d2"
GUARD="${ROOT}/hooks/openspec-guard.sh"
WIDE="/tmp/guard-widened.sh"
export HOME="$(mktemp -d /tmp/f5b-home-XXXXXX)"; mkdir -p "$HOME/.claude"
TP="$HOME/t.jsonl"; touch "$TP"; TOK="session-t"
COMP="$HOME/.claude/.skill-composition-state-${TOK}"
VERD="$HOME/.claude/.skill-project-verified-${TOK}"
HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"

set_comp() { jq -nc --argjson c '["requesting-code-review","verification-before-completion"]' \
   --argjson d "$1" '{chain:$c,current_index:1,completed:$d}' > "$COMP"; }
mkinput() { jq -n --arg tp "$TP" --arg cmd "git push origin HEAD" \
  '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'; }
run() { mkinput | CLAUDE_PLUGIN_ROOT="$ROOT" bash "$1" 2>/dev/null; }
cls() { case "$1" in *'"deny"'*) printf 'DENY';; '') printf 'EMPTY';; *) printf 'ALLOW';; esac; }
gate() { case "$1" in
    *"verification-before-completion completed before push"*) printf 'chain-verify';;
    *"requesting-code-review completed before"*) printf 'chain-review';;
    *"routing governance"*) printf 'routing-governance';;
    *"fail-closed"*) printf 'global-failclosed';;
    *"failing gate"*) printf 'verify-hardening';;
    *'"deny"'*) printf 'deny-OTHER';; *) printf '-';; esac; }
cell() { printf '  %-52s %-6s %s\n' "$1" "$(cls "$2")" "$(gate "$2")"; }

F5='{"sha":"'"$HEAD_SHA"'","gate_gaming_status":"clean"}'

echo "=== PAIR: F5 (hand-authored 2-field artifact), VERIFY uncredited ==="
set_comp '["requesting-code-review"]'
printf '%s' "$F5" > "$VERD";  cell "widened  + falsifier PRESENT" "$(run "$WIDE")"
rm -f "$VERD";                cell "widened  + falsifier ABSENT " "$(run "$WIDE")"
printf '%s' "$F5" > "$VERD";  cell "current  + falsifier PRESENT" "$(run "$GUARD")"

echo
echo "=== POSITIVE CONTROL: same harness, VERIFY genuinely credited ==="
set_comp '["requesting-code-review","verification-before-completion"]'
rm -f "$VERD";                cell "current  + milestone credited" "$(run "$GUARD")"
                              cell "widened  + milestone credited" "$(run "$WIDE")"

echo
echo "=== Artifact actually written by the real writer, for comparison ==="
set_comp '["requesting-code-review"]'
jq -nc --arg s "$HEAD_SHA" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s,passed:["tests"]}' > "$VERD"
                              cell "widened  + full-shape verdict " "$(run "$WIDE")"
rm -rf "$HOME"

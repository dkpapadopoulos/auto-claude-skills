#!/bin/bash
# Tests hooks/outbound-consent-hook.sh — the ADVISORY observer of cross-family dispatch
# that does NOT go through scripts/consult-dispatch.sh.
#
# Since the egress-consent-dispatcher change the observer no longer judges consent (the
# dispatcher enforces that for panel/second-opinion). It reports and RECORDS dispatch that
# bypasses the dispatcher, so any future deny on bypasses can be earned from a corpus.
# The single most important assertion is still that it NEVER emits a permissionDecision.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
_p(){ PASS=$((PASS+1)); echo "  PASS: $1"; }
_f(){ FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "        got: ${2:-<empty>}"; }
assert_has(){ case "$3" in *"$2"*) _p "$1";; *) _f "$1" "$3";; esac; }
assert_empty(){ if [ -z "$2" ]; then _p "$1"; else _f "$1" "$2"; fi; }
assert_no(){ case "$3" in *"$2"*) _f "$1" "$3";; *) _p "$1";; esac; }
assert_eq(){ if [ "$2" = "$3" ]; then _p "$1"; else _f "$1" "expected '$2', got '$3'"; fi; }

H="$(mktemp -d)"; mkdir -p "$H/.claude/projects/p"
trap 'rm -rf "$H"' EXIT
TP="$H/.claude/projects/p/conv-OBS.jsonl"
# The singleton names ANOTHER conversation; the record must carry the payload's token.
echo "session-FOREIGN" > "$H/.claude/.skill-session-token"
LOG="$H/shadow.jsonl"
run(){ printf '%s' "$1" | HOME="$H" CLAUDE_PLUGIN_ROOT="$ROOT" EGRESS_BYPASS_SHADOW_LOG="$LOG" /bin/bash "$ROOT/hooks/outbound-consent-hook.sh" 2>/dev/null; }
bash_payload(){ jq -nc --arg c "$1" --arg tp "$TP" '{tool_name:"Bash",transcript_path:$tp,agent_id:null,tool_input:{command:$c}}'; }
agent_payload(){ jq -nc --arg s "$1" --arg tp "$TP" --arg p "${2:-x}" '{tool_name:"Agent",transcript_path:$tp,agent_id:null,tool_input:{subagent_type:$s,prompt:$p}}'; }
records(){ [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }

echo "-- test: silence where nothing leaves the machine --"
assert_empty "unrelated Bash is silent" "$(run "$(bash_payload 'ls -la')")"
assert_empty "local subagent mentioning codex is silent" "$(run "$(agent_payload general-purpose 'codex is mentioned here')")"
assert_empty "local subagent mentioning gemini is silent" "$(run "$(agent_payload general-purpose 'discuss the gemini migration')")"
for verb in status result cancel setup --help task-resume-candidate; do
    assert_empty "companion '$verb' (local job state) is silent" \
        "$(run "$(bash_payload "node \"/p/scripts/codex-companion.mjs\" $verb --json")")"
done
assert_empty "reading the companion script is silent" "$(run "$(bash_payload 'cat /p/scripts/codex-companion.mjs')")"
assert_empty "the dispatcher itself is not a bypass" \
    "$(run "$(bash_payload 'bash "/p/scripts/consult-dispatch.sh" send 0123')")"
assert_empty "preparing a codex package is not a bypass" \
    "$(run "$(bash_payload 'bash /p/scripts/consult-dispatch.sh prepare codex /tmp/pkg.md')")"
assert_eq "no records for any of the above" "0" "$(records)"

echo "-- test: bypass dispatch is announced and recorded --"
o="$(run "$(bash_payload 'node "/p/scripts/codex-companion.mjs" task "review this"')")"
assert_has "companion task is announced" "outside scripts/consult-dispatch.sh" "$o"
assert_eq "companion task is recorded once" "1" "$(records)"
rec="$(tail -1 "$LOG")"
assert_eq "record shape names the verb" "bash:companion:task" "$(printf '%s' "$rec" | jq -r .shape)"
assert_eq "record carries the PAYLOAD token, not the singleton" "session-conv-OBS" "$(printf '%s' "$rec" | jq -r .session_token)"
assert_eq "record has schema_version 1" "1" "$(printf '%s' "$rec" | jq -r .schema_version)"
assert_no "record never carries command text" "review this" "$rec"
assert_eq "record is main-thread" "false" "$(printf '%s' "$rec" | jq -r .sidechain)"
assert_eq "shadow log is owner-only" "600" "$(stat -f '%Lp' "$LOG" 2>/dev/null)"

o="$(run "$(agent_payload codex:codex-rescue 'SECRET PROMPT TEXT')")"
assert_has "codex subagent is announced" "outside scripts/consult-dispatch.sh" "$o"
assert_eq "codex subagent shape" "agent:codex:codex-rescue" "$(tail -1 "$LOG" | jq -r .shape)"
assert_no "subagent prompt is never recorded" "SECRET PROMPT" "$(cat "$LOG")"

o="$(run "$(bash_payload 'codex exec -s read-only "hi"')")"
assert_eq "direct codex exec shape" "bash:codex-cli" "$(tail -1 "$LOG" | jq -r .shape)"
o="$(run "$(bash_payload 'node "/p/scripts/codex-companion.mjs" status && codex exec "hi"')")"
assert_eq "a local verb does not hide a codex exec in the same command" "bash:codex-cli" "$(tail -1 "$LOG" | jq -r .shape)"
o="$(run "$(bash_payload 'gemini -p "review this"')")"
assert_eq "gemini CLI shape" "bash:other-vendor" "$(tail -1 "$LOG" | jq -r .shape)"
o="$(run "$(agent_payload gemini-bridge)")"
assert_eq "gemini subagent shape" "agent:gemini-bridge" "$(tail -1 "$LOG" | jq -r .shape)"
o="$(run "$(jq -nc --arg tp "$TP" '{tool_name:"Bash",transcript_path:$tp,agent_id:"agent-7",tool_input:{command:"codex exec hi"}}')")"
assert_eq "sidechain dispatch is marked" "true" "$(tail -1 "$LOG" | jq -r .sidechain)"

echo "-- test: reading the frozen package is normal, not a forgery --"
n0="$(records)"
assert_empty "cat of a frozen package is silent" "$(run "$(bash_payload 'cat ~/.claude/.skill-egress-pkg-session-abc.0123')")"
assert_eq "and not recorded" "$n0" "$(records)"
echo "-- test: glob commands over consent state are still announced --"
assert_has "rm of every egress file is announced" "egress approval records" "$(run "$(bash_payload 'rm -f ~/.claude/.skill-egress-*')")"
assert_has "sed over veto files is announced" "egress approval records" "$(run "$(bash_payload 'sed -i "" s/1/0/ ~/.claude/.skill-egress-v*')")"
assert_empty "a package read next to nothing else stays silent" "$(run "$(bash_payload 'cat ~/.claude/.skill-egress-pkg-a.b && echo done')")"
echo "-- test: control characters never break the observer's JSON --"
o="$(run "$(jq -nc --arg tp "$TP" '{tool_name:"Agent",transcript_path:$tp,agent_id:null,tool_input:{subagent_type:"codex:codex-rescue\t\u0001"}}')")"
assert_eq "message is valid JSON" "ok" "$(printf '%s' "$o" | jq -e . >/dev/null 2>&1 && echo ok || echo broken)"
echo "-- test: a missing token library is announced --"
o="$(printf '%s' "$(agent_payload codex:codex-rescue)" | HOME="$H" CLAUDE_PLUGIN_ROOT="$H/nowhere" EGRESS_BYPASS_SHADOW_LOG="$LOG" /bin/bash "$ROOT/hooks/outbound-consent-hook.sh" 2>/dev/null)"
assert_has "token library missing is announced" "session identity unavailable" "$o"
echo "-- test: direct touches of consent state are announced --"
n0="$(records)"
o="$(run "$(bash_payload 'printf "{}" > ~/.claude/.skill-egress-receipt-session-x.abc.toolu_1')")"
assert_has "writing a receipt path is announced" "egress approval records" "$o"
assert_eq "and recorded" "$((n0 + 1))" "$(records)"
assert_eq "consent-state shape" "bash:consent-state" "$(tail -1 "$LOG" | jq -r .shape)"

echo "-- test: degradation is announced, never silent --"
# Remove ONLY jq (/usr/bin/jq exists on macOS, so PATH=/bin:/usr/bin would keep it).
NOJQ="$H/nojq"; mkdir -p "$NOJQ"
for t in bash cat sed tr date wc tail mv basename dirname head printf; do
    s_="$(command -v "$t" 2>/dev/null)"; [ -n "$s_" ] && [ -x "$s_" ] && ln -sf "$s_" "$NOJQ/$t"
done
WITHJQ="$H/withjq"; cp -R "$NOJQ" "$WITHJQ"; ln -sf "$(command -v jq)" "$WITHJQ/jq"
o="$(printf '%s' "$(agent_payload codex:codex-rescue)" | env PATH="$NOJQ" HOME="$H" CLAUDE_PLUGIN_ROOT="$ROOT" EGRESS_BYPASS_SHADOW_LOG="$LOG" /bin/bash "$ROOT/hooks/outbound-consent-hook.sh" 2>/dev/null)"
assert_has "no jq: announced" "jq unavailable" "$o"
o="$(printf '%s' "$(agent_payload codex:codex-rescue)" | env PATH="$WITHJQ" HOME="$H" CLAUDE_PLUGIN_ROOT="$ROOT" EGRESS_BYPASS_SHADOW_LOG="$LOG" /bin/bash "$ROOT/hooks/outbound-consent-hook.sh" 2>/dev/null)"
assert_has "control: the same shim WITH jq classifies the dispatch" "outside scripts/consult-dispatch.sh" "$o"
o="$(run "$(jq -nc '{tool_name:"Agent",tool_input:{subagent_type:"codex:codex-rescue"}}')")"
assert_has "no transcript_path: still announced" "outside scripts/consult-dispatch.sh" "$o"
assert_eq "no transcript_path: token recorded as null, never the singleton" "null" "$(tail -1 "$LOG" | jq -r .session_token)"
o="$(printf '%s' "$(agent_payload codex:codex-rescue)" | HOME="$H" CLAUDE_PLUGIN_ROOT="$ROOT" EGRESS_BYPASS_SHADOW_LOG="/nonexistent-dir/x.jsonl" /bin/bash "$ROOT/hooks/outbound-consent-hook.sh" 2>/dev/null)"
assert_has "unwritable log: dispatch still announced" "outside scripts/consult-dispatch.sh" "$o"
assert_has "unwritable log: the lost record is announced" "not recorded" "$o"

echo "-- test: the shadow log is bounded --"
jq -nc '{schema_version:1}' > "$LOG"; for i in $(seq 1 2100); do echo '{"schema_version":1}'; done >> "$LOG"
run "$(agent_payload codex:codex-rescue)" >/dev/null
assert_eq "rotated to the last 1000 lines" "1000" "$(records)"

echo "-- test: never a permissionDecision (load-bearing) --"
for payload in "$(agent_payload codex:codex-rescue)" "$(bash_payload 'codex exec hi')" \
               "$(bash_payload 'node codex-companion.mjs task hi')" "$(bash_payload 'cat .skill-egress-receipt-x')"; do
    assert_no "never emits a permissionDecision" "permissionDecision" "$(run "$payload")"
done

echo "-- test: hook is wired for both dispatch shapes --"
W="$(jq -r '[.hooks.PreToolUse[] | select(any(.hooks[]; .command | contains("outbound-consent"))) | .matcher] | join(" ")' "$ROOT/hooks/hooks.json")"
assert_has "wired for Agent/Task" "Task|Agent" "$W"
assert_has "wired for Bash" "Bash" "$W"

echo "=============================="
echo "Tests passed: ${PASS}"
echo "Tests failed: ${FAIL}"
[ "${FAIL}" -eq 0 ] || exit 1
echo "All tests passed."

#!/bin/bash
# Tests hooks/outbound-consent-hook.sh + scripts/record-outbound-consent.sh.
#
# The hook is ADVISORY BY DESIGN: it observes cross-family outbound dispatch and reports
# whether consent was recorded. The single most important assertion here is that it NEVER
# emits a permissionDecision — an advisory that can decide is a bypass waiting to happen.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0
_p(){ PASS=$((PASS+1)); echo "  PASS: $1"; }
_f(){ FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "        got: ${2:-<empty>}"; }
assert_has(){ case "$3" in *"$2"*) _p "$1";; *) _f "$1" "$3";; esac; }
assert_empty(){ if [ -z "$2" ]; then _p "$1"; else _f "$1" "$2"; fi; }
assert_no(){ case "$3" in *"$2"*) _f "$1" "$3";; *) _p "$1";; esac; }

H="$(mktemp -d)"; mkdir -p "$H/.claude"; echo "tok-test" > "$H/.claude/.skill-session-token"
run(){ printf '%s' "$1" | HOME="$H" CLAUDE_PLUGIN_ROOT="$ROOT" /bin/bash "$ROOT/hooks/outbound-consent-hook.sh" 2>/dev/null; }
AGENT='{"tool_name":"Agent","tool_input":{"subagent_type":"codex:codex-rescue","prompt":"x"}}'
BASHC='{"tool_name":"Bash","tool_input":{"command":"node codex-companion.mjs task hi"}}'

echo "-- test: outbound consent observer --"
assert_empty "unrelated Bash is silent" "$(run '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}')"
assert_empty "non-codex subagent is silent" \
  "$(run '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","prompt":"codex is mentioned here"}}' )"
assert_has "codex subagent with no consent is reported" "NO recorded consent" "$(run "$AGENT")"
assert_has "codex CLI via Bash with no consent is reported" "NO recorded consent" "$(run "$BASHC")"

HOME="$H" CLAUDE_PLUGIN_ROOT="$ROOT" /bin/bash "$ROOT/scripts/record-outbound-consent.sh" panel >/dev/null 2>&1
assert_empty "recorded consent silences the observer" "$(run "$AGENT")"

python3 - "$H" <<'PY'
import json,sys,time,os
json.dump({"skill":"panel","ts":int(time.time())-1200},
          open(os.path.join(sys.argv[1],".claude",".skill-outbound-consent-tok-test"),"w"))
PY
assert_has "stale consent is reported" "stale" "$(run "$AGENT")"

echo "not json" > "$H/.claude/.skill-outbound-consent-tok-test"
# A malformed record must read as UNCONSENTED, never as consent. The failure direction
# matters: treating an unparseable record as approval is how a gate goes quietly silent.
assert_has "malformed consent reads as unconsented" "UNCONSENTED" "$(run "$AGENT")"

rm -f "$H/.claude/.skill-session-token" "$H/.claude/.skill-outbound-consent-tok-test"
assert_has "no session token is announced, not silent" "NOT checked" "$(run "$AGENT")"

# THE load-bearing assertion: advisory means advisory.
for payload in "$AGENT" "$BASHC"; do
  assert_no "never emits a permissionDecision" "permissionDecision" "$(run "$payload")"
done
rm -rf "$H"

echo "-- test: the skills tell the model to record consent --"
for f in skills/panel/SKILL.md skills/second-opinion/SKILL.md; do
  assert_has "${f} calls record-outbound-consent.sh" "record-outbound-consent.sh" "$(cat "$ROOT/$f")"
done
echo "-- test: hook is wired for both dispatch shapes --"
W="$(python3 -c "
import json;d=json.load(open('$ROOT/hooks/hooks.json'))
print(' '.join(e.get('matcher','') for e in d['hooks']['PreToolUse']
      for h in e.get('hooks',[]) if 'outbound-consent' in h.get('command','')))")"
assert_has "wired for Agent/Task" "Task|Agent" "$W"
assert_has "wired for Bash" "Bash" "$W"

echo "=============================="
echo "Tests passed: ${PASS}"
echo "Tests failed: ${FAIL}"
[ "${FAIL}" -eq 0 ] || exit 1
echo "All tests passed."

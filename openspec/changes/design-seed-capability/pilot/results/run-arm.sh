#!/usr/bin/env bash
# Run ONE pilot arm as a headless session in its own worktree.
#
# Headless, not a subagent: the worktree's PreToolUse deny hook — the arms' capability
# boundary — is INERT for a subagent, because that worktree's .claude/settings.json is
# never loaded for an agent belonging to another session. Measured; see
# pre-launch-measurements.md M1.
#
# --settings disables every user-level plugin. With them loaded, the auto-claude-skills
# UserPromptSubmit hook injects "DESIGN SEED: ... adopt the shipped styleguide seed"
# into EVERY arm prompt, including the control's. M2/M3.
#
# Budget (pilot/budget.md): 60 tool calls, 45 minutes, no retry. The CLI has no
# --max-turns, so the cap is counted here from the event stream. budget.md says "work in
# progress at the cap is submitted as-is", which is why stopping is the right action.
set -uo pipefail
WT="$1"; PROMPT_FILE="$2"; OUT="$3"; MODEL="$4"; SETTINGS="$5"
CAP_CALLS=60
CAP_SECS=2700
mkdir -p "$OUT"
START=$(date +%s)
cd "$WT" || exit 1
claude -p "$(cat "$PROMPT_FILE")" \
    --model "$MODEL" \
    --settings "$SETTINGS" \
    --permission-mode bypassPermissions \
    --output-format stream-json --verbose \
    > "$OUT/stream.jsonl" 2> "$OUT/stderr.log" &
CPID=$!
STOP="completed"
while kill -0 "$CPID" 2>/dev/null; do
    ELAPSED=$(( $(date +%s) - START ))
    CALLS=$(grep -c '"type":"tool_use"' "$OUT/stream.jsonl" 2>/dev/null)
    CALLS=${CALLS:-0}
    if [ "$CALLS" -ge "$CAP_CALLS" ]; then STOP="cap:tool-calls"; kill "$CPID" 2>/dev/null; break; fi
    if [ "$ELAPSED" -ge "$CAP_SECS" ]; then STOP="cap:wall-clock"; kill "$CPID" 2>/dev/null; break; fi
    sleep 5
done
wait "$CPID" 2>/dev/null
END=$(date +%s)
CALLS=$(grep -c '"type":"tool_use"' "$OUT/stream.jsonl" 2>/dev/null); CALLS=${CALLS:-0}
# Recorded as an OBSERVED variable, never assumed: "0 skill invocations" in a pre-launch
# probe is one draw from a stochastic process, not a property of the configuration.
SKILLS=$(grep -c '"skill":' "$OUT/stream.jsonl" 2>/dev/null); SKILLS=${SKILLS:-0}
{
  echo "worktree:          $WT"
  echo "model:             $MODEL"
  echo "settings:          $SETTINGS"
  echo "prompt_sha256:     $(shasum -a 256 "$PROMPT_FILE" | cut -d' ' -f1)"
  echo "stop_reason:       $STOP"
  echo "tool_calls:        $CALLS (cap $CAP_CALLS)"
  echo "skill_invocations: $SKILLS (observed, not assumed)"
  echo "wall_clock:        $(( END - START ))s (cap ${CAP_SECS}s)"
  echo "started_utc:       $(date -u -r "$START" +%Y-%m-%dT%H:%M:%SZ)"
  echo "ended_utc:         $(date -u -r "$END" +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/consumption.txt"
cat "$OUT/consumption.txt"

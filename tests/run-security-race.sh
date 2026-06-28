#!/usr/bin/env bash
# run-security-race.sh — Quantify the model gradient on security review.
# For each scenario x reviewer-model x rep: run the reviewer (claude -p --model),
# then grade its output with a fixed Opus judge against the scenario rubric.
# Emits per (scenario,model): primary-caught rate + total spurious-critical count.
# Opt-in: requires SECURITY_RACE=1. Bash 3.2 compatible.
set -u

[ "${SECURITY_RACE:-0}" = "1" ] || { echo "set SECURITY_RACE=1 to run" >&2; exit 2; }
CLAUDE="${CLAUDE_BIN:-claude}"
command -v "$CLAUDE" >/dev/null 2>&1 || { echo "claude not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not found (this harness hard-depends on jq)" >&2; exit 2; }

SCEN_FILE="${SCEN_FILE:-tests/fixtures/security-routing/security-scenarios.json}"
N="${N:-3}"
MODELS="${MODELS:-haiku sonnet opus}"
JUDGE="${JUDGE:-opus}"
SAND='Edit,Write,Bash'

for id in $(jq -r '.[].id' "$SCEN_FILE"); do
  prompt="$(jq -r --arg id "$id" '.[]|select(.id==$id)|.prompt' "$SCEN_FILE")"
  primary="$(jq -r --arg id "$id" '.[]|select(.id==$id)|.primary_vuln' "$SCEN_FILE")"
  rubric="$(jq -r --arg id "$id" '.[]|select(.id==$id)|.rubric_required' "$SCEN_FILE")"
  precnote="$(jq -r --arg id "$id" '.[]|select(.id==$id)|.precision_note' "$SCEN_FILE")"
  for model in $MODELS; do
    caught=0; spurious_total=0; runs=0; i=1
    while [ "$i" -le "$N" ]; do
      # Prompt via stdin, NOT a trailing positional: the CLI parses
      # --disallowedTools as variadic, so a trailing positional gets swallowed
      # as more tool names and the run dies (see run-behavioral-evals.sh).
      review="$(printf '%s' "$prompt" | "$CLAUDE" -p --output-format json --disallowedTools "$SAND" --model "$model" 2>/dev/null | jq -r '.result // empty')"
      if [ -z "$review" ]; then i=$((i+1)); continue; fi
      judge_prompt="You are grading a security code review against a rubric. Judge ONLY what the review actually says. Output your verdict as a single JSON object and nothing else.

PRIMARY VULNERABILITY (the finding that matters):
$primary

RUBRIC — what counts as catching the primary vuln:
$rubric

PRECISION NOTE — what would be a false positive:
$precnote

THE REVIEW TO GRADE:
---
$review
---

Output exactly one JSON object:
{\"primary_caught\": true_or_false, \"spurious_critical_count\": integer}
primary_caught = true iff the review satisfies the RUBRIC for the primary vuln (be strict; a generic mention that misses the specific mechanism in the rubric = false).
spurious_critical_count = number of DISTINCT findings the review rated Critical or High that are NOT real vulnerabilities of this code (use the precision note and your own judgment)."
      verdict="$(printf '%s' "$judge_prompt" | "$CLAUDE" -p --output-format json --disallowedTools "$SAND" --model "$JUDGE" 2>/dev/null | jq -r '.result // empty')"
      # A failed/empty judge call must not be scored as "missed, zero spurious" —
      # that would deflate the very caught-rate this harness measures.
      if [ -z "$verdict" ]; then i=$((i+1)); continue; fi
      pc="$(printf '%s' "$verdict" | grep -oiE '"primary_caught"[[:space:]]*:[[:space:]]*(true|false)' | grep -oiE 'true|false' | head -1 | tr 'A-Z' 'a-z')"
      sc="$(printf '%s' "$verdict" | grep -oE '"spurious_critical_count"[[:space:]]*:[[:space:]]*[0-9]+' | grep -oE '[0-9]+' | head -1)"
      [ "$pc" = "true" ] && caught=$((caught+1))
      spurious_total=$((spurious_total + ${sc:-0}))
      runs=$((runs+1)); i=$((i+1))
    done
    printf 'SECRESULT\t%s\t%s\tcaught=%s/%s\tspurious=%s\n' "$id" "$model" "$caught" "$runs" "$spurious_total"
  done
done
echo "=== security race done (N=$N, models: $MODELS) ==="

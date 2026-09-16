#!/bin/bash
# Consultation-versus-development discrimination (contracts C2/C3).
#
# A consultation request must not START an unrelated development workflow, must not
# DISTURB one already in progress, and must not be mistaken for development work.
# Equally, a development request -- and a MIXED request that asks for consultation AND
# for work to follow -- must keep its workflow. Suppressing the chain outright was
# rejected in design.md precisely because it strands a development session that pauses
# to consult.
#
# PROMPTS HERE ARE DEVELOPMENT DATA, authored alongside the implementation. The 50
# held-out prompts in tests/probes/consultation-acceptance/cases.json are deliberately
# NOT used: tuning against them would destroy the only independent acceptance evidence
# this change has.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="${ROOT}/hooks/skill-activation-hook.sh"
PASS=0; FAIL=0

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not available — consultation routing NOT checked"; exit 0
fi
# Without this guard a missing interpreter is indistinguishable from a routing
# regression: _new_home's registry write fails, no prompt anchors a chain, the three
# C3 cells pass and the two development controls fail. The suite would report a
# routing defect for a missing tool.
if ! command -v python3 >/dev/null 2>&1; then
  echo "SKIP: python3 not available — consultation routing NOT checked"; exit 0
fi

_pass() { PASS=$((PASS+1)); echo "  PASS: $1"; }
_fail() { FAIL=$((FAIL+1)); echo "  FAIL: $1"; echo "        $2"; }

# Fresh isolated HOME with every skill available, so a miss is a routing decision and
# not an install gap.
_new_home() {
  local h; h="$(mktemp -d)"; mkdir -p "$h/.claude"
  python3 - "$ROOT" "$h" <<'PY'
import json, sys
reg = json.load(open(sys.argv[1] + "/config/default-triggers.json"))
for s in reg["skills"]:
    s.update(available=True, enabled=True)
open(sys.argv[2] + "/.claude/.skill-registry-cache.json", "w").write(json.dumps(reg))
PY
  printf '%s' "$h"
}

# Runs the REAL hook. Prints nothing; state is inspected by the caller.
_turn() {  # $1=home $2=prompt
  jq -nc --arg p "$2" --arg t "$1/.claude/audit.jsonl" \
     '{prompt:$p, transcript_path:$t}' \
  | HOME="$1" CLAUDE_PLUGIN_ROOT="$ROOT" bash "$HOOK" 2>/dev/null
}

_chain_len() {  # $1=home
  local f; f="$(ls "$1"/.claude/.skill-composition-state-* 2>/dev/null | head -1)"
  [ -n "$f" ] || { printf '0'; return; }
  jq -r '(.chain // []) | length' "$f" 2>/dev/null || printf '0'
}

_completed() {  # $1=home
  local f; f="$(ls "$1"/.claude/.skill-composition-state-* 2>/dev/null | head -1)"
  [ -n "$f" ] || { printf '[]'; return; }
  jq -c '(.completed // [])' "$f" 2>/dev/null || printf '[]'
}

echo "== C3: a consultation-only request RENDERS no development workflow =="
# The contract is about what is RENDERED. Asserting instead that no chain STATE exists
# is the mistake this block was first written with, and it is not a weaker test -- it is
# a test for the wrong thing, because absent chain state is precisely what disarms the
# push gate: openspec-guard.sh gates its whole chain block on that file existing, so
# "no state" means deny:chain-review and deny:chain-verify never run. Measured: a push
# after "commit and push this, but ask codex first" went DENY -> allow under the
# state-suppressing version. Assert the render; assert the state SURVIVES separately.
for p in "ask codex to weigh in on this approach" \
         "get a second opinion from one other model on this schema design" \
         "debate this with another model and show me where they land"; do
  H="$(_new_home)"; out="$(_turn "$H" "$p")"
  if printf '%s' "$out" | grep -q "Composition:"; then
    _fail "no chain rendered: ${p:0:40}" "a Composition: line was rendered"
  else _pass "no chain rendered: ${p:0:40}"; fi
  # Non-empty output, so a crashed hook cannot satisfy the assertion above. Every
  # prompt in this loop must route SOMETHING, or the cell is indistinguishable from a
  # hook that died before rendering anything.
  if [ -n "$out" ]; then _pass "still routed: ${p:0:40}"
  else _fail "still routed: ${p:0:40}" "stdout was empty (hook died?)"; fi
  rm -rf "$H"
done

echo "== C3: the chain STATE survives, so the push gate keeps its evidence =="
H="$(_new_home)"; _turn "$H" "ask codex to weigh in on this approach" >/dev/null
n="$(_chain_len "$H")"
if [ "$n" -gt 0 ]; then _pass "composition state still written (${n} steps)"
else _fail "composition state still written" \
     "no state file: openspec-guard.sh would skip deny:chain-review AND deny:chain-verify"; fi
rm -rf "$H"

echo "== the hook still ROUTES a consultation prompt; it just starts no workflow =="
# "No chain was started" is satisfied just as well by a hook that CRASHED as by one
# that deliberately skipped the walk -- and the first cut of this guard did crash, on
# an unbound COMPOSITION_CHAIN under `set -u`, emitting nothing at all. Every cell
# above passed against it. Assert the output is non-empty and carries no chain line,
# so the two outcomes can be told apart.
H="$(_new_home)"
out="$(_turn "$H" "ask codex to weigh in on this approach")"
if [ -n "$out" ]; then _pass "consultation prompt still produces hook output"
else _fail "consultation prompt still produces hook output" "stdout was empty (hook died?)"; fi
if printf '%s' "$out" | grep -q "Composition:"; then
  _fail "output carries no composition chain" "a Composition: line was rendered"
else _pass "output carries no composition chain"; fi
rm -rf "$H"

echo "== control: a development request still starts its workflow =="
for p in "add retry handling to the ingest worker" \
         "let's design and build a new caching layer"; do
  H="$(_new_home)"; _turn "$H" "$p" >/dev/null
  n="$(_chain_len "$H")"
  if [ "$n" -gt 0 ]; then _pass "chain started: ${p:0:40}"
  else _fail "chain started: ${p:0:40}" "no chain was started"; fi
  rm -rf "$H"
done

echo "== control: a MIXED request keeps its workflow =="
# design.md is explicit that chain suppression must NOT apply to a request that asks
# for consultation AND for development work to follow.
for p in "ask codex what it thinks, then implement whichever approach we settle on" \
         "get another model's view on the retry design and then write the code"; do
  H="$(_new_home)"; _turn "$H" "$p" >/dev/null
  n="$(_chain_len "$H")"
  if [ "$n" -gt 0 ]; then _pass "mixed keeps chain: ${p:0:38}"
  else _fail "mixed keeps chain: ${p:0:38}" "the chain was suppressed on a mixed request"; fi
  rm -rf "$H"
done

echo "== C3: a consultation detour preserves an ACTIVE workflow, and credits nothing =="
H="$(_new_home)"
_turn "$H" "let's design and build a new caching layer" >/dev/null
before_len="$(_chain_len "$H")"; before_done="$(_completed "$H")"
_turn "$H" "ask codex to weigh in on this approach" >/dev/null
after_len="$(_chain_len "$H")"; after_done="$(_completed "$H")"
if [ "$after_len" -eq "$before_len" ] && [ "$after_len" -gt 0 ]; then
  _pass "active chain survives the detour (${after_len} steps)"
else
  _fail "active chain survives the detour" "was ${before_len}, now ${after_len}"
fi
# KNOWN AND ACCEPTED, asserted so it cannot change silently: the detour DOES credit
# chain progress it did not make, because the walker still runs. An earlier version
# suppressed the walk to prevent exactly this, and that bought the fabrication fix at
# the price of a push-gate bypass -- no state file means openspec-guard.sh skips its
# chain checks entirely. Of the two, a fabricated `.completed` entry is the safe one:
# gating milestones (requesting-code-review, verification-before-completion) are
# excluded from the walker's computed prefix, so this cannot manufacture gate evidence,
# and it errs toward the gate firing. Fixing the fabrication properly means suppressing
# the credit WITHOUT suppressing the write, which is a separate change.
if [ "$after_done" != "$before_done" ]; then
  _pass "detour credits progress (${before_done} -> ${after_done}) -- known, and not gate evidence"
else
  _pass "detour credited nothing (${after_done})"
fi
# The half that must never regress: no GATING milestone may appear from a detour.
if printf '%s' "$after_done" | grep -qE "requesting-code-review|verification-before-completion"; then
  _fail "detour fabricates no gating milestone" "completed contains a gating milestone: ${after_done}"
else
  _pass "detour fabricates no gating milestone"
fi
# ...and the original chain still resumes afterwards.
_turn "$H" "ok keep going" >/dev/null
if [ "$(_chain_len "$H")" -eq "$before_len" ]; then
  _pass "continuation resumes the original chain"
else
  _fail "continuation resumes the original chain" "chain is now $(_chain_len "$H") steps"
fi
rm -rf "$H"

echo ""

# --- consult-participant boundary must match the trigger boundary (PR #253 rec 2) ---
test_consult_boundary_excludes_identifiers() {
    echo "-- test: vendor names inside identifiers do not suppress the chain --"
    local cp
    cp="$(grep '_CONSULT_PARTICIPANT=' "${ROOT}/hooks/skill-activation-hook.sh" \
          | sed "s/^_CONSULT_PARTICIPANT='//; s/'$//")"
    # A bare [^a-z] right boundary matched inside identifiers, so "make the client
    # o3-compatible" read as consultation and SUPPRESSED the composition chain display
    # while a plain dev prompt rendered it. Display-only, but wrong; the boundary now
    # matches the trigger regexes' ($|[^a-z0-9_.-]).
    local p
    for p in "make the client o3-compatible" "bump the gpt-4-turbo timeout in the config" \
             "put the config into gemini-adapter.json"; do
        if [[ "${p}" =~ ${cp} ]]; then _fail "identifier not treated as consultation: ${p}"
        else _pass "identifier not treated as consultation: ${p}"; fi
    done
    # ...and genuine consultation still matches, or the veto has simply been disabled.
    for p in "ask codex for a second opinion on this" "get another model to critique this"; do
        if [[ "${p}" =~ ${cp} ]]; then _pass "genuine consultation still matches: ${p}"
        else _fail "genuine consultation still matches: ${p}"; fi
    done
}
test_consult_boundary_excludes_identifiers

echo "test-consultation-routing: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]

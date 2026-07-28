#!/bin/bash
# test-shadow-adjudicate.sh — C2 adjudication tool.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/shadow-adjudicate.sh"
PASS=0; FAIL=0
ok()   { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
bad()  { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1"; echo "        expected: $2"; echo "        actual:   $3"; }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }

echo "=== test-shadow-adjudicate.sh ==="

# --- Task 1: band arithmetic (exact Clopper-Pearson) ---
band() { ( . "$SCRIPT" --source-only; _band "$1" "$2" ); }

eq "0/29 clears the DENY floor"        "DENY"          "$(band 0 29)"
eq "0/28 does NOT clear it"            "NARROWED"      "$(band 0 28)"
eq "9/23 is ADVISORY-ONLY"             "ADVISORY-ONLY" "$(band 9 23)"
eq "8/23 is NARROWED, not advisory"    "NARROWED"      "$(band 8 23)"
eq "5/23 is NARROWED"                  "NARROWED"      "$(band 5 23)"
eq "empty corpus is INSUFFICIENT"      "INSUFFICIENT"  "$(band 0 0)"

# --- Task 2: episode grouping ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export IMPLEMENT_SHADOW_LOG="$TMP/shadow.jsonl"
export IMPLEMENT_ADJUDICATION_LOG="$TMP/adj.jsonl"

rec() { # rec <id> <ts> <repo> <branch> <token> [pv]
  printf '{"record_id":"%s","ts":"%s","repo":"%s","branch":"%s","session_token":"%s","predicate_version":%s,"action":"push","diff_base":"branch-local","impl_in_chain":true,"material_source":true,"impl_evidence_kind":"none","transcript_path":"/tmp/t.jsonl","gate":"push-implement","would_block":true,"schema_version":1}\n' \
    "$1" "$2" "$3" "$4" "$5" "${6:-2}" >> "$IMPLEMENT_SHADOW_LOG"
}
episodes() { ( . "$SCRIPT" --source-only; _episodes ); }

# the real v1 burst shape: 11 records, one repo+branch+token, 9-minute window
: > "$IMPLEMENT_SHADOW_LOG"
i=0
while [ "$i" -lt 11 ]; do
  rec "r$i" "2026-07-28T07:4$(( i % 10 )):08Z" "/repo/A" "feat/x" "tok1"
  i=$(( i + 1 ))
done
eq "an 11-record retry burst is ONE episode" "1" "$(episodes | wc -l | tr -d ' ')"

# anchored window: 0min, 25min, 35min -> 2 episodes (35 is outside 30 of the FIRST)
: > "$IMPLEMENT_SHADOW_LOG"
rec a "2026-07-28T10:00:00Z" "/repo/A" "feat/x" "tok1"
rec b "2026-07-28T10:25:00Z" "/repo/A" "feat/x" "tok1"
rec c "2026-07-28T10:35:00Z" "/repo/A" "feat/x" "tok1"
eq "window is anchored at first record, not rolling" "2" "$(episodes | wc -l | tr -d ' ')"

# different session tokens never merge
: > "$IMPLEMENT_SHADOW_LOG"
rec d "2026-07-28T10:00:00Z" "/repo/A" "feat/x" "tok1"
rec e "2026-07-28T10:01:00Z" "/repo/A" "feat/x" "tok2"
eq "distinct session tokens are distinct episodes" "2" "$(episodes | wc -l | tr -d ' ')"

# v1 records are excluded entirely
: > "$IMPLEMENT_SHADOW_LOG"
rec f "2026-07-28T10:00:00Z" "/repo/A" "feat/x" "tok1" 1
eq "v1 records are not episodes" "0" "$(episodes | wc -l | tr -d ' ')"

# --- Task 3: adjudication write ---
adj() { ( unset CLAUDECODE; "$SCRIPT" "$1" --verdict "$2" --reason "$3" >/dev/null 2>&1; echo $?; ); }

: > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"
rec g "2026-07-28T10:00:00Z" "/repo/A" "feat/x" "tok1"
rec h "2026-07-28T10:00:00Z" "/repo/B" "feat/y" "tok2" 1
BEFORE="$(cksum < "$IMPLEMENT_SHADOW_LOG")"

eq "adjudicating a v2 record succeeds" "0" "$(adj g true_catch 'resolved by attest')"
eq "one adjudication was appended"     "1" "$(wc -l < "$IMPLEMENT_ADJUDICATION_LOG" | tr -d ' ')"
eq "shadow log is untouched"           "$BEFORE" "$(cksum < "$IMPLEMENT_SHADOW_LOG")"
eq "verdict was recorded"              "true_catch" "$(jq -r '.verdict' "$IMPLEMENT_ADJUDICATION_LOG")"
eq "a v1 record is refused"            "1" "$(adj h true_catch 'nope')"
eq "refusal wrote nothing"             "1" "$(wc -l < "$IMPLEMENT_ADJUDICATION_LOG" | tr -d ' ')"
eq "an unknown record id is refused"   "1" "$(adj nosuch true_catch 'nope')"
eq "an invalid verdict is refused"     "1" "$(adj g bogus_verdict 'nope')"

: > "$IMPLEMENT_ADJUDICATION_LOG"
CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason "agent run" >/dev/null 2>&1
eq "CLAUDECODE marks the claimant agent" "agent" "$(jq -r '.claimant' "$IMPLEMENT_ADJUDICATION_LOG")"
eq "provenance records agent_env"        "present" "$(jq -r '.provenance.agent_env' "$IMPLEMENT_ADJUDICATION_LOG")"
# The output must DISCLAIM verification, not merely avoid the word: an earlier
# version of this test grepped for 'human-verified' expecting zero hits, which
# the correct disclaimer ("not human-verified") also fails. Assert both halves.
eq "output carries the human-claimed label" "1" \
   "$(CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason x 2>&1 | grep -ci 'HUMAN-CLAIMED')"
eq "output disclaims verification"          "1" \
   "$(CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason x 2>&1 | grep -ci 'not human-verified')"
eq "agent runs say they are excluded"       "1" \
   "$(CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason x 2>&1 | grep -ci 'excluded from the rate')"

# --- Task 4: --next ---
: > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"
rec old "2026-07-28T09:00:00Z" "/repo/A" "feat/x" "tok1"
rec new "2026-07-28T11:00:00Z" "/repo/B" "feat/y" "tok2"
CLAUDECODE=1 "$SCRIPT" new --verdict true_catch --reason seen >/dev/null 2>&1
ADJ_BEFORE="$(cksum < "$IMPLEMENT_ADJUDICATION_LOG")"

eq "next surfaces the oldest unadjudicated" "1" "$("$SCRIPT" --next 2>&1 | grep -c '^old ')"
eq "next includes the transcript pointer"   "1" "$("$SCRIPT" --next 2>&1 | grep -c '/tmp/t.jsonl')"
eq "next shows why the leg fired"           "1" "$("$SCRIPT" --next 2>&1 | grep -ci 'material_source')"
eq "next does not modify the sidecar"       "$ADJ_BEFORE" "$(cksum < "$IMPLEMENT_ADJUDICATION_LOG")"
eq "next exits 0"                           "0" "$("$SCRIPT" --next >/dev/null 2>&1; echo $?)"

CLAUDECODE=1 "$SCRIPT" old --verdict unknown --reason seen >/dev/null 2>&1
eq "fully adjudicated corpus reports done"  "1" "$("$SCRIPT" --next 2>&1 | grep -ci 'nothing outstanding')"
eq "and still exits 0"                      "0" "$("$SCRIPT" --next >/dev/null 2>&1; echo $?)"

# --- Task 5: --status ---
seed()  { : > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"; }
mkrec() { rec "$1" "2026-07-28T$2:00Z" "$3" "br-$1" "tok-$1"; }
label() { ( unset CLAUDECODE; "$SCRIPT" "$1" --verdict "$2" --reason t >/dev/null 2>&1 ); }
status() { "$SCRIPT" --status 2>&1; }

# floor: 3 clean episodes in 1 repo must NOT print a rate
seed
mkrec e1 "10:01" /repo/A; mkrec e2 "10:02" /repo/A; mkrec e3 "10:03" /repo/A
label e1 true_catch; label e2 true_catch; label e3 true_catch
eq "below the floor prints insufficient data" "1" "$(status | grep -ci 'insufficient data')"
eq "and prints no percentage rate"            "0" "$(status | grep -c '%')"
eq "and names the 29-episode floor"           "1" "$(status | grep -c '29')"

# worst-verdict-wins within one episode
seed
rec m1 "2026-07-28T10:00:00Z" /repo/A feat/x tok1
rec m2 "2026-07-28T10:05:00Z" /repo/A feat/x tok1
label m1 true_catch; label m2 false_block
eq "the two records form one episode" "1" "$(( $(status | grep -E '^  episodes' | awk '{print $2}') ))"
eq "a mixed episode resolves false_block" "1" "$(status | grep -E '^  false_block' | awk '{print $2}')"
eq "and does not also count as true_catch" "0" "$(status | grep -E '^  true_catch' | awk '{print $2}')"

# agent-claimed is segregated, then re-included by a human adjudication
seed
mkrec a1 "10:01" /repo/A
CLAUDECODE=1 "$SCRIPT" a1 --verdict true_catch --reason t >/dev/null 2>&1
eq "agent-claimed episode is excluded" "1" "$(status | grep -E '^  agent-claimed' | awk '{print $2}')"
eq "and is not counted as adjudicated" "0" "$(status | grep -E '^  adjudicated' | awk '{print $2}')"
label a1 true_catch
eq "human re-confirmation counts it"   "1" "$(status | grep -E '^  adjudicated' | awk '{print $2}')"

# repos are listed, not merely counted
seed
mkrec p1 "10:01" /repo/A; mkrec p2 "10:02" /repo/B
label p1 true_catch; label p2 true_catch
eq "status lists contributing repos" "1" "$(status | grep -c '/repo/B')"

# v1 records are reported but excluded
seed
mkrec q1 "10:01" /repo/A
rec q2 "2026-07-28T10:02:00Z" /repo/A feat/z tokz 1
label q1 true_catch
eq "v1 records are reported separately" "1" "$(status | grep -E '^  v1 records' | awk '{print $3}')"

# posture
eq "status disclaims enforcement"       "1" "$(status | grep -ci 'informational only')"
eq "status exits 0 on an empty corpus"  "0" "$(seed; "$SCRIPT" --status >/dev/null 2>&1; echo $?)"

# --- Task 6: the tool must never become a gate component ---
# These pin properties, not behaviour. If one fails, the implementation drifted
# into the enforcement path and the IMPLEMENTATION must be fixed, not the test.
# `grep -c` prints "0" AND exits 1 on no-match, so a `|| echo 0` fallback emits
# TWO lines. Count via a helper that distinguishes no-match from missing-file.
count() { local n; n="$(grep -cE "$1" "$2" 2>/dev/null)"; [ -n "$n" ] || n=0; echo "$n"; }

eq "not in the gate-enforcement canary list" "0" \
   "$(count 'shadow-adjudicate' "$ROOT/hooks/session-start-hook.sh")"
eq "not sourced by the push guard"           "0" \
   "$(count 'shadow-adjudicate' "$ROOT/hooks/openspec-guard.sh")"
eq "never emits a permissionDecision"        "0" \
   "$(grep -c 'permissionDecision' "$SCRIPT")"
eq "never uses set -e"                       "0" \
   "$(grep -cE '^[[:space:]]*set -e' "$SCRIPT")"
eq "never writes the shadow log"             "0" \
   "$(grep -cE '>[>]?[[:space:]]*"\$\{SHADOW_LOG\}"' "$SCRIPT")"
eq "never reads stdin"                       "0" \
   "$(grep -cE '^[[:space:]]*(read|cat)[[:space:]]*$' "$SCRIPT")"

echo
echo "Tests run: $(( PASS + FAIL ))  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1

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

echo
echo "Tests run: $(( PASS + FAIL ))  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1

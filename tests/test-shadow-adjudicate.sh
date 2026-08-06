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

# --- episode edge cases ---
: > "$IMPLEMENT_SHADOW_LOG"; rec s1 "2026-07-28T10:00:00Z" "/repo/A" "b" "t"
eq "a single record is one episode" "1" "$(episodes | wc -l | tr -d ' ')"

# window boundary: 1800s is inside (not > w), 1801s is outside
: > "$IMPLEMENT_SHADOW_LOG"
rec w1 "2026-07-28T10:00:00Z" "/repo/A" "b" "t"; rec w2 "2026-07-28T10:30:00Z" "/repo/A" "b" "t"
eq "exactly 1800s stays in the episode" "1" "$(episodes | wc -l | tr -d ' ')"
: > "$IMPLEMENT_SHADOW_LOG"
rec w3 "2026-07-28T10:00:00Z" "/repo/A" "b" "t"; rec w4 "2026-07-28T10:30:01Z" "/repo/A" "b" "t"
eq "1801s starts a new episode" "2" "$(episodes | wc -l | tr -d ' ')"

# Malformed timestamps are EXCLUDED from episodes, not merged. _iso_epoch
# returns -1 for every unparseable value, so two corrupt records sharing a key
# satisfy (-1)-(-1)=0 <= window and would collapse into one episode on a time
# relation nothing verified. Excluding stops corrupt data moving the denominator
# in either direction.
: > "$IMPLEMENT_SHADOW_LOG"
rec g1 "garbage" "/repo/A" "b1" "t1"; rec g2 "also-garbage" "/repo/A" "b2" "t2"
eq "malformed ts on distinct branches are excluded" "0" "$(episodes | wc -l | tr -d ' ')"
: > "$IMPLEMENT_SHADOW_LOG"
rec g3 "garbage" "/repo/A" "b1" "t1"; rec g4 "garbage" "/repo/A" "b1" "t1"
eq "SAME-key malformed ts do not merge into an episode" "0" "$(episodes | wc -l | tr -d ' ')"
# and a malformed record must not contaminate a valid neighbour
: > "$IMPLEMENT_SHADOW_LOG"
rec v9 "2026-07-28T10:00:00Z" "/repo/A" "b1" "t1"; rec g5 "garbage" "/repo/A" "b1" "t1"
eq "a valid record survives alongside a malformed one" "1" "$(episodes | wc -l | tr -d ' ')"
eq "and the episode contains ONLY the valid record" "v9" "$(episodes | cut -f5)"

# --- C1 regression: an EMPTY field must not drop the record ---
# `IFS=$'\t' read` treats tab as IFS whitespace, so consecutive tabs collapse and
# every field after an empty one shifts left, dropping the record entirely.
# implement-shadow.sh writes branch="" whenever `git rev-parse --abbrev-ref HEAD`
# fails, so this is a shape the guard really produces.
jrecf() { # jrecf <id> <branch> <token>
  jq -cn --arg id "$1" --arg br "$2" --arg tok "$3" \
    '{record_id:$id,ts:"2026-07-28T10:00:00Z",repo:"/repo/A",branch:$br,
      session_token:$tok,predicate_version:2,action:"push",diff_base:"branch-local",
      impl_in_chain:true,material_source:true,impl_evidence_kind:"none",
      transcript_path:"/tmp/t.jsonl",gate:"push-implement",would_block:true,
      schema_version:1}' >> "$IMPLEMENT_SHADOW_LOG"
}
: > "$IMPLEMENT_SHADOW_LOG"; jrecf n1 "" tokA; jrecf n2 "" tokB
eq "records with an EMPTY branch still count"        "2" "$(episodes | wc -l | tr -d ' ')"
: > "$IMPLEMENT_SHADOW_LOG"; jrecf n3 "feat/x" ""
eq "a record with an EMPTY session_token counts"     "1" "$(episodes | wc -l | tr -d ' ')"
# and --next must not mis-render: transcript_path is the spec-mandated pointer
: > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"; jrecf n4 "" tokC
eq "--next keeps the transcript pointer with an empty field" "1" \
   "$("$SCRIPT" --next 2>&1 | grep -c '^  read    /tmp/t.jsonl$')"
eq "--next does not shift action into branch"        "1" \
   "$("$SCRIPT" --next 2>&1 | grep -c '^  action  push')"

# --- I1 regression: one unparseable line must not truncate the corpus ---
: > "$IMPLEMENT_SHADOW_LOG"
jrecf p1 b1 t1; printf '{"truncated": \n' >> "$IMPLEMENT_SHADOW_LOG"; jrecf p2 b2 t2; jrecf p3 b3 t3
eq "a malformed line does not truncate the read" "3" "$(episodes | wc -l | tr -d ' ')"
eq "and unparseable lines are reported"          "1" \
   "$("$SCRIPT" --status 2>&1 | grep -E '^  unparseable lines' | awk '{print $3}')"

# --- I2 regression: a null/missing ts must be COUNTED, not silently dropped ---
# `null | test(...)` is a jq runtime error; jq then skips that input, so the
# record was excluded from episodes AND contributed 0 to the malformed count.
: > "$IMPLEMENT_SHADOW_LOG"; jrecf q1 b1 t1
jq -cn '{record_id:"nots",repo:"/repo/A",branch:"b",session_token:"t2",
         predicate_version:2,action:"push",diff_base:"branch-local",
         impl_in_chain:true,material_source:true,impl_evidence_kind:"none",
         transcript_path:"/tmp/t",gate:"push-implement",would_block:true,
         schema_version:1}' >> "$IMPLEMENT_SHADOW_LOG"
eq "a record with NO ts field is excluded"  "1" "$(episodes | wc -l | tr -d ' ')"
eq "and is reported as malformed"           "1" \
   "$("$SCRIPT" --status 2>&1 | grep -E '^  malformed ts' | awk '{print $3}')"

# a separator byte inside a field must not collide two distinct episodes.
# Concatenating key fields with \001 made branch="x\001y"+token="t1" equal to
# branch="x"+token="y\001t1", silently merging them and shrinking the denominator.
# NOTE: this fixture MUST be built with jq, not printf. A raw \001 inside a JSON
# string is invalid (control chars U+0000-U+001F must be escaped), so a
# printf-built record is silently dropped by jq and the test would pass for the
# wrong reason -- it would never exercise the collision at all.
jrec() { # jrec <id> <ts> <repo> <branch> <token>
  jq -cn --arg id "$1" --arg ts "$2" --arg repo "$3" --arg br "$4" --arg tok "$5" \
    '{record_id:$id,ts:$ts,repo:$repo,branch:$br,session_token:$tok,
      predicate_version:2,action:"push",diff_base:"branch-local",
      impl_in_chain:true,material_source:true,impl_evidence_kind:"none",
      transcript_path:"/tmp/t.jsonl",gate:"push-implement",would_block:true,
      schema_version:1}' >> "$IMPLEMENT_SHADOW_LOG"
}
: > "$IMPLEMENT_SHADOW_LOG"
jrec c1 "2026-07-28T10:00:00Z" "/repo/A" "$(printf 'x\001y')" "t1"
jrec c2 "2026-07-28T10:01:00Z" "/repo/A" "x" "$(printf 'y\001t1')"
eq "both collision fixtures are valid JSON" "2" "$(jq -r '.record_id' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | grep -c .)"
eq "a \\001 inside a field cannot collide keys" "2" "$(episodes | wc -l | tr -d ' ')"

# --- Task 3: adjudication write ---
# Both agent markers must be cleared to simulate a human: _claimant checks
# CLAUDECODE and CLAUDE_CODE_SESSION_ID, and the suite itself runs inside a
# Claude Code session where both are set.
adj() { ( unset CLAUDECODE CLAUDE_CODE_SESSION_ID; "$SCRIPT" "$1" --verdict "$2" --reason "$3" >/dev/null 2>&1; echo $?; ); }

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
# The label MUST reflect the actual claimant. Asserting HUMAN-CLAIMED under
# CLAUDECODE=1 previously "passed" against output that said "(agent-claimed)"
# and "HUMAN-CLAIMED" two lines apart.
eq "an agent run is labelled AGENT-CLAIMED"  "1" \
   "$(CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason x 2>&1 | grep -c 'AGENT-CLAIMED')"
eq "an agent run is NOT labelled HUMAN-CLAIMED" "0" \
   "$(CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason x 2>&1 | grep -c 'HUMAN-CLAIMED')"
eq "a human run is labelled HUMAN-CLAIMED"   "1" \
   "$( ( unset CLAUDECODE CLAUDE_CODE_SESSION_ID; "$SCRIPT" g --verdict unknown --reason x 2>&1 ) | grep -c 'HUMAN-CLAIMED')"
eq "output disclaims verification"          "1" \
   "$(CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason x 2>&1 | grep -ci 'not human-verified')"
eq "agent runs say they are excluded"       "1" \
   "$(CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason x 2>&1 | grep -ci 'excluded from the rate')"
eq "CLAUDE_CODE_SESSION_ID also marks agent" "agent" \
   "$( : > "$IMPLEMENT_ADJUDICATION_LOG"; ( unset CLAUDECODE; CLAUDE_CODE_SESSION_ID=abc "$SCRIPT" g --verdict unknown --reason x >/dev/null 2>&1 ); jq -r '.claimant' "$IMPLEMENT_ADJUDICATION_LOG")"

# --- provenance fields (spec MUST; only agent_env was covered before, which is
# exactly how a corrupted tty capture went unnoticed) ---
: > "$IMPLEMENT_ADJUDICATION_LOG"
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID; "$SCRIPT" g --verdict unknown --reason x >/dev/null 2>&1 )
eq "provenance.tty is a single line"  "1" "$(jq -r '.provenance.tty' "$IMPLEMENT_ADJUDICATION_LOG" | grep -c .)"
eq "provenance.tty is not the two-line tty(1) artifact" "0" \
   "$(jq -r '.provenance.tty' "$IMPLEMENT_ADJUDICATION_LOG" | grep -c '^not a tty$')"
eq "provenance.user is populated"     "1" "$(jq -r '.provenance.user | length > 0' "$IMPLEMENT_ADJUDICATION_LOG" | grep -c true)"
eq "provenance.parent is populated"   "1" "$(jq -r '.provenance.parent | length > 0' "$IMPLEMENT_ADJUDICATION_LOG" | grep -c true)"
eq "provenance.repo_head is populated" "1" "$(jq -r '.provenance.repo_head | length > 0' "$IMPLEMENT_ADJUDICATION_LOG" | grep -c true)"
eq "sidecar is created 0600"          "-rw-------" "$(ls -l "$IMPLEMENT_ADJUDICATION_LOG" | awk '{print $1}' | cut -c1-10)"

# --- a later adjudication supersedes an earlier one ---
# Without this, correcting a fat-fingered verdict prints success while the
# original silently continues to win, permanently poisoning the rate.
: > "$IMPLEMENT_ADJUDICATION_LOG"
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID; "$SCRIPT" g --verdict false_block --reason "fat-fingered" >/dev/null 2>&1 )
( unset CLAUDECODE CLAUDE_CODE_SESSION_ID; "$SCRIPT" g --verdict true_catch  --reason "correction"  >/dev/null 2>&1 )
eq "both adjudications are retained (audit trail)" "2" "$(wc -l < "$IMPLEMENT_ADJUDICATION_LOG" | tr -d ' ')"
eq "a correction actually takes effect" "true_catch" \
   "$( . "$SCRIPT" --source-only; _episode_verdict "g" | sed -n 1p )"
# and an agent overwriting a human reverts the episode to excluded
( CLAUDECODE=1 "$SCRIPT" g --verdict true_catch --reason "agent last" >/dev/null 2>&1 )
eq "an agent overwriting a human reverts to agent-claimed" "agent" \
   "$( . "$SCRIPT" --source-only; _episode_verdict "g" | sed -n 2p )"

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

# An empty v2 corpus is NOT the same as a fully-adjudicated one. Caught by
# dogfooding against the real log: 11 v1 records and 0 v2 records reported
# "every v2 record is adjudicated", which reads as "work done" when in fact
# nothing is countable yet.
: > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"
rec only_v1 "2026-07-28T10:00:00Z" "/repo/A" "feat/x" "tok1" 1
eq "an empty v2 corpus is not 'adjudicated'" "0" "$("$SCRIPT" --next 2>&1 | grep -ci 'is adjudicated')"
eq "it says there are no v2 records"         "1" "$("$SCRIPT" --next 2>&1 | grep -ci 'no v2 records')"
# Exact field: `grep -c '1 v1'` also matches "21 v1 record(s)", so it would not
# catch an off-by-N miscount that happens to end in 1.
eq "and it surfaces the exact v1 count"      "1" "$("$SCRIPT" --next 2>&1 | grep -E 'v1 record\(s\) present' | awk '{print $1}')"
eq "empty-v2 --next still exits 0"           "0" "$("$SCRIPT" --next >/dev/null 2>&1; echo $?)"

# --- impl_evidence_detail rendering (corpus-validity audit, F2) ------------
# The field exists so an adjudicator can tell "checked and absent" from "could
# not check" WITHOUT re-deriving it from ~/.claude state that session-start GC
# deletes at 7 days. If --next does not surface it, recording it is pointless.
rec3() { # rec3 <id> <ts> <detail-json>
  printf '{"record_id":"%s","ts":"%s","repo":"/repo/A","branch":"feat/x","session_token":"tok1","predicate_version":2,"action":"push","diff_base":"branch-local","impl_in_chain":true,"material_source":true,"impl_evidence_kind":"none","impl_evidence_detail":%s,"transcript_path":"/tmp/t.jsonl","gate":"push-implement","would_block":true,"schema_version":3}\n' \
    "$1" "$2" "$3" >> "$IMPLEMENT_SHADOW_LOG"
}

: > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"
rec3 d_cc "2026-07-28T09:00:00Z" '{"ledger":"missing","invocation":"missing","bridge":"cannot_check","attestation":"missing"}'
eq "--next renders the per-leg detail"        "1" \
   "$("$SCRIPT" --next 2>&1 | grep -c 'bridge=cannot_check')"
eq "a cannot_check leg raises the false_block note" "1" \
   "$("$SCRIPT" --next 2>&1 | grep -ci 'may have fired on infrastructure failure')"

# The note must be CONDITIONAL. An unconditional note is indistinguishable from
# a correct one on the cannot_check fixture above, and would train the
# adjudicator to ignore it.
: > "$IMPLEMENT_SHADOW_LOG"
rec3 d_ok "2026-07-28T09:00:00Z" '{"ledger":"missing","invocation":"missing","bridge":"missing","attestation":"missing"}'
eq "all-missing detail is still rendered"     "1" \
   "$("$SCRIPT" --next 2>&1 | grep -c 'bridge=missing')"
eq "all-missing detail raises NO false_block note" "0" \
   "$("$SCRIPT" --next 2>&1 | grep -ci 'may have fired on infrastructure failure')"

# A pre-schema-3 record has no per-leg data at all. That must be SAID, not left
# blank: a blank line reads as "all legs fine" when the truth is the outcome is
# unrecoverable for that record.
: > "$IMPLEMENT_SHADOW_LOG"
rec legacy "2026-07-28T09:00:00Z" "/repo/A" "feat/x" "tok1"
eq "a schema<3 record says the detail is not recorded" "1" \
   "$("$SCRIPT" --next 2>&1 | grep -ci 'not recorded (schema <3)')"
eq "and never renders an empty legs line"      "0" \
   "$("$SCRIPT" --next 2>&1 | grep -cE '^  legs +$')"

# Schema 3 must remain adjudicable: predicate_version is deliberately still 2,
# so the corpus stays poolable and the pre-registered horizon does not restart.
: > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"
rec3 d_pool "2026-07-28T09:00:00Z" '{"ledger":"missing","invocation":"missing","bridge":"missing","attestation":"missing"}'
eq "a schema-3 record is still a v2 episode"  "1" "$(episodes | grep -c 'd_pool')"

# --- Task 5: --status ---
seed()  { : > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"; }
mkrec() { rec "$1" "2026-07-28T$2:00Z" "$3" "br-$1" "tok-$1"; }
label() { ( unset CLAUDECODE CLAUDE_CODE_SESSION_ID; "$SCRIPT" "$1" --verdict "$2" --reason t >/dev/null 2>&1 ); }
status() { "$SCRIPT" --status 2>&1; }

# floor: 3 clean episodes in 1 repo must NOT print a rate
seed
mkrec e1 "10:01" /repo/A; mkrec e2 "10:02" /repo/A; mkrec e3 "10:03" /repo/A
label e1 true_catch; label e2 true_catch; label e3 true_catch
eq "below the floor prints insufficient data" "1" "$(status | grep -ci 'insufficient data')"
# The tool prints no literal '%' in ANY branch, so grepping for one pinned
# nothing. Assert the rate/band lines are genuinely absent instead.
eq "and prints no rate line"                  "0" "$(status | grep -cE '^  rate +[0-9]+/[0-9]+')"
eq "and prints no band line"                  "0" "$(status | grep -cE '^  band ')"
# Exact-field, not `grep -c '29'`: a bare substring match would also pass if
# FLOOR_EPISODES were mistyped to 129, 290 or 2900.
eq "and names the exact 29-episode floor"     "29" "$(status | grep -E '^  need ' | awk '{print $2}')"
eq "and names the exact 2-repo requirement"   ">=2" "$(status | grep -E '^  need ' | awk '{print $8}')"

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

# malformed-ts exclusions must be visible in --status, not a silent shortfall
seed
mkrec r1 "10:01" /repo/A
rec r2 "not-a-timestamp" /repo/A feat/z tokz
label r1 true_catch
eq "malformed ts count is surfaced" "1" "$(status | grep -E '^  malformed ts' | awk '{print $3}')"
eq "and it is not counted as an episode" "1" "$(status | grep -E '^  episodes' | awk '{print $2}')"

# the diversity floor must bind INDEPENDENTLY of the episode floor: the other
# floor test trips both thresholds at once, so neither is pinned on its own.
seed
i=0
while [ "$i" -lt 30 ]; do
  mkrec "d$i" "10:$( [ "$i" -lt 10 ] && printf '0%s' "$i" || printf '%s' "$i" )" /repo/SAME
  label "d$i" true_catch
  i=$(( i + 1 ))
done
eq "30 episodes in ONE repo still fails on diversity" "1" "$(status | grep -ci 'insufficient data')"
eq "and it reports 30 adjudicated episodes"           "30" "$(status | grep -E '^  adjudicated' | awk '{print $2}')"
eq "and reports only 1 repo"                          "1"  "$(status | grep -E '^  repos' | awk '{print $2}')"

# --- ABOVE the floor: the rate/band/worst-case branch (previously never executed) ---
# Build 30 rate-contributing episodes across 2 repos. Each gets its own
# session_token, so each is an independent episode.
build_floor() { # build_floor <n_true_catch> <n_false_block> <n_unknown>
  seed
  local i=0
  # Alternate repos WITHIN each verdict group: putting a whole group in one repo
  # made the diversity floor depend on the mix, so `build_floor 30 0 0` had only
  # one repo and failed for a reason the test wasn't probing.
  while [ "$i" -lt "$1" ]; do jrec2 "tc$i" "$( [ $((i%2)) -eq 0 ] && echo /repo/A || echo /repo/B )"; label "tc$i" true_catch;  i=$((i+1)); done
  i=0; while [ "$i" -lt "$2" ]; do jrec2 "fb$i" "$( [ $((i%2)) -eq 0 ] && echo /repo/A || echo /repo/B )"; label "fb$i" false_block; i=$((i+1)); done
  i=0; while [ "$i" -lt "$3" ]; do jrec2 "uk$i" "$( [ $((i%2)) -eq 0 ] && echo /repo/A || echo /repo/B )"; label "uk$i" unknown;     i=$((i+1)); done
}
jrec2() { # jrec2 <id> <repo> — unique branch+token so each record is its own episode
  jq -cn --arg id "$1" --arg repo "$2" \
    '{record_id:$id,ts:"2026-07-28T10:00:00Z",repo:$repo,branch:("br-"+$id),
      session_token:("tok-"+$id),predicate_version:2,action:"push",
      diff_base:"branch-local",impl_in_chain:true,material_source:true,
      impl_evidence_kind:"none",transcript_path:"/tmp/t.jsonl",
      gate:"push-implement",would_block:true,schema_version:1}' >> "$IMPLEMENT_SHADOW_LOG"
}

build_floor 30 0 0
eq "30 clean episodes across 2 repos print a rate" "0" "$(status | grep -ci 'insufficient data')"
eq "the rate line shows 0 false blocks of 30"      "0/30" "$(status | grep -E '^  rate ' | awk '{print $2}')"
eq "0/30 clean resolves to DENY"                   "DENY" "$(status | grep -E '^  band ' | awk '{print $2}')"
eq "the worst-case bound is printed"               "1"    "$(status | grep -c 'worst case')"

# unknowns must not silently clear the gate: worst case counts them as false blocks
build_floor 30 0 5
eq "unknowns are excluded from the headline rate" "0/30" "$(status | grep -E '^  rate ' | awk '{print $2}')"
eq "but included in the worst case"               "5/35" "$(status | grep -E '^  worst case ' | awk '{print $3}')"
eq "and the worst case downgrades the band"       "NARROWED" "$(status | grep -E '^  worst case ' | awk '{print $5}')"

# a genuinely bad rate must reach ADVISORY-ONLY (exact CP: 9/23, not Wilson's 8)
build_floor 14 15 0
eq "15/29 false blocks is ADVISORY-ONLY" "ADVISORY-ONLY" "$(status | grep -E '^  band ' | awk '{print $2}')"

# the floor applies to the RATE's denominator, not merely to labelled episodes
build_floor 14 0 20
eq "34 labelled but only 14 rate-bearing stays below the floor" "1" \
   "$(status | grep -ci 'insufficient data')"

# --- cmd_status must survive an EMPTY field too ---
# _episodes was fixed to preserve empty fields, but cmd_status re-split its
# output with `IFS=$'\t' read`, which collapses consecutive tabs: an empty
# `branch` shifted session_token into branch and left record_ids EMPTY, so
# _episode_verdict "" returned unlabeled and the episode was counted
# unadjudicated. A human could label 29 episodes and watch the count stay 0.
seed
jrecf2() { jq -cn --arg id "$1" --arg br "$2" --arg tok "$3" \
  '{record_id:$id,ts:"2026-07-28T10:00:00Z",repo:"/repo/A",branch:$br,
    session_token:$tok,predicate_version:2,action:"push",diff_base:"branch-local",
    impl_in_chain:true,material_source:true,impl_evidence_kind:"none",
    transcript_path:"/tmp/t.jsonl",gate:"push-implement",would_block:true,
    schema_version:1}' >> "$IMPLEMENT_SHADOW_LOG"; }
jrecf2 s1 "" tokA; jrecf2 s2 "" tokB
label s1 true_catch; label s2 true_catch
eq "empty-branch episodes are seen by --status"      "2" "$(status | grep -E '^  episodes' | awk '{print $2}')"
eq "and their adjudications are COUNTED"             "2" "$(status | grep -E '^  adjudicated' | awk '{print $2}')"
eq "and none are reported unadjudicated"             "0" "$(status | grep -E '^  unadjudicated' | awk '{print $2}')"
eq "and the repo is still attributed"                "1" "$(status | grep -c '/repo/A')"

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
# Behavioural, not a grep for a bare `read`/`cat` line that no real
# stdin-consuming implementation would contain: close stdin entirely and the
# tool must still work.
eq "runs with stdin CLOSED"                  "0" "$("$SCRIPT" --status 0<&- >/dev/null 2>&1; echo $?)"
eq "--next runs with stdin closed too"       "0" "$("$SCRIPT" --next 0<&- >/dev/null 2>&1; echo $?)"

# --- C2 regression: a truncated command line must fail, not hang ---
# ulimit bounds it so a regression fails fast instead of wedging the suite.
eq "a missing --verdict value exits non-zero" "1" \
   "$( ( ulimit -t 5; "$SCRIPT" someid --verdict >/dev/null 2>&1 ); echo $? )"
eq "a missing --reason value exits non-zero"  "1" \
   "$( ( ulimit -t 5; "$SCRIPT" someid --verdict true_catch --reason >/dev/null 2>&1 ); echo $? )"

echo
echo "Tests run: $(( PASS + FAIL ))  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1

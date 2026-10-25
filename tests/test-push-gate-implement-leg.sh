#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-implement-leg.sh ==="

# --- Unit: implement_shadow_record's would_block parameter (#169) ----------
# Direct-call unit block. The 8th parameter defaults to true so the guard's
# existing call site is unchanged; passing false is how an attestation-resolved
# episode is recorded.
# NOT wrapped in a subshell: test-helpers.sh's assert_* increment plain global
# counters (TESTS_RUN/TESTS_PASSED/TESTS_FAILED), and a subshell's writes to
# those are discarded on exit — the FAIL text would print but never flip the
# suite's exit code. Isolation is instead scoped via the _u_-prefixed names
# (no collision with anything used later in this file) and explicit cleanup;
# sourcing the lib into this shell only defines implement_shadow_record() and
# two version vars, and IMPLEMENT_SHADOW_LOG is unconditionally re-exported to
# its real default path below (before any assertion that depends on it), so
# nothing here leaks into the rest of the suite.
_u_home="$(mktemp -d /tmp/pg-impl-unit-XXXXXX)"
export IMPLEMENT_SHADOW_LOG="${_u_home}/shadow.jsonl"
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/implement-shadow.sh"

assert_equals "schema_version is 5" "5" "${IMPLEMENT_SHADOW_SCHEMA_VERSION}"
# 3 (#219): the push path now measures the tree and ref the command names, not
# the session cwd — that changes WHEN the leg fires, so v2 records are no longer
# poolable. Bumping this pin without bumping the constant, or vice versa, is the
# mistake it exists to catch.
assert_equals "predicate_version is 5 (#245 redirection parser + advisory_emitted)" "5" \
    "${IMPLEMENT_SHADOW_PREDICATE_VERSION}"

implement_shadow_record push "${PROJECT_ROOT}" tok /tmp/t.jsonl none branch-local true
assert_contains "omitted would_block defaults to true" '"would_block":true' \
    "$(cat "${IMPLEMENT_SHADOW_LOG}")"

: > "${IMPLEMENT_SHADOW_LOG}"
implement_shadow_record push "${PROJECT_ROOT}" tok /tmp/t.jsonl attested branch-local true false
_u_rec="$(cat "${IMPLEMENT_SHADOW_LOG}")"
assert_contains "explicit false is recorded as a json boolean" '"would_block":false' "${_u_rec}"
assert_contains "evidence kind is carried through" '"impl_evidence_kind":"attested"' "${_u_rec}"
assert_equals "record is still valid json" "0" \
    "$(jq -e . "${IMPLEMENT_SHADOW_LOG}" >/dev/null 2>&1; echo $?)"

rm -rf "${_u_home}"
unset IMPLEMENT_SHADOW_LOG

# --- Unit: impl_evidence_detail (corpus-validity audit, F2) ----------------
# impl_evidence_kind is format-frozen ("none"/"attested" are asserted here and
# pinned in three openspec specs), so the per-leg outcome lands in a NEW field
# rather than by widening that one. The 9th parameter is a space-separated
# "<leg>:<status>" string; the lib builds the object in jq, so the guard never
# constructs JSON in bash 3.2.
#
# The distinction this exists for: _bridge_has returns 1 for THREE different
# reasons (branch-ledger lib unsourceable, function undefined, no evidence).
# Only the last one means "no implementation work"; the first two are
# infrastructure failures where the constant advisory names the WRONG remedy,
# which is the pre-registered false_block condition. Without this field an
# adjudicator has to re-derive that from ~/.claude state that session-start GC
# deletes after 7 days, while the corpus needs months to reach n=29.
_d_home="$(mktemp -d /tmp/pg-impl-detail-XXXXXX)"
export IMPLEMENT_SHADOW_LOG="${_d_home}/shadow.jsonl"

implement_shadow_record push "${PROJECT_ROOT}" tok /tmp/t.jsonl none branch-local true true \
    "ledger:missing invocation:missing bridge:cannot_check attestation:missing"
assert_json_valid "detailed record is valid json" "${IMPLEMENT_SHADOW_LOG}"
assert_equals "detail is an object, not an opaque string" "object" \
    "$(jq -r '.impl_evidence_detail | type' "${IMPLEMENT_SHADOW_LOG}")"
assert_equals "cannot_check is preserved per leg" "cannot_check" \
    "$(jq -r '.impl_evidence_detail.bridge' "${IMPLEMENT_SHADOW_LOG}")"
assert_equals "missing is distinguishable from cannot_check" "missing" \
    "$(jq -r '.impl_evidence_detail.ledger' "${IMPLEMENT_SHADOW_LOG}")"
assert_equals "schema_version on a detailed record is 5" "5" \
    "$(jq -r '.schema_version' "${IMPLEMENT_SHADOW_LOG}")"
assert_equals "predicate_version is 5 so v4 records are NOT pooled" "5" \
    "$(jq -r '.predicate_version' "${IMPLEMENT_SHADOW_LOG}")"

# An omitted detail must be null, NOT a fabricated all-missing object. "not
# recorded" and "checked and absent" are different states; conflating them is
# the same silence-as-success class the audit exists to close.
: > "${IMPLEMENT_SHADOW_LOG}"
implement_shadow_record push "${PROJECT_ROOT}" tok /tmp/t.jsonl none branch-local true
assert_equals "omitted detail is null, never a fabricated object" "null" \
    "$(jq -r '.impl_evidence_detail | type' "${IMPLEMENT_SHADOW_LOG}")"
assert_json_valid "record with no detail is still valid json" "${IMPLEMENT_SHADOW_LOG}"

# A malformed detail string must not corrupt the record or abort the write.
: > "${IMPLEMENT_SHADOW_LOG}"
implement_shadow_record push "${PROJECT_ROOT}" tok /tmp/t.jsonl none branch-local true true \
    "garbage-with-no-colon"
assert_json_valid "malformed detail still yields valid json" "${IMPLEMENT_SHADOW_LOG}"
assert_equals "malformed detail degrades to null, not a partial object" "null" \
    "$(jq -r '.impl_evidence_detail | type' "${IMPLEMENT_SHADOW_LOG}")"

rm -rf "${_d_home}"
unset IMPLEMENT_SHADOW_LOG

# The IMPLEMENT-evidence leg (Check 0, WARN-FIRST) advises — never denies — when
# an implementation-slot skill (executing-plans / subagent-driven-development /
# agent-team-execution) is in the composition chain, the push diff touches
# material (non-docs) source, and no evidence for that slot exists. This test
# isolates that leg: REVIEW and VERIFY are pre-satisfied via the SAME seed
# helpers as test-push-gate-ledger.sh (branch-ledger records + a clean verdict
# covering HEAD), so any advisory/deny that shows up is attributable to the
# IMPLEMENT leg alone.

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

# --- Content assertions (wiring) ---
g="$(cat "${GUARD}")"
assert_contains "gate has an IMPLEMENT leg"            "IMPLEMENT"                       "${g}"
assert_contains "gate checks executing-plans slot"     "executing-plans"                 "${g}"
assert_contains "gate accepts phase_attested evidence" "phase_attested"                  "${g}"
# Wiring only. Both ledger legs bottom out in branch_ledger_dir, which returns
# non-zero for an unresolvable branch KEY as well as for "no record" — probing
# the key is what keeps a cannot_check from being under-reported as missing,
# which is the direction that biases the pre-registered rate toward clearing the
# deny-flip. This is only the WIRING assertion — the behavioral coverage is the
# "unresolvable branch key" block at the END of this file, which drives the
# guard against a plugin root whose branch_ledger_key fails. Both are kept: this
# one fails if the probe is deleted outright, that one fails if it is defeated.
assert_contains "detail probes branch-ledger key resolvability" \
    "_impl_det_key_ok" "${g}"
assert_contains "leg is documented as warn-first (no deny yet)" "will become a deny after backtest" "${g}"

# --- Behavioral setup (mirrors test-push-gate-ledger.sh verbatim) ---
_OLDHOME="$HOME"
_THOME="$(mktemp -d /tmp/pg-impl-home-XXXXXX)"
export HOME="$_THOME"
mkdir -p "$HOME/.claude"

_TPATH="$HOME/t.jsonl"
touch "$_TPATH"               # basename "t" -> token "session-t"
_TOK="session-t"
_COMP="$HOME/.claude/.skill-composition-state-${_TOK}"

# Singleton session-token file: phase_attest() (invoked directly below, outside
# the guard's transcript-based resolution) reads THIS file for its token. Must
# match the guard's own transcript-resolved token ("session-t") so an
# attestation recorded here is visible to the guard's phase_attested() read.
printf '%s' "${_TOK}" > "$HOME/.claude/.skill-session-token"

# Composition state: REVIEW + VERIFY + an implementation-slot skill (executing-
# plans) in chain; completed is EMPTY (status layer must not satisfy IMPLEMENT
# via .completed per the design — only ledger/invocation/bridge/attestation do).
printf '%s' '{"chain":["requesting-code-review","verification-before-completion","executing-plans"],"current_index":0,"completed":[]}' \
    > "${_COMP}"

# Self-contained fixture repo: a feature branch whose diff against its OWN
# mainline (main) touches MATERIAL, non-routing source (src/app.py). The guard
# runs with cwd = this repo (below), so its material-source gate is exercised
# deterministically regardless of which branch the OUTER repo is on. The prior
# version relied on the ambient repo's branch-diff-vs-mainline being non-empty,
# so it silently failed when run from a clean `main` checkout (base==HEAD =>
# empty diff => no material source => the advisory never fired). src/app.py is
# NON-routing (not skills/|config/|hooks/), and the fixture repo has no
# config/default-triggers.json, so routing-governance never fires and only the
# IMPLEMENT leg is under test.
#
# pwd -P: git rev-parse --show-toplevel (how the guard resolves _proot) returns
# the PHYSICAL path, so on macOS a /tmp symlink would make the record-time
# branch-ledger key (raw mktemp path) differ from the guard's read-time key —
# REVIEW/VERIFY would then be rescued only by the #131 bridge, not the direct
# ledger this test intends. Pin the physical path so both keys agree.
_REPO="$(cd "$(mktemp -d /tmp/pg-impl-repo-XXXXXX)" && pwd -P)"
(
  set -e                       # any failed setup step aborts the subshell (not just the last)
  cd "${_REPO}"
  git init -q
  git config user.email test@example.com
  git config user.name  test
  echo "# fixture" > README.md
  git add README.md && git commit -qm "init"
  git branch -M main
  git checkout -qb feat/impl
  mkdir -p src && echo "print('x')" > src/app.py
  git add src/app.py && git commit -qm "feat: material source change"
) || { echo "FATAL: fixture repo setup failed" >&2; rm -rf "${_REPO}" "${_THOME}"; export HOME="$_OLDHOME"; exit 1; }

# Clean covering verdict at the FIXTURE repo's HEAD — satisfies verify-hardening
# and, with the ledger records below, VERIFY; routing-governance does not fire
# (no routing paths in the diff, no config/default-triggers.json in the repo),
# so only the IMPLEMENT leg's behavior is under test.
_PVHEAD="$(git -C "${_REPO}" rev-parse HEAD 2>/dev/null)"
jq -nc --arg s "${_PVHEAD}" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' \
    > "$HOME/.claude/.skill-project-verified-${_TOK}"

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"
branch_ledger_record "requesting-code-review"        "${_REPO}"
branch_ledger_record "verification-before-completion" "${_REPO}"

_mkinput() {
    jq -n --arg tp "$_TPATH" --arg c "${1:-git push origin HEAD}" \
        '{"transcript_path":$tp,"tool_input":{"command":$c}}'
}
# Guard runs with cwd = the fixture repo so _proot (git rev-parse --show-toplevel)
# resolves to it and the material-source diff is computed as
# merge-base(HEAD,main)..HEAD (i.e. the src/app.py commit on feat/impl).
run_guard() { ( cd "${_REPO}" && _mkinput "${1:-}" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null ); }

# (a) IMPLEMENT in chain, material source in diff, no impl evidence ->
#     advisory present, and NOT a deny attributable to IMPLEMENT (no deny at
#     all, since REVIEW/VERIFY/routing are pre-satisfied above).
out="$(run_guard)"
assert_contains     "no impl evidence => IMPLEMENT advisory"     "IMPLEMENT:"  "${out:-<empty>}"
assert_contains     "advisory surfaces as additionalContext"     "additionalContext" "${out:-<empty>}"
assert_not_contains "IMPLEMENT leg does not deny"                 '"deny"'     "${out:-}"
assert_not_contains "IMPLEMENT leg emits no permissionDecision at all" "permissionDecision" "${out:-}"

# (a2) The warn must ALSO write a telemetry line — phase_gate_log is defined in
# phase-evidence.sh, which must be sourced BEFORE Check 0 (regression: it was
# only sourced later, making the call a silent no-op and the deny-flip backtest
# baseline empty). HOME is isolated (mktemp) so this reads the test's own log.
_pglog="${HOME}/.claude/.phase-gate-events.log"
assert_contains "IMPLEMENT warn writes a phase-gate telemetry line" "push-implement" "$(cat "${_pglog}" 2>/dev/null || echo '<no log>')"

# (b) After phase_attest executing-plans "test" -> no IMPLEMENT advisory, but
# the episode IS recorded as would_block:false / attested, so the deny-flip
# corpus can measure how often attestation rather than work satisfied the leg
# (#169). The shadow log override is set HERE (it used to be set later) so this
# case can assert on it.
export IMPLEMENT_SHADOW_LOG="$HOME/.claude/.push-implement-shadow.jsonl"
: > "$IMPLEMENT_SHADOW_LOG"
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/phase-attest.sh"
phase_attest "executing-plans" "test" >/dev/null 2>&1
_pglog_before="$(wc -l < "${HOME}/.claude/.phase-gate-events.log" 2>/dev/null | tr -d ' ')"
out="$(run_guard)"
assert_not_contains "attested executing-plans => no IMPLEMENT advisory" "IMPLEMENT:" "${out:-}"
assert_not_contains "attested path still does not deny"                 '"deny"'     "${out:-}"
assert_not_contains "attested path emits no permissionDecision"  "permissionDecision" "${out:-}"

assert_equals "attested episode writes exactly one shadow record" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
_arec="$(cat "$IMPLEMENT_SHADOW_LOG")"
assert_json_valid "attested record is valid json" "$IMPLEMENT_SHADOW_LOG"
assert_contains "attested record is not a would-block" '"would_block":false'          "${_arec}"
assert_contains "attested record names the evidence class" '"impl_evidence_kind":"attested"' "${_arec}"
assert_contains "attested record names the gate"      '"gate":"push-implement"'       "${_arec}"
# The attested record is the one case where a leg reads `present`. Paired with
# the would-block assertions above, this is what proves the detail tracks the
# actual outcome rather than emitting a constant.
assert_equals "attested record marks the attestation leg present" "present" \
    "$(jq -r '.impl_evidence_detail.attestation' "$IMPLEMENT_SHADOW_LOG" | head -1)"
assert_equals "attested record still shows ledger as checked-and-absent" "missing" \
    "$(jq -r '.impl_evidence_detail.ledger' "$IMPLEMENT_SHADOW_LOG" | head -1)"

# The warn telemetry line must NOT fire on a satisfied leg — the advisory and
# phase_gate_log stay gated on _impl_ok=false.
_pglog_after="$(wc -l < "${HOME}/.claude/.phase-gate-events.log" 2>/dev/null | tr -d ' ')"
assert_equals "attested episode writes no push-implement warn line" \
    "${_pglog_before:-0}" "${_pglog_after:-0}"

# (b2) Real invocation evidence must still record NOTHING — the shipped
# implement-shadow-event scenario "satisfied IMPLEMENT evidence emits nothing"
# is deliberately preserved for the non-attested classes (#169 design, Unit E).
rm -f "$HOME/.claude/.skill-phase-attest-${_TOK}"
: > "$IMPLEMENT_SHADOW_LOG"
printf '%s\n' '["executing-plans"]' > "$HOME/.claude/.skill-invocation-evidence-${_TOK}"
out="$(run_guard)"
assert_not_contains "invocation-satisfied => no IMPLEMENT advisory" "IMPLEMENT:" "${out:-}"
assert_equals "invocation-satisfied writes no shadow record" "0" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
rm -f "$HOME/.claude/.skill-invocation-evidence-${_TOK}"

# (c) Chain without any implementation-slot member -> no IMPLEMENT advisory,
#     even though the diff still touches material source and no impl evidence
#     exists (the leg only fires when an impl-slot skill is IN the chain).
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' \
    > "${_COMP}"
out="$(run_guard)"
assert_not_contains "no impl-slot in chain => no IMPLEMENT advisory" "IMPLEMENT:" "${out:-}"
assert_not_contains "no impl-slot in chain => no deny"                '"deny"'    "${out:-}"

# --- Stage C1: shadow record on a push warn -------------------------------
# The warn branch must leave an adjudicable JSONL record. Uses the same seeded
# HOME/chain as the advisory assertions above (IMPLEMENT unsatisfied, REVIEW and
# VERIFY pre-satisfied), so a record here is attributable to the IMPLEMENT leg.
# Restore that precondition: (c) narrowed .chain to exclude the impl-slot skill
# for its own assertion, and (b) left an executing-plans attestation on disk —
# either alone would keep the leg from firing here, so both are reset.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion","executing-plans"],"current_index":0,"completed":[]}' \
    > "${_COMP}"
rm -f "$HOME/.claude/.skill-phase-attest-${_TOK}"
export IMPLEMENT_SHADOW_LOG="$HOME/.claude/.push-implement-shadow.jsonl"
: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard)"
assert_not_contains "shadow emission does not turn the leg into a deny" '"deny"' "${out:-}"
assert_not_contains "shadow emission emits no permissionDecision at all" "permissionDecision" "${out:-}"
assert_equals "one shadow record written on a push warn" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
_rec="$(cat "$IMPLEMENT_SHADOW_LOG")"
assert_json_valid "shadow record is valid json" "$IMPLEMENT_SHADOW_LOG"
assert_contains "record names the gate"        '"gate":"push-implement"' "${_rec}"
assert_contains "record marks a would-block"   '"would_block":true'      "${_rec}"
assert_contains "record carries action push"   '"action":"push"'         "${_rec}"
assert_contains "record carries schema_version"    '"schema_version":5'    "${_rec}"
assert_contains "record carries predicate_version" '"predicate_version":5' "${_rec}"
assert_contains "record carries a record_id"   '"record_id":'            "${_rec}"
assert_contains "record carries a ts"          '"ts":'                   "${_rec}"
assert_contains "record carries the transcript pointer" '"transcript_path":' "${_rec}"
assert_not_contains "record never carries raw command text" '"command":' "${_rec}"

# The guard must populate the per-leg detail, not leave it null. A would-block
# means every leg was consulted and every one came back empty, so each leg is
# recorded explicitly rather than inferred from impl_evidence_kind:"none".
assert_equals "guard populates the per-leg detail" "object" \
    "$(jq -r '.impl_evidence_detail | type' "$IMPLEMENT_SHADOW_LOG" | head -1)"
_detail="$(jq -rc '.impl_evidence_detail' "$IMPLEMENT_SHADOW_LOG" | head -1)"
assert_not_contains "no leg is left null by the guard" "null" "${_detail}"
# Exact values, not merely "present": this harness is healthy (branch-ledger
# sources, jq on PATH, token resolved, phase_attested defined), so every leg
# must read `missing` — it was checked and found nothing. A `cannot_check` here
# would mean the probe is reporting infrastructure failure inside a working
# harness, which is the one reading that must never be silently wrong.
for _leg in ledger invocation bridge attestation; do
    assert_equals "guard records ${_leg} as checked-and-absent" "missing" \
        "$(jq -r --arg l "${_leg}" '.impl_evidence_detail[$l]' "$IMPLEMENT_SHADOW_LOG" | head -1)"
done

# record_id must be unique across events, not a repeat of a constant.
out="$(run_guard)"
assert_equals "second warn appends a second record" "2" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
assert_equals "record_ids are distinct" "2" \
    "$(jq -r '.record_id' "$IMPLEMENT_SHADOW_LOG" | sort -u | wc -l | tr -d ' ')"

# --- Stage C1: merge coverage (population fix) ----------------------------
# Spec says the leg applies to a push OR merge; the code gated it on push only,
# so gh-merge events were structurally missing from the sample.
: > "$IMPLEMENT_SHADOW_LOG"

# Contrast control: the SAME unsatisfied-evidence fixture state, invoked as a
# PUSH (identical precondition to the assertion at line ~106 above), MUST
# surface "IMPLEMENT:" in stdout. This proves the fixture genuinely produces a
# would-block for this state, so the merge case's empty stdout below is
# attributable to the known advisory-flush gap and not to the leg silently
# failing to fire at all.
out_push_contrast="$(run_guard)"
assert_contains "contrast control: push DOES surface IMPLEMENT advisory" "IMPLEMENT:" "${out_push_contrast:-<empty>}"

: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard 'gh pr merge 7 --squash')"

assert_not_contains "merge path stays advisory (no deny from this leg)" '"deny"' "${out:-}"
assert_not_contains "merge path emits no permissionDecision at all" "permissionDecision" "${out:-}"
assert_equals "one shadow record written on a merge warn" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
assert_contains "merge record carries action gh-merge" '"action":"gh-merge"' \
    "$(cat "$IMPLEMENT_SHADOW_LOG")"

# --- Stage C1: an unwritable shadow log must not change the decision -------
# The recorder is diagnostic. If it cannot write, the guard's stdout must be
# byte-identical to a healthy run and the exit code must stay 0.
: > "$IMPLEMENT_SHADOW_LOG"
_healthy="$(run_guard)"
# Non-vacuous baseline: _healthy must actually carry the advisory and the
# healthy run must actually have written a record, or the byte-identical
# comparison below would trivially hold for two empty strings.
assert_contains "healthy run surfaces the IMPLEMENT advisory (non-vacuous baseline)" \
    "IMPLEMENT:" "${_healthy:-<empty>}"
assert_equals "healthy run wrote exactly one shadow record" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
# IMPLEMENT_SHADOW_LOG has been byte-identical to the lib's own default path
# since it was set above, so this IS the default log; snapshot its count
# before pointing the override at a guaranteed-unwritable path.
_default_count_before="$(wc -l < "$HOME/.claude/.push-implement-shadow.jsonl" 2>/dev/null | tr -d ' ')"
[ -n "${_default_count_before}" ] || _default_count_before=0
# $HOME/.claude/.skill-session-token is a regular FILE (written near the top
# of this test), so using it as a directory component of the log path
# guarantees `mkdir -p` fails for every user, including root — unlike
# /nonexistent-dir-$$, which only fails because of ambient FS permissions.
export IMPLEMENT_SHADOW_LOG="$HOME/.claude/.skill-session-token/s.jsonl"
_broken="$(run_guard)"; _brc=$?
assert_equals "unwritable shadow log leaves stdout byte-identical" "${_healthy}" "${_broken}"
assert_equals "unwritable shadow log still exits 0" "0" "${_brc}"
_default_count_after="$(wc -l < "$HOME/.claude/.push-implement-shadow.jsonl" 2>/dev/null | tr -d ' ')"
[ -n "${_default_count_after}" ] || _default_count_after=0
assert_equals "default shadow log gained no record while the override was unwritable" \
    "${_default_count_before}" "${_default_count_after}"
export IMPLEMENT_SHADOW_LOG="$HOME/.claude/.push-implement-shadow.jsonl"

# Satisfied IMPLEMENT evidence must emit nothing at all -- for REAL (non-
# attestation) evidence. This used to exercise phase_attest, but #169 made
# attestation-satisfied episodes recordable (case (b) above), so the "emits
# nothing" invariant now only holds for the non-attested classes (#169
# design, Unit E) -- exercise invocation evidence here instead.
: > "$IMPLEMENT_SHADOW_LOG"
printf '%s\n' '["executing-plans"]' > "$HOME/.claude/.skill-invocation-evidence-${_TOK}"
out="$(run_guard)"
assert_equals "no shadow record when IMPLEMENT evidence exists" "0" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | tr -d ' ')"
rm -f "$HOME/.claude/.skill-invocation-evidence-${_TOK}"

# --- #161: merges are measured against the PR, not the local branch -------
# gh is stubbed on PATH: no test may touch the network. The stub reports a PR
# whose diff edits src/app.py, while the fixture branch's own delta is what the
# pre-#161 code would have measured.
#
# Precondition: the previous block already removed its invocation-evidence
# fixture, and no phase_attest record is left on disk either, so _impl_ok is
# false again here. This rm is a defensive no-op kept in case a future edit
# reintroduces an attestation fixture above without its own cleanup. Fixture
# state matches what the brief assumes: impl-slot in chain, no impl evidence.
# (_COMP already has executing-plans in .chain since line ~142, and REVIEW/
# VERIFY ledger records from lines ~90-91 are untouched, so only the IMPLEMENT
# leg is under test here.)
rm -f "$HOME/.claude/.skill-phase-attest-${_TOK}"

_GHSTUB="$(mktemp -d /tmp/pg-ghstub-XXXXXX)"
cat > "${_GHSTUB}/gh" <<'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in 404) exit 1 ;; esac; done
printf 'src/app.py\n'
STUB
chmod +x "${_GHSTUB}/gh"

: > "$IMPLEMENT_SHADOW_LOG"
out="$(PATH="${_GHSTUB}:$PATH" run_guard 'gh pr merge 7 --squash')"
_rec="$(cat "$IMPLEMENT_SHADOW_LOG")"
assert_equals "merge writes one record" "1" "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
assert_contains "merge record names the PR as its subject" '"diff_base":"pr:7"' "${_rec}"
assert_contains "merge record still marks material source"  '"material_source":true' "${_rec}"
assert_contains "predicate_version bumped to 5 (#245)"        '"predicate_version":5' "${_rec}"
assert_not_contains "merge did not become a deny" "permissionDecision" "${out:-}"

# Unresolvable PR -> unresolved, record still written, still no deny.
: > "$IMPLEMENT_SHADOW_LOG"
out="$(PATH="${_GHSTUB}:$PATH" run_guard 'gh pr merge 404 --squash')"
assert_equals "unresolvable merge still writes a record" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
assert_contains "unresolvable merge is marked unresolved" '"diff_base":"unresolved"' \
    "$(cat "$IMPLEMENT_SHADOW_LOG")"
assert_not_contains "unresolvable merge did not become a deny" "permissionDecision" "${out:-}"

# Resolved-but-non-material PR -> record names the PR (NOT "unresolved"), with
# material_source:false and no advisory. Fix round 1 (#161 review finding):
# gh resolves fine but the PR touches only docs/CHANGELOG.md, so the merge is
# a distinct outcome from "we couldn't look" and must be labeled as such.
_GHSTUB_DOCS="$(mktemp -d /tmp/pg-ghstub-docs-XXXXXX)"
cat > "${_GHSTUB_DOCS}/gh" <<'STUB'
#!/bin/bash
printf 'docs/CHANGELOG.md\n'
STUB
chmod +x "${_GHSTUB_DOCS}/gh"

: > "$IMPLEMENT_SHADOW_LOG"
out="$(PATH="${_GHSTUB_DOCS}:$PATH" run_guard 'gh pr merge 9 --squash')"
_rec="$(cat "$IMPLEMENT_SHADOW_LOG")"
assert_equals "resolved non-material merge writes one record" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
assert_contains "resolved non-material merge names the PR, not unresolved" '"diff_base":"pr:9"' "${_rec}"
assert_contains "resolved non-material merge marks material_source false" '"material_source":false' "${_rec}"
assert_not_contains "resolved non-material merge does not become a deny" "permissionDecision" "${out:-}"
assert_not_contains "resolved non-material merge surfaces no IMPLEMENT advisory" "IMPLEMENT:" "${out:-}"
rm -rf "${_GHSTUB_DOCS}"

# PUSH PATH UNCHANGED — this is a Global Constraint, asserted not assumed.
: > "$IMPLEMENT_SHADOW_LOG"
out_push="$(run_guard)"
assert_contains "push record is branch-local" '"diff_base":"branch-local"' \
    "$(cat "$IMPLEMENT_SHADOW_LOG")"
assert_contains "push still surfaces the IMPLEMENT advisory" "IMPLEMENT:" "${out_push:-<empty>}"
rm -rf "${_GHSTUB}"

# --- #161 RESOLVED: a resolved merge now surfaces the advisory ------------
# PR #163 pinned the gap with an assert_not_contains and an "invert on fix"
# comment; this is that inversion (the old pin has since been deleted).
_GHSTUB2="$(mktemp -d /tmp/pg-ghstub2-XXXXXX)"
cat > "${_GHSTUB2}/gh" <<'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in 404) exit 1 ;; esac; done
printf 'src/app.py\n'
STUB
chmod +x "${_GHSTUB2}/gh"

out="$(PATH="${_GHSTUB2}:$PATH" run_guard 'gh pr merge 7 --squash')"
assert_contains "resolved merge surfaces the IMPLEMENT advisory" "IMPLEMENT:" "${out:-<empty>}"
assert_not_contains "resolved merge is still not a deny" "permissionDecision" "${out:-}"

# Unresolved merge stays SILENT — the original suppression was protective.
out="$(PATH="${_GHSTUB2}:$PATH" run_guard 'gh pr merge 404 --squash')"
assert_not_contains "unresolved merge stays silent" "IMPLEMENT:" "${out:-}"
rm -rf "${_GHSTUB2}"

# --- I2: the pr:* flush gate must be exercised by a NON-empty, NON-IMPLEMENT
# _STALE_MSG, or removing the gate is invisible to the suite ---------------
# Review finding: the assertion above ("unresolved merge stays silent")
# passes for the wrong reason — on an unresolved merge _impl_material is
# false, so _STALE_MSG is empty there too, and the gate at
# openspec-guard.sh's `_flush_push_advisories` is never actually exercised.
# Manufacture a genuinely non-empty, non-IMPLEMENT _STALE_MSG by advancing
# feat/impl's HEAD past the SHA the branch-ledger recorded above (lines
# ~90-91): _ledger_has then appends "<milestone> stale: recorded at ..."
# text for requesting-code-review/verification-before-completion on every
# subsequent guard run, regardless of push vs merge or IMPLEMENT status.
echo "print('y')" >> "${_REPO}/src/app.py"
git -C "${_REPO}" add src/app.py
git -C "${_REPO}" commit -qm "feat: advance local HEAD past the ledger record (non-IMPLEMENT staleness bait)"

_GHSTUB4="$(mktemp -d /tmp/pg-ghstub4-XXXXXX)"
cat > "${_GHSTUB4}/gh" <<'STUB'
#!/bin/bash
for a in "$@"; do case "$a" in 404) exit 1 ;; esac; done
printf 'src/app.py\n'
STUB
chmod +x "${_GHSTUB4}/gh"

# (a) UNRESOLVED merge must stay FULLY silent even though _STALE_MSG is now
# non-empty (ledger staleness). Mutation-verified: widening
# _flush_push_advisories's gate away from a `_impl_db`-scoped select onto
# "always use _STALE_MSG for any merge" flips this and the "does not leak"
# assertion below from pass to fail; restoring the gate flips them back.
out="$(PATH="${_GHSTUB4}:$PATH" run_guard 'gh pr merge 404 --squash')"
assert_not_contains "unresolved merge with pending staleness stays fully silent" \
    "additionalContext" "${out:-}"
assert_not_contains "unresolved merge does not leak ledger staleness text" \
    "stale:" "${out:-}"

# (b) RESOLVED merge (#161 I1): must flush ONLY the IMPLEMENT text, never the
# ledger staleness text also sitting in _STALE_MSG. Pre-fix, the flush was
# gated on _impl_db alone and leaked the ENTIRE _STALE_MSG — including notes
# about milestones that have nothing to do with the merged PR — onto `gh pr
# merge` of unrelated PRs.
out="$(PATH="${_GHSTUB4}:$PATH" run_guard 'gh pr merge 7 --squash')"
assert_contains "resolved merge with pending staleness still surfaces IMPLEMENT" \
    "IMPLEMENT:" "${out:-<empty>}"
assert_not_contains "resolved merge does not leak ledger staleness text" \
    "stale:" "${out:-}"
rm -rf "${_GHSTUB4}"

# --- Negative-case coverage: record-write condition, false branches --------
# Task 2 review finding: only the TRUE branches of the write gate (materially
# true, or gh-merge) had explicit assertions. Pin both FALSE branches too.

# (a) gh pr merge WITH implement evidence present -> _impl_ok short-circuits
# before the would-block write gate, so the would-block record (would_block:
# true) is never written and no advisory fires, even though the PR resolves
# and touches material source. This case is satisfied by attestation alone,
# so per #169 it DOES still write the attested record (would_block:false) --
# asserted explicitly below rather than just "no record at all".
rm -f "$HOME/.claude/.skill-phase-attest-${_TOK}"
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/phase-attest.sh"
phase_attest executing-plans "negative-case-merge" >/dev/null 2>&1
: > "$IMPLEMENT_SHADOW_LOG"
_GHSTUB3="$(mktemp -d /tmp/pg-ghstub3-XXXXXX)"
cat > "${_GHSTUB3}/gh" <<'STUB'
#!/bin/bash
printf 'src/app.py\n'
STUB
chmod +x "${_GHSTUB3}/gh"
out="$(PATH="${_GHSTUB3}:$PATH" run_guard 'gh pr merge 11 --squash')"
_arec_merge="$(cat "$IMPLEMENT_SHADOW_LOG" 2>/dev/null)"
assert_not_contains "attested merge writes no would-block record" '"would_block":true' "${_arec_merge}"
assert_equals "attested merge writes exactly one record (the attested one, #169)" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | tr -d ' ')"
assert_contains "attested merge record names the evidence class" '"impl_evidence_kind":"attested"' "${_arec_merge}"
assert_not_contains "attested merge surfaces no IMPLEMENT advisory" "IMPLEMENT:" "${out:-}"
rm -rf "${_GHSTUB3}"
rm -f "$HOME/.claude/.skill-phase-attest-${_TOK}"

# (b) git push whose branch diff is non-material (docs-only) -> the write gate
# never sees _impl_material=true and this is not a merge, so no shadow record.
git -C "${_REPO}" checkout -qb feat/docsonly main
echo "docs change" >> "${_REPO}/README.md"
git -C "${_REPO}" add README.md
git -C "${_REPO}" commit -qm "docs: non-material change"
: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard)"
assert_equals "non-material push writes no shadow record" "0" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | tr -d ' ')"
assert_not_contains "non-material push surfaces no IMPLEMENT advisory" "IMPLEMENT:" "${out:-}"
git -C "${_REPO}" checkout -q feat/impl

# --- cannot_check vs missing: an UNRESOLVABLE BRANCH KEY -------------------
# The two ledger legs bottom out in branch_ledger_dir, which returns non-zero
# both when there is no record AND when the branch key cannot be resolved. Only
# the first means "no implementation work"; the second is an infrastructure
# failure where the advisory names the wrong remedy. Under-reporting it as
# `missing` biases the pre-registered rate toward CLEARING the deny-flip, so
# this distinction is asserted behaviorally, not just as wiring.
#
# The fixture keeps _LEDGER_OK=true (the lib sources fine) but makes
# branch_ledger_key fail, which is the only way to isolate key-resolution from
# lib-availability. REVIEW/VERIFY are re-satisfied via invocation evidence
# because the ledger they normally use is exactly what this fixture breaks —
# without that they would deny before Check 0 is ever reached.
_FAKEROOT="$(mktemp -d /tmp/pg-fakeroot-XXXXXX)"
cp -R "${PROJECT_ROOT}/hooks" "${_FAKEROOT}/" 2>/dev/null
[ -d "${PROJECT_ROOT}/config" ] && cp -R "${PROJECT_ROOT}/config" "${_FAKEROOT}/" 2>/dev/null
printf '\nbranch_ledger_key() { return 1; }\n' >> "${_FAKEROOT}/hooks/lib/branch-ledger.sh"

git -C "${_REPO}" checkout -q feat/impl
printf '%s' '{"chain":["requesting-code-review","verification-before-completion","executing-plans"],"current_index":0,"completed":[]}' > "${_COMP}"
printf '%s\n' '["requesting-code-review","verification-before-completion"]' \
    > "$HOME/.claude/.skill-invocation-evidence-${_TOK}"
rm -f "$HOME/.claude/.skill-phase-attest-${_TOK}"
: > "$IMPLEMENT_SHADOW_LOG"

_kout="$( cd "${_REPO}" && _mkinput "" | CLAUDE_PLUGIN_ROOT="${_FAKEROOT}" bash "${_FAKEROOT}/hooks/openspec-guard.sh" 2>/dev/null )"
assert_not_contains "unresolvable-key run still never denies from this leg" \
    "permissionDecision" "${_kout:-}"
assert_equals "unresolvable key still writes a shadow record" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | tr -d ' ')"
assert_equals "unresolvable branch key records ledger as cannot_check" "cannot_check" \
    "$(jq -r '.impl_evidence_detail.ledger' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"
assert_equals "unresolvable branch key records bridge as cannot_check" "cannot_check" \
    "$(jq -r '.impl_evidence_detail.bridge' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"
# Control: the invocation leg does NOT depend on the branch key, so it must
# still read `missing`. Without this, a mutation that hardcoded every leg to
# cannot_check would pass the two assertions above.
assert_equals "invocation leg is unaffected by the branch key" "missing" \
    "$(jq -r '.impl_evidence_detail.invocation' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"
rm -rf "${_FAKEROOT}"
rm -f "$HOME/.claude/.skill-invocation-evidence-${_TOK}"

# --- cannot_check vs missing: a CORRUPT STATE FILE -------------------------
# Same bug class as the unresolvable branch key above, on the other two legs.
# _invoc_has and phase_attested both END in `jq -e ... "$f" >/dev/null 2>&1`,
# so a file that EXISTS but does not parse returns 1 — byte-identical at the
# exit code to "no record". Reporting that as `missing` claims we looked and
# found nothing when we could not look at all, which biases the pre-registered
# rate toward CLEARING the deny-flip (the dangerous direction).
#
# REVIEW/VERIFY are satisfied via .completed here, NOT via invocation evidence:
# this fixture corrupts precisely the file those legs would otherwise read, so
# using it would deny before Check 0 is ever reached.
git -C "${_REPO}" checkout -q feat/impl
printf '%s' '{"chain":["requesting-code-review","verification-before-completion","executing-plans"],"current_index":0,"completed":["requesting-code-review","verification-before-completion"]}' > "${_COMP}"
printf '%s' '{ this is not json' > "$HOME/.claude/.skill-invocation-evidence-${_TOK}"
printf '%s' 'also not json'      > "$HOME/.claude/.skill-phase-attest-${_TOK}"
: > "$IMPLEMENT_SHADOW_LOG"

out="$(run_guard)"
assert_not_contains "corrupt-state run still never denies from this leg" \
    "permissionDecision" "${out:-}"
assert_equals "corrupt state still writes a shadow record" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | tr -d ' ')"
assert_equals "unparseable invocation evidence records cannot_check" "cannot_check" \
    "$(jq -r '.impl_evidence_detail.invocation' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"
assert_equals "unparseable attest file records cannot_check" "cannot_check" \
    "$(jq -r '.impl_evidence_detail.attestation' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"
# Control: the ledger leg reads neither file, so it must still be `missing`.
# Without this, hardcoding every leg to cannot_check would pass the two above.
assert_equals "ledger leg is unaffected by the corrupt state files" "missing" \
    "$(jq -r '.impl_evidence_detail.ledger' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"

# Control 2: a WELL-FORMED but non-array invocation file is checked-and-rejected
# (`type=="array"` fails), which is genuinely `missing`, NOT cannot_check. This
# pins the boundary — without it, "treat every jq failure as cannot_check" would
# pass, and the field would over-report infrastructure failure.
printf '%s' '{"not":"an array"}' > "$HOME/.claude/.skill-invocation-evidence-${_TOK}"
rm -f "$HOME/.claude/.skill-phase-attest-${_TOK}"
: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard)"
assert_equals "well-formed non-array evidence stays missing, not cannot_check" "missing" \
    "$(jq -r '.impl_evidence_detail.invocation' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"
rm -f "$HOME/.claude/.skill-invocation-evidence-${_TOK}"


# --- Deletion-only pushes leave the corpus alone (#229) ---------------------
# A command whose EVERY push deletes a ref ships no source, so measuring
# `material_source` against the checkout HEAD asks about a commit the command
# does not push. Such a record can only be adjudicated a false_block, which
# moves the pre-registered rate for a reason unrelated to the predicate under
# test — so the leg must not fire, and PREDICATE_VERSION is bumped to 4.
: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard 'git push --delete origin feature/x')"
assert_not_contains "deletion-only push raises no IMPLEMENT advisory" "IMPLEMENT:" "${out:-}"
assert_equals "deletion-only push appends no shadow record" "0" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"

# CONTROL: the identical state with an ordinary push MUST still record. Without
# this the cell above passes when the leg is broken outright, or when the
# fixture stopped producing material source at all.
: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard)"
assert_contains "control: ordinary push still raises the advisory" "IMPLEMENT:" "${out:-<empty>}"
assert_equals "control: ordinary push still appends a record" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"

# CONTROL: a deletion must not suppress the leg for a real push in the SAME
# command — the ALL-form guarantee, asserted here rather than assumed from the
# predicate's unit tests.
: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard 'git push --delete origin feature/x; git push origin HEAD')"
assert_contains "deletion + real push still raises the advisory" "IMPLEMENT:" "${out:-<empty>}"
assert_equals "deletion + real push still appends a record" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"

# --- A deletion the STRICT form cannot certify (#245) -----------------------
# `| tail -2` is an unaccountable segment, so `_gc_seg_is_inert` refuses and the
# strict certification is lost -- correctly: it cannot tell `tail` from
# `./deploy.sh`, and the right-hand side of a pipe executes arbitrarily. Before
# this change the subject then fell back to the checkout HEAD and the leg
# asserted "this push edits source" of a command shipping nothing, writing a
# would-block record with a false premise. Two of the twelve v4 would-block
# episodes in the live corpus are exactly this shape, and `2>&1 | tail -N` is
# what an agent naturally writes.
#
# The advisory and the record's membership now follow the WEAKER
# recognised-deletions predicate. Enforcement does NOT: `_SUBJ_DELETION_ONLY`
# still governs the four content-dependent legs from the strict form alone.
: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard 'git push --delete origin feature/x 2>&1 | tail -2')"
assert_not_contains "uncertifiable deletion raises no IMPLEMENT advisory" "IMPLEMENT:" "${out:-}"
assert_equals "uncertifiable deletion records advisory_emitted false" "false" \
    "$(jq -r '.advisory_emitted' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"
# RECORDED, not dropped: "the leg said nothing" and "the event never happened"
# are different states, and the reader must exclude on the field rather than on
# an absence it cannot see.
assert_equals "uncertifiable deletion still appends a record" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"

# CONTROL -- the same command SHAPE carrying a real push keeps the advisory.
# Without it, suppressing the advisory unconditionally passes every cell above.
: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard 'git push origin HEAD 2>&1 | tail -2')"
assert_contains "control: ordinary push with a pipeline stage still advises" "IMPLEMENT:" "${out:-<empty>}"
assert_equals "control: ordinary push records advisory_emitted true" "true" \
    "$(jq -r '.advisory_emitted' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"

# CONTROL -- a deletion MIXED with a real push is deletion-only under neither
# form. This is the case the weaker predicate is allowed to answer, so getting
# it wrong here would be exactly the misuse the design forbids.
: > "$IMPLEMENT_SHADOW_LOG"
out="$(run_guard 'git push --delete origin feature/x 2>&1 | tail -2 && git push origin HEAD')"
assert_contains "control: deletion mixed with a real push still advises" "IMPLEMENT:" "${out:-<empty>}"
assert_equals "control: mixed command records advisory_emitted true" "true" \
    "$(jq -r '.advisory_emitted' "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1)"

# --- Schema 5: harness ids and versions (review-credit-from-evidence, d4) ----
# Every record now carries session_id and tool_use_id from the hook PAYLOAD,
# cc_version from AI_AGENT and acs_version from the plugin's own manifest. A
# stamp that cannot be computed is written EMPTY; it never blocks or drops the
# record. Driven through the REAL guard: the guard computes the stamps, the
# recorder only writes them, so a lib-level cell would test the wrong half.
# AI_AGENT is set or removed explicitly per cell: the harness running this suite
# exports its own, and inheriting it would make every cell depend on that.
_STAMP_ACS="$(jq -r .version "${PROJECT_ROOT}/.claude-plugin/plugin.json")"
_mkpayload() { # [extra-json-object]
    local _x="${1:-}"; [ -n "${_x}" ] || _x='{}'
    jq -nc --arg tp "$_TPATH" --argjson x "${_x}" \
        '{"transcript_path":$tp,"tool_input":{"command":"git push origin HEAD"}} + $x'
}
_stamp_guard() { # <payload> <AI_AGENT value | -unset-> [plugin_root]
    local _root="${3:-${PROJECT_ROOT}}"
    if [ "$2" = "-unset-" ]; then
        ( cd "${_REPO}" && printf '%s' "$1" | env -u AI_AGENT CLAUDE_PLUGIN_ROOT="${_root}" \
            VERIFY_SHADOW_LOG="$HOME/stamp-vs.jsonl" REVIEW_SHADOW_LOG="$HOME/stamp-rs.jsonl" \
            bash "${_root}/hooks/openspec-guard.sh" 2>/dev/null )
    else
        ( cd "${_REPO}" && printf '%s' "$1" | env AI_AGENT="$2" CLAUDE_PLUGIN_ROOT="${_root}" \
            VERIFY_SHADOW_LOG="$HOME/stamp-vs.jsonl" REVIEW_SHADOW_LOG="$HOME/stamp-rs.jsonl" \
            bash "${_root}/hooks/openspec-guard.sh" 2>/dev/null )
    fi
}
_sf() { jq -r "$1" "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | head -1; }   # field of record 1
_IDS='{"session_id":"sess-1","tool_use_id":"toolu_01AbC"}'
# A chain holding ONLY the implementation slot: the REVIEW and VERIFY verdict
# legs then record nothing, so no other recorder's call site computes the
# stamps first and each IMPLEMENT call site is tested on its own (measured: with
# the full chain, deleting the attested site's stamp call stayed green because
# the VERIFY site, which runs earlier, had already filled the globals).
printf '%s' '{"chain":["executing-plans"],"current_index":0,"completed":[]}' > "${_COMP}"

: > "$IMPLEMENT_SHADOW_LOG"; rm -f "$HOME/stamp-vs.jsonl" "$HOME/stamp-rs.jsonl"
out="$(_stamp_guard "$(_mkpayload "${_IDS}")" "claude-code_2-1-308_harness")"
assert_contains "stamps: fixture still raises the advisory (non-vacuous)" "IMPLEMENT:" "${out:-<empty>}"
assert_equals "stamps: no other leg recorded, so no other site stamped first" "absent absent" \
    "$([ -s "$HOME/stamp-vs.jsonl" ] && echo present || echo absent) $([ -s "$HOME/stamp-rs.jsonl" ] && echo present || echo absent)"
assert_equals "stamps: exactly one record" "1" "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
assert_equals "stamps: schema_version is 5" "5" "$(_sf .schema_version)"
assert_equals "stamps: predicate_version is unchanged at 5" "5" "$(_sf .predicate_version)"
assert_equals "stamps: session_id from the payload" "sess-1" "$(_sf .session_id)"
assert_equals "stamps: tool_use_id from the payload" "toolu_01AbC" "$(_sf .tool_use_id)"
assert_equals "stamps: cc_version parsed from AI_AGENT" "2.1.308" "$(_sf .cc_version)"
assert_equals "stamps: acs_version is the plugin manifest's version" "${_STAMP_ACS}" "$(_sf .acs_version)"
assert_not_empty "stamps: acs_version is not vacuously empty" "$(_sf .acs_version)"

# The four keys are always PRESENT, even when empty: a reader must be able to
# tell "stamped empty" (schema 5) from "never stamped" (schema <= 4).
: > "$IMPLEMENT_SHADOW_LOG"
_stamp_guard "$(_mkpayload)" "-unset-" >/dev/null
assert_equals "stamps: AI_AGENT unset => cc_version empty" "" "$(_sf .cc_version)"
assert_equals "stamps: payload without ids => session_id empty" "" "$(_sf .session_id)"
assert_equals "stamps: payload without ids => tool_use_id empty" "" "$(_sf .tool_use_id)"
assert_equals "stamps: empty stamps are present keys, not absent ones" "true true true true" \
    "$(jq -r '[has("session_id"),has("tool_use_id"),has("cc_version"),has("acs_version")] | map(tostring) | join(" ")' \
        "$IMPLEMENT_SHADOW_LOG" | head -1)"
assert_equals "stamps: record without ids is still written" "1" "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"

: > "$IMPLEMENT_SHADOW_LOG"
_stamp_guard "$(_mkpayload "${_IDS}")" "claude-code_x-y_z" >/dev/null
assert_equals "stamps: malformed AI_AGENT => cc_version empty" "" "$(_sf .cc_version)"
assert_equals "stamps: malformed AI_AGENT does not cost the ids" "sess-1" "$(_sf .session_id)"

# ONE definition of the AI_AGENT shape: the guard reuses acs_cc_version
# (hooks/lib/credited-skills.sh), whose `_<suffix>` is optional. So a suffix-
# less value parses, and the stamp must agree with the lib for every shape —
# two parsers that disagree on one input is the paired-site drift class.
: > "$IMPLEMENT_SHADOW_LOG"
_stamp_guard "$(_mkpayload "${_IDS}")" "claude-code_2-1-308" >/dev/null
assert_equals "stamps: suffix-less AI_AGENT parses as the lib parses it" "2.1.308" "$(_sf .cc_version)"
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/credited-skills.sh"
while IFS= read -r _aa; do
    : > "$IMPLEMENT_SHADOW_LOG"
    _stamp_guard "$(_mkpayload "${_IDS}")" "${_aa}" >/dev/null
    assert_equals "stamps: cc_version agrees with acs_cc_version for '${_aa}'" \
        "$(AI_AGENT="${_aa}" acs_cc_version)" "$(_sf .cc_version)"
done <<'AIAGENTS'
claude-code_2-1-308_harness
claude-code_10-0-1_sdk-cli
claude-code_02-1-308_x
claude-code_2-1_x
claude-code_2-1-308-4_x
codex_2-1-308_x
AIAGENTS

# Ids are kept only when they match ^[A-Za-z0-9._-]{1,128}$. A path-shaped or
# space-bearing value is reduced to empty, never copied.
: > "$IMPLEMENT_SHADOW_LOG"
_stamp_guard "$(_mkpayload '{"session_id":"a b/../c","tool_use_id":"toolu_01AbC"}')" "-unset-" >/dev/null
assert_equals "stamps: session_id outside the charset => empty" "" "$(_sf .session_id)"
assert_equals "stamps: a rejected session_id leaves tool_use_id intact" "toolu_01AbC" "$(_sf .tool_use_id)"
: > "$IMPLEMENT_SHADOW_LOG"
_long="$(printf '%0129d' 0)"
_stamp_guard "$(_mkpayload "{\"session_id\":\"${_long}\",\"tool_use_id\":42}")" "-unset-" >/dev/null
assert_equals "stamps: a 129-char id => empty" "" "$(_sf .session_id)"
assert_equals "stamps: a non-string id => empty" "" "$(_sf .tool_use_id)"
: > "$IMPLEMENT_SHADOW_LOG"
_stamp_guard "$(_mkpayload "{\"session_id\":\"$(printf '%0128d' 0)\"}")" "-unset-" >/dev/null
assert_equals "stamps: a 128-char id is kept (boundary control)" "$(printf '%0128d' 0)" "$(_sf .session_id)"
# The guard splits its one jq answer on \x1f. An id CARRYING \x1f must be
# rejected inside jq, or it would shift the fields and forge the next stamp.
: > "$IMPLEMENT_SHADOW_LOG"
_stamp_guard "$(_mkpayload '{"session_id":"a\u001fforged\u001f9.9.9","tool_use_id":"t\nx"}')" "-unset-" >/dev/null
assert_equals "stamps: an id carrying the field separator => empty" "" "$(_sf .session_id)"
assert_equals "stamps: a separator-bearing id cannot forge tool_use_id" "" "$(_sf .tool_use_id)"
assert_equals "stamps: a separator-bearing id cannot forge acs_version" "${_STAMP_ACS}" "$(_sf .acs_version)"

# The attestation-resolved record (#169) is written by the second call site and
# carries the same stamps.
phase_attest "executing-plans" "stamp test" >/dev/null 2>&1
: > "$IMPLEMENT_SHADOW_LOG"; rm -f "$HOME/stamp-vs.jsonl" "$HOME/stamp-rs.jsonl"
_stamp_guard "$(_mkpayload "${_IDS}")" "claude-code_2-1-308_harness" >/dev/null
assert_equals "stamps: attested run recorded no other leg (isolates this site)" "absent absent" \
    "$([ -s "$HOME/stamp-vs.jsonl" ] && echo present || echo absent) $([ -s "$HOME/stamp-rs.jsonl" ] && echo present || echo absent)"
assert_equals "stamps: attested record is the would_block:false one" "false" "$(_sf .would_block)"
assert_equals "stamps: attested record carries session_id" "sess-1" "$(_sf .session_id)"
assert_equals "stamps: attested record carries tool_use_id" "toolu_01AbC" "$(_sf .tool_use_id)"
assert_equals "stamps: attested record carries cc_version" "2.1.308" "$(_sf .cc_version)"
assert_equals "stamps: attested record carries acs_version" "${_STAMP_ACS}" "$(_sf .acs_version)"
rm -f "$HOME/.claude/.skill-phase-attest-${_TOK}"

# Fail-open on the manifest. A plugin root with NO .claude-plugin/ (every
# other entry symlinked to the real checkout) must still write the record with
# its ids; a malformed or non-JSON manifest yields an empty acs_version.
_SROOT="$(mktemp -d /tmp/pg-impl-sroot-XXXXXX)"
for _e in "${PROJECT_ROOT}"/*; do ln -s "${_e}" "${_SROOT}/${_e##*/}"; done
: > "$IMPLEMENT_SHADOW_LOG"
out="$(_stamp_guard "$(_mkpayload "${_IDS}")" "claude-code_2-1-308_harness" "${_SROOT}")"
assert_contains "no manifest: the advisory still fires (non-vacuous)" "IMPLEMENT:" "${out:-<empty>}"
assert_equals "no manifest: the record is still written" "1" "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
assert_equals "no manifest: acs_version empty" "" "$(_sf .acs_version)"
assert_equals "no manifest: session_id survives" "sess-1" "$(_sf .session_id)"
assert_equals "no manifest: tool_use_id survives" "toolu_01AbC" "$(_sf .tool_use_id)"
mkdir -p "${_SROOT}/.claude-plugin"
while IFS='|' read -r _mv _want; do
    printf '%s' "${_mv}" > "${_SROOT}/.claude-plugin/plugin.json"
    : > "$IMPLEMENT_SHADOW_LOG"
    _stamp_guard "$(_mkpayload "${_IDS}")" "-unset-" "${_SROOT}" >/dev/null
    assert_equals "manifest ${_mv}: acs_version is '${_want}'" "${_want}" "$(_sf .acs_version)"
    assert_equals "manifest ${_mv}: session_id survives" "sess-1" "$(_sf .session_id)"
done <<'MANIFESTS'
{"version":"1.2.3"}|1.2.3
{"version":"1.2.3-rc.1"}|1.2.3-rc.1
{"version":"1.2.3+build.7"}|1.2.3+build.7
{"version":"v1.2.3"}|
{"version":"1.2"}|
{"version":"1.2.3\nx"}|
{"version":"1.2.3 x"}|
{"version":123}|
not json|
MANIFESTS
rm -rf "${_SROOT}"

rm -f "$HOME/stamp-vs.jsonl" "$HOME/stamp-rs.jsonl"
printf '%s' '{"chain":["requesting-code-review","verification-before-completion","executing-plans"],"current_index":0,"completed":[]}' \
    > "${_COMP}"

# F5: the stamps cost a jq fork ONLY when a record is about to be written. A
# jq shim on PATH logs each invocation's argv; the stamp read is the only jq
# call loading the plugin manifest with --rawfile (scripts/push-gate-capture.sh,
# run from the guard's EXIT trap, also reads the manifest — with a plain path).
_JQSHIM="$(mktemp -d /tmp/pg-impl-jqshim-XXXXXX)"
_JQREAL="$(command -v jq)"
cat > "${_JQSHIM}/jq" <<SHIM
#!/bin/bash
printf '%s\n' "\$*" >> "${_JQSHIM}/calls"
exec "${_JQREAL}" "\$@"
SHIM
chmod +x "${_JQSHIM}/jq"
_stamp_jq_calls() { grep -F -- '--rawfile' "${_JQSHIM}/calls" 2>/dev/null | grep -c 'claude-plugin/plugin.json' | tr -d ' '; }
_shim_guard() { # <AI_AGENT>
    ( cd "${_REPO}" && _mkpayload "${_IDS}" | env PATH="${_JQSHIM}:${PATH}" AI_AGENT="$1" \
        VERIFY_SHADOW_LOG="${_JQSHIM}/vs.jsonl" REVIEW_SHADOW_LOG="${_JQSHIM}/rs.jsonl" \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null )
}
_nlines() { if [ -f "$1" ]; then grep -c . "$1" | tr -d ' '; else echo 0; fi; }
# This run writes TWO records (IMPLEMENT, and VERIFY on the fixture's unmeasured
# verdict), so "one jq" also pins that the stamps are computed once per run.
: > "$IMPLEMENT_SHADOW_LOG"; : > "${_JQSHIM}/calls"; rm -f "${_JQSHIM}/vs.jsonl"
_shim_guard "claude-code_2-1-308_harness" >/dev/null
assert_equals "F5: the run wrote an IMPLEMENT and a VERIFY record (precondition)" "1 1" \
    "$(_nlines "$IMPLEMENT_SHADOW_LOG") $(_nlines "${_JQSHIM}/vs.jsonl")"
assert_equals "F5: two records in one run read the stamps with exactly one jq" "1" "$(_stamp_jq_calls)"
assert_equals "F5: the second record carries the same stamps" "sess-1 2.1.308" \
    "$(jq -r '"\(.session_id) \(.cc_version)"' "${_JQSHIM}/vs.jsonl" 2>/dev/null)"
assert_equals "F5: the shim saw the record being written (positive control)" "sess-1" "$(_sf .session_id)"
# A passing path that writes no record of ANY leg: real invocation evidence
# satisfies IMPLEMENT, and a chain holding only the implementation slot keeps
# the REVIEW and VERIFY verdict legs (which this fixture's unreviewed,
# unmeasured state would otherwise feed) from recording. All three corpora must
# stay empty, or the cell would be measuring a recorded path.
printf '%s' '{"chain":["executing-plans"],"current_index":0,"completed":[]}' > "${_COMP}"
printf '%s\n' '["executing-plans"]' > "$HOME/.claude/.skill-invocation-evidence-${_TOK}"
: > "$IMPLEMENT_SHADOW_LOG"; : > "${_JQSHIM}/calls"; rm -f "${_JQSHIM}/vs.jsonl" "${_JQSHIM}/rs.jsonl"
out="$(_shim_guard "claude-code_2-1-308_harness")"
assert_not_contains "F5: the no-record path passes (no deny)" '"deny"' "${out:-}"
assert_equals "F5: the no-record path writes no record in any corpus (precondition)" "0 0 0" \
    "$(_nlines "$IMPLEMENT_SHADOW_LOG") $(_nlines "${_JQSHIM}/vs.jsonl") $(_nlines "${_JQSHIM}/rs.jsonl")"
assert_not_empty "F5: the shim intercepted the guard's other jq calls (positive control)" \
    "$(cat "${_JQSHIM}/calls" 2>/dev/null)"
assert_equals "F5: a path writing no record adds no stamp jq" "0" "$(_stamp_jq_calls)"
rm -f "$HOME/.claude/.skill-invocation-evidence-${_TOK}"
printf '%s' '{"chain":["requesting-code-review","verification-before-completion","executing-plans"],"current_index":0,"completed":[]}' \
    > "${_COMP}"
rm -rf "${_JQSHIM}"

# Real producer -> real reader, both schemas. The guard writes a schema-5
# record; scripts/shadow-adjudicate.sh must offer it, and must still offer the
# SAME record rewritten to schema 4 (the four stamps removed) — readers keep
# parsing older schemas.
_ADJR="${PROJECT_ROOT}/scripts/shadow-adjudicate.sh"
_adj_next() { # <log>
    env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT \
        IMPLEMENT_SHADOW_LOG="$1" IMPLEMENT_ADJUDICATION_LOG="$HOME/adj-$$.jsonl" \
        /bin/bash "${_ADJR}" --next 2>&1
}
: > "$IMPLEMENT_SHADOW_LOG"
_stamp_guard "$(_mkpayload "${_IDS}")" "claude-code_2-1-308_harness" >/dev/null
_s5id="$(_sf .record_id)"
assert_not_empty "round trip: the guard wrote a schema-5 record_id" "${_s5id}"
assert_contains "round trip: the reader offers a schema-5 record" "${_s5id}" "$(_adj_next "$IMPLEMENT_SHADOW_LOG")"
jq -c 'del(.session_id,.tool_use_id,.cc_version,.acs_version) | .schema_version = 4' \
    "$IMPLEMENT_SHADOW_LOG" > "$HOME/s4.jsonl"
assert_equals "round trip: the downgraded record really is schema 4 without stamps" "4 false" \
    "$(jq -r '"\(.schema_version) \(has("session_id"))"' "$HOME/s4.jsonl")"
assert_contains "round trip: the reader still offers a schema-4 record" "${_s5id}" "$(_adj_next "$HOME/s4.jsonl")"
rm -f "$HOME/s4.jsonl" "$HOME/adj-$$.jsonl"
export HOME="$_OLDHOME"
rm -rf "${_REPO}" "${_THOME}" 2>/dev/null
print_summary
exit $?

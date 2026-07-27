#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-implement-leg.sh ==="

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

# (a2) The warn must ALSO write a telemetry line — phase_gate_log is defined in
# phase-evidence.sh, which must be sourced BEFORE Check 0 (regression: it was
# only sourced later, making the call a silent no-op and the deny-flip backtest
# baseline empty). HOME is isolated (mktemp) so this reads the test's own log.
_pglog="${HOME}/.claude/.phase-gate-events.log"
assert_contains "IMPLEMENT warn writes a phase-gate telemetry line" "push-implement" "$(cat "${_pglog}" 2>/dev/null || echo '<no log>')"

# (b) After phase_attest executing-plans "test" -> no IMPLEMENT advisory.
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/phase-attest.sh"
phase_attest "executing-plans" "test" >/dev/null 2>&1
out="$(run_guard)"
assert_not_contains "attested executing-plans => no IMPLEMENT advisory" "IMPLEMENT:" "${out:-}"
assert_not_contains "attested path still does not deny"                 '"deny"'     "${out:-}"

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
assert_equals "one shadow record written on a push warn" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
_rec="$(cat "$IMPLEMENT_SHADOW_LOG")"
assert_json_valid "shadow record is valid json" "$IMPLEMENT_SHADOW_LOG"
assert_contains "record names the gate"        '"gate":"push-implement"' "${_rec}"
assert_contains "record marks a would-block"   '"would_block":true'      "${_rec}"
assert_contains "record carries action push"   '"action":"push"'         "${_rec}"
assert_contains "record carries schema_version"    '"schema_version":1'    "${_rec}"
assert_contains "record carries predicate_version" '"predicate_version":1' "${_rec}"
assert_contains "record carries a record_id"   '"record_id":'            "${_rec}"
assert_contains "record carries a ts"          '"ts":'                   "${_rec}"
assert_contains "record carries the transcript pointer" '"transcript_path":' "${_rec}"
assert_not_contains "record never carries raw command text" '"command":' "${_rec}"

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

# KNOWN GAP — issue #161, deliberately NOT fixed here: _flush_push_advisories()
# (hooks/openspec-guard.sh:604) gates the advisory-text FLUSH on _gc_is_push
# only, so the IMPLEMENT advisory computed for a merge (Check 0 itself DOES
# fire for merges per the widened condition at line ~398-399, as the shadow
# record below proves) never reaches stdout. That function is shared with
# staleness/bridge/evaluator-surface advisories too, so widening it has a
# bigger blast radius than this leg and is out of scope for this fix.
#
# This assertion PINS the current (gapped) behavior on purpose: merge stdout
# does NOT carry "IMPLEMENT:" today. When #161 ships push-advisory flushing
# for gh-merge, this assertion MUST BE INVERTED to assert_contains — its
# presence here is a tripwire for that fix, not an endorsement of the gap.
assert_not_contains "KNOWN GAP #161: merge stdout omits IMPLEMENT advisory text (invert on fix)" "IMPLEMENT:" "${out:-}"
# Paired with the above so "no deny" is non-vacuous: stdout for this case is
# expected to be empty outright (nothing to flush), not merely deny-free.
assert_equals "merge stdout is empty (advisory computed but not flushed, per #161 gap)" "" "${out:-}"

assert_not_contains "merge path stays advisory (no deny from this leg)" '"deny"' "${out:-}"
assert_equals "one shadow record written on a merge warn" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
assert_contains "merge record carries action gh-merge" '"action":"gh-merge"' \
    "$(cat "$IMPLEMENT_SHADOW_LOG")"

export HOME="$_OLDHOME"
rm -rf "${_REPO}" "${_THOME}" 2>/dev/null
print_summary
exit $?

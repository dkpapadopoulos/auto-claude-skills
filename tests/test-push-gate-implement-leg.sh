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
assert_not_contains "IMPLEMENT leg emits no permissionDecision at all" "permissionDecision" "${out:-}"

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
assert_not_contains "shadow emission emits no permissionDecision at all" "permissionDecision" "${out:-}"
assert_equals "one shadow record written on a push warn" "1" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" | tr -d ' ')"
_rec="$(cat "$IMPLEMENT_SHADOW_LOG")"
assert_json_valid "shadow record is valid json" "$IMPLEMENT_SHADOW_LOG"
assert_contains "record names the gate"        '"gate":"push-implement"' "${_rec}"
assert_contains "record marks a would-block"   '"would_block":true'      "${_rec}"
assert_contains "record carries action push"   '"action":"push"'         "${_rec}"
assert_contains "record carries schema_version"    '"schema_version":1'    "${_rec}"
assert_contains "record carries predicate_version" '"predicate_version":2' "${_rec}"
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

# Satisfied IMPLEMENT evidence must emit nothing at all.
: > "$IMPLEMENT_SHADOW_LOG"
source "${PROJECT_ROOT}/hooks/lib/phase-attest.sh" 2>/dev/null
phase_attest executing-plans "shadow-negative-test" >/dev/null 2>&1
out="$(run_guard)"
assert_equals "no shadow record when IMPLEMENT evidence exists" "0" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | tr -d ' ')"

# --- #161: merges are measured against the PR, not the local branch -------
# gh is stubbed on PATH: no test may touch the network. The stub reports a PR
# whose diff edits src/app.py, while the fixture branch's own delta is what the
# pre-#161 code would have measured.
#
# Precondition: the previous block (line ~246) left an executing-plans
# attestation on disk, which would satisfy _impl_ok and suppress the whole
# leg (no record at all) regardless of push vs merge. Clear it so this block's
# fixture state matches what the brief assumes: impl-slot in chain, no impl
# evidence. (_COMP already has executing-plans in .chain since line ~142, and
# REVIEW/VERIFY ledger records from lines ~90-91 are untouched, so only the
# IMPLEMENT leg is under test here.)
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
assert_contains "predicate_version bumped to 2"             '"predicate_version":2' "${_rec}"
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
# comment. This is that inversion. The OLD pin (search for "KNOWN GAP #161")
# MUST be deleted in this step — leaving both would assert both directions.
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

# --- Negative-case coverage: record-write condition, false branches --------
# Task 2 review finding: only the TRUE branches of the write gate (materially
# true, or gh-merge) had explicit assertions. Pin both FALSE branches too.

# (a) gh pr merge WITH implement evidence present -> _impl_ok short-circuits
# before the write gate, so no shadow record and no advisory, even though the
# PR resolves and touches material source.
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
assert_equals "attested merge writes no shadow record" "0" \
    "$(wc -l < "$IMPLEMENT_SHADOW_LOG" 2>/dev/null | tr -d ' ')"
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

export HOME="$_OLDHOME"
rm -rf "${_REPO}" "${_THOME}" 2>/dev/null
print_summary
exit $?

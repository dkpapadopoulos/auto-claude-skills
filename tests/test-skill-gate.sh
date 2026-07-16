#!/usr/bin/env bash
# test-skill-gate.sh — phase-enforcement suite (attest lib, evidence lib,
# skill-gate, guard C2 leg). Spec: openspec/changes/phase-enforcement/specs/pdlc-safety/spec.md
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-skill-gate.sh ==="

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/psg-home-XXXXXX)"
mkdir -p "$HOME/.claude"
trap 'rm -rf "$HOME"; export HOME="$_OLDHOME"' EXIT

TOKEN="session-psg-test"
printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
ATTEST_LIB="${PROJECT_ROOT}/hooks/lib/phase-attest.sh"
ATTEST_FILE="$HOME/.claude/.skill-phase-attest-${TOKEN}"

# --- attest: writes reason + ts, merges, refuses gating milestones ---
rm -f "$ATTEST_FILE"
/bin/bash -c ". '${ATTEST_LIB}' && phase_attest product-discovery 'bugfix - covered by brief'" 2>/dev/null
assert_file_exists "attest writes file" "$ATTEST_FILE"
assert_contains "attest records reason" "covered by brief" "$(cat "$ATTEST_FILE")"
/bin/bash -c ". '${ATTEST_LIB}' && phase_attest openspec-ship 'doc-only session'" 2>/dev/null
assert_contains "attest merges second step" "openspec-ship" "$(cat "$ATTEST_FILE")"
assert_contains "attest keeps first step" "product-discovery" "$(cat "$ATTEST_FILE")"

_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attest requesting-code-review 'nope'" 2>/dev/null || _rc=$?
assert_equals "attest refuses requesting-code-review (exit 1)" "1" "$_rc"
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attest verification-before-completion 'nope'" 2>/dev/null || _rc=$?
assert_equals "attest refuses verification-before-completion (exit 1)" "1" "$_rc"
assert_not_contains "gating milestones absent from attest file" "requesting-code-review" "$(cat "$ATTEST_FILE")"

# --- attested reader: true for written step, false for absent, false for gating even if forged ---
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attested '${TOKEN}' product-discovery" || _rc=$?
assert_equals "attested: recorded step -> 0" "0" "$_rc"
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attested '${TOKEN}' brainstorming" || _rc=$?
assert_equals "attested: absent step -> 1" "1" "$_rc"
# Forge a gating-milestone entry by direct file write (Scenario 3, reader-side lock)
jq '. + {"requesting-code-review":{"reason":"forged","ts":"x"}}' "$ATTEST_FILE" > "$ATTEST_FILE.t" && mv "$ATTEST_FILE.t" "$ATTEST_FILE"
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attested '${TOKEN}' requesting-code-review" || _rc=$?
assert_equals "attested: forged gating milestone -> 1 (reader lock)" "1" "$_rc"

# --- attest: pre-existing 0-byte file must not brick attestation ---
: > "$ATTEST_FILE"
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attest openspec-ship 'empty-file recovery'" 2>/dev/null || _rc=$?
assert_equals "attest recovers from 0-byte file (exit 0)" "0" "$_rc"
assert_contains "attest recorded after 0-byte recovery" "empty-file recovery" "$(cat "$ATTEST_FILE" 2>/dev/null)"

# --- attest: whitespace-only and non-object files must not brick attestation ---
printf '   ' > "$ATTEST_FILE"
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attest openspec-ship 'whitespace recovery'" 2>/dev/null || _rc=$?
assert_equals "attest recovers from whitespace-only file (exit 0)" "0" "$_rc"
printf '[1,2,3]' > "$ATTEST_FILE"
_rc=0; /bin/bash -c ". '${ATTEST_LIB}' && phase_attest openspec-ship 'array recovery'" 2>/dev/null || _rc=$?
assert_equals "attest recovers from non-object JSON file (exit 0)" "0" "$_rc"
assert_contains "attest recorded after array recovery" "array recovery" "$(cat "$ATTEST_FILE" 2>/dev/null)"

# --- evidence predicate: invocation-record / ledger / attested / NEVER .completed ---
# NOTE: the 0-byte/whitespace/array recovery asserts above each overwrite
# $ATTEST_FILE, so the product-discovery + forged requesting-code-review
# entries they left no longer survive by this point — re-establish exactly
# that state here rather than assume it carries over.
/bin/bash -c ". '${ATTEST_LIB}' && phase_attest product-discovery 'evidence predicate setup'" 2>/dev/null
jq '. + {"requesting-code-review":{"reason":"forged","ts":"x"}}' "$ATTEST_FILE" > "$ATTEST_FILE.t" && mv "$ATTEST_FILE.t" "$ATTEST_FILE"

EVID_LIB="${PROJECT_ROOT}/hooks/lib/phase-evidence.sh"
COMP_FILE="$HOME/.claude/.skill-composition-state-${TOKEN}"
INVOC_FILE="$HOME/.claude/.skill-invocation-evidence-${TOKEN}"
printf '{"chain":["brainstorming","writing-plans","subagent-driven-development","requesting-code-review","verification-before-completion","openspec-ship","finishing-a-development-branch"],"completed":["brainstorming","writing-plans"],"current_index":1}\n' > "$COMP_FILE"
printf '["brainstorming"]\n' > "$INVOC_FILE"

_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' brainstorming ''" || _rc=$?
assert_equals "evidence: invocation-record step -> 0" "0" "$_rc"
# THE CODEX-#2 PIN: writing-plans is in .completed (walker back-fill) but NOT
# in the invocation record -> NOT satisfied. Walker anchoring is not evidence.
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' writing-plans ''" || _rc=$?
assert_equals "evidence: walker-backfilled .completed does NOT satisfy -> 1" "1" "$_rc"
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' product-discovery ''" || _rc=$?
assert_equals "evidence: attested step -> 0" "0" "$_rc"
# forged gating attestation must NOT satisfy (Scenario 3 via shared predicate)
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' requesting-code-review ''" || _rc=$?
assert_equals "evidence: forged gating attest does not satisfy -> 1" "1" "$_rc"
# implementation-slot alias: evidence for SDD satisfies executing-plans (codex #3)
printf '["brainstorming","subagent-driven-development"]\n' > "$INVOC_FILE"
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' executing-plans ''" || _rc=$?
assert_equals "evidence: impl-slot alias satisfies sibling -> 0" "0" "$_rc"
# malformed invocation record: leg degrades, attested leg still works
printf 'NOT JSON' > "$INVOC_FILE"
_rc=0; /bin/bash -c ". '${EVID_LIB}' && phase_step_satisfied '${TOKEN}' product-discovery ''" || _rc=$?
assert_equals "evidence: malformed record, attested leg still works -> 0" "0" "$_rc"
printf '["brainstorming"]\n' > "$INVOC_FILE"

# --- completion hook: writes invocation record + all-step ledger ---
COMPLETION_HOOK="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"
_CH_REPO="$(mktemp -d /tmp/psg-ch-XXXXXX)"
( cd "$_CH_REPO" && git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m init )
_ch_payload() {  # $1=skill $2=is_error
    printf '{"transcript_path":"","tool_response":{"is_error":%s},"tool_input":{"skill":"%s"},"cwd":"%s"}' "$2" "$1" "$_CH_REPO"
}
rm -f "$INVOC_FILE"
_ch_payload superpowers:writing-plans false | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$COMPLETION_HOOK" >/dev/null 2>&1
assert_contains "completion hook appends bare name to invocation record" "writing-plans" "$(cat "$INVOC_FILE" 2>/dev/null)"
_ch_payload superpowers:openspec-ship true | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$COMPLETION_HOOK" >/dev/null 2>&1
assert_not_contains "errored Skill return NOT recorded" "openspec-ship" "$(cat "$INVOC_FILE" 2>/dev/null)"
rm -rf "$_CH_REPO"
printf '["brainstorming"]\n' > "$INVOC_FILE"

print_summary

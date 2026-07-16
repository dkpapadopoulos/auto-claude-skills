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

print_summary

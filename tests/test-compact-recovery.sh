#!/usr/bin/env bash
# test-compact-recovery.sh — compact-recovery prompt-carrier suite.
# Spec: openspec/changes/compact-recovery-prompt-carrier/specs/compact-recovery/spec.md
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-compact-recovery.sh ==="

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/crc-home-XXXXXX)"
mkdir -p "$HOME/.claude"
trap 'rm -rf "$HOME"; export HOME="$_OLDHOME"' EXIT

TOKEN="session-test-crc"
RENDER_LIB="${PROJECT_ROOT}/hooks/lib/compact-recovery-render.sh"

_seed_full_state() {
    printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
    printf '# Team checkpoint body\n' > "$HOME/.claude/team-checkpoint.md"
    printf '{"chain":["superpowers:brainstorming","superpowers:writing-plans"],"completed":["superpowers:brainstorming"],"current_index":1}\n' \
        > "$HOME/.claude/.skill-composition-state-${TOKEN}"
    printf 'fix auto-compact recovery :: out-of-scope: session-rules ledger\n' \
        > "$HOME/.claude/.skill-confirmed-intent-${TOKEN}"
    printf '{"changes":{"compact-recovery-prompt-carrier":{"capability_slug":"compact-recovery","archived_at":null},"old-archived-change":{"capability_slug":"x","archived_at":"2026-01-01"}}}\n' \
        > "$HOME/.claude/.skill-openspec-state-${TOKEN}"
}
_clear_state() {
    rm -f "$HOME/.claude/team-checkpoint.md" \
          "$HOME/.claude/.skill-composition-state-${TOKEN}" \
          "$HOME/.claude/.skill-confirmed-intent-${TOKEN}" \
          "$HOME/.claude/.skill-openspec-state-${TOKEN}" \
          "$HOME/.claude/.skill-compact-pending-${TOKEN}" 2>/dev/null
}

# --- renderer: full state emits all sections ---
_clear_state; _seed_full_state
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_contains "renderer emits team checkpoint" "Team checkpoint body" "$_out"
assert_contains "renderer emits composition chain" "superpowers:writing-plans" "$_out"
assert_contains "renderer emits confirmed intent" "fix auto-compact recovery" "$_out"
assert_contains "renderer emits non-archived change slug" "compact-recovery-prompt-carrier" "$_out"
assert_not_contains "renderer omits archived changes" "old-archived-change" "$_out"

# --- renderer: empty state emits nothing ---
_clear_state
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_equals "renderer emits nothing with no state" "" "$_out"

# --- renderer: malformed state degrades to remaining sections ---
_clear_state; _seed_full_state
printf 'NOT JSON{' > "$HOME/.claude/.skill-composition-state-${TOKEN}"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_contains "renderer survives malformed composition state" "fix auto-compact recovery" "$_out"
assert_not_contains "renderer does not leak malformed content" "NOT JSON" "$_out"

# --- renderer: empty token still renders team checkpoint ---
_clear_state
printf '# Team checkpoint body\n' > "$HOME/.claude/team-checkpoint.md"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '' manual" 2>/dev/null)"
assert_contains "empty token renders token-independent sections" "Team checkpoint body" "$_out"

print_summary

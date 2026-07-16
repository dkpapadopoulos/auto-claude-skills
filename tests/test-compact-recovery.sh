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

# --- renderer: findings 1 + 4 — intent (and team checkpoint) degrade independently
# of jq; composition/openspec sections require jq and are absent without it. ---
_clear_state; _seed_full_state
_NOJQ_BIN="$(mktemp -d /tmp/crc-nojq-XXXXXX)"
ln -s /bin/cat "$_NOJQ_BIN/cat"
ln -s /usr/bin/head "$_NOJQ_BIN/head"
_out="$(env PATH="$_NOJQ_BIN" /bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
_status=$?
assert_equals "finding4: no-jq renderer exits 0" "0" "$_status"
assert_contains "finding4: no-jq renderer still emits team checkpoint" "Team checkpoint body" "$_out"
assert_contains "finding1: no-jq renderer still emits confirmed intent" "fix auto-compact recovery" "$_out"
assert_not_contains "finding1: no-jq renderer omits composition section (needs jq)" "superpowers:writing-plans" "$_out"
assert_not_contains "finding1: no-jq renderer omits openspec changes (needs jq)" "compact-recovery-prompt-carrier" "$_out"
rm -rf "$_NOJQ_BIN"

# --- renderer: finding 2 — negative current_index must not jq-wrap to the last
# chain element; it must clamp to "unknown". ---
_clear_state
printf '{"chain":["step-a","step-b"],"completed":["step-a"],"current_index":-1}\n' \
    > "$HOME/.claude/.skill-composition-state-${TOKEN}"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_contains "finding2: negative current_index clamps to unknown" "Current step: unknown" "$_out"
assert_not_contains "finding2: negative current_index does not name last chain element as current" "Current step: step-b" "$_out"

# --- renderer: finding 3 — openspec changes summary bounded to 6, deterministic
# survivors (jq to_entries preserves insertion order: slug-1..slug-6 survive). ---
_clear_state
_changes_json='{"changes":{'
_i=1
while [ "$_i" -le 8 ]; do
    _slug="$(printf 'slug-%02d' "$_i")"
    _changes_json="${_changes_json}\"${_slug}\":{\"archived_at\":null}"
    [ "$_i" -lt 8 ] && _changes_json="${_changes_json},"
    _i=$((_i + 1))
done
_changes_json="${_changes_json}}}"
printf '%s\n' "$_changes_json" > "$HOME/.claude/.skill-openspec-state-${TOKEN}"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_contains "finding3: bounded changes keeps slug-01" "slug-01" "$_out"
assert_contains "finding3: bounded changes keeps slug-06" "slug-06" "$_out"
assert_not_contains "finding3: bounded changes drops slug-07" "slug-07" "$_out"
assert_not_contains "finding3: bounded changes drops slug-08" "slug-08" "$_out"

# --- finding 1 (CRITICAL): hooks invoked directly by hooks.json (no `bash`
# prefix) must carry the executable bit, or production sees exit 126. ---
PRE_HOOK="${PROJECT_ROOT}/hooks/pre-compact-hook.sh"
SESSIONSTART_HOOK="${PROJECT_ROOT}/hooks/compact-recovery-hook.sh"
PROMPTCARRIER_HOOK="${PROJECT_ROOT}/hooks/compact-recovery-prompt-hook.sh"
assert_equals "finding1: pre-compact hook is executable" "yes" "$([ -x "$PRE_HOOK" ] && echo yes || echo no)"
assert_equals "finding1: SessionStart compact-recovery hook is executable" "yes" "$([ -x "$SESSIONSTART_HOOK" ] && echo yes || echo no)"
assert_equals "finding1: UserPromptSubmit prompt-carrier hook is executable" "yes" "$([ -x "$PROMPTCARRIER_HOOK" ] && echo yes || echo no)"

# --- pre-compact: writes marker + log even with cozempic absent ---
_clear_state
printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
_fake_transcript="$HOME/fake-transcript.jsonl"
printf '{"type":"user"}\n' > "$_fake_transcript"
printf '{"session_id":"s1","transcript_path":"%s","trigger":"auto"}' "$_fake_transcript" \
    | PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PRE_HOOK" >/dev/null 2>&1
assert_equals "pre-compact exits 0 without cozempic" "0" "$?"
assert_file_exists "pre-compact logs event without cozempic" "$HOME/.claude/.compact-events.log"

# --- finding 2/3 (payload-first token resolution, issue #51): the token MUST
# derive from the payload's own transcript_path via
# resolve_session_token_from_transcript (session-<basename .jsonl>); the
# shared singleton is a fallback ONLY, never checked first. Name the fake
# transcript so its derived token equals TOKEN, and seed the singleton with a
# DIFFERENT token to prove precedence — this pins singleton-first as a
# regression. ---
_WRONG_TOKEN="session-WRONG-SINGLETON"
_clear_state
rm -f "$HOME/.claude/.skill-compact-pending-${_WRONG_TOKEN}" 2>/dev/null
printf '%s' "$_WRONG_TOKEN" > "$HOME/.claude/.skill-session-token"
_derived_transcript="$HOME/test-crc.jsonl"
printf '{"type":"user"}\n' > "$_derived_transcript"
printf '{"session_id":"s1","transcript_path":"%s","trigger":"auto"}' "$_derived_transcript" \
    | PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PRE_HOOK" >/dev/null 2>&1
assert_file_exists "finding2/3: payload-derived token marker exists at TOKEN" "$HOME/.claude/.skill-compact-pending-${TOKEN}"
assert_equals "finding2/3: singleton token marker NOT written (payload wins)" "no" \
    "$([ -f "$HOME/.claude/.skill-compact-pending-${_WRONG_TOKEN}" ] && echo yes || echo no)"
_marker_body="$(cat "$HOME/.claude/.skill-compact-pending-${TOKEN}" 2>/dev/null)"
assert_contains "marker records the trigger" "trigger=auto" "$_marker_body"
rm -f "$HOME/.claude/.skill-compact-pending-${_WRONG_TOKEN}" 2>/dev/null

# --- finding 2/3 fallback: when the payload's transcript_path resolves to
# nothing (missing/empty), the singleton token IS used. ---
_clear_state
printf '%s' "$_WRONG_TOKEN" > "$HOME/.claude/.skill-session-token"
printf '{"session_id":"s1","transcript_path":"","trigger":"manual"}' \
    | PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PRE_HOOK" >/dev/null 2>&1
assert_file_exists "finding2/3 fallback: singleton token used when payload derives nothing" \
    "$HOME/.claude/.skill-compact-pending-${_WRONG_TOKEN}"
rm -f "$HOME/.claude/.skill-compact-pending-${_WRONG_TOKEN}" 2>/dev/null

# --- prompt-carrier hook ---
PROMPT_HOOK="${PROJECT_ROOT}/hooks/compact-recovery-prompt-hook.sh"
# NOTE: uses $_derived_transcript (session-test-crc == $TOKEN), NOT
# $_fake_transcript (derives session-fake-transcript) — the latter would
# silently look up the wrong marker and test nothing on the positive path.
_payload() { printf '{"transcript_path":"%s","prompt":"proceed"}' "$_derived_transcript"; }

# no marker -> silent
_clear_state
printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
assert_equals "prompt-carrier silent with no marker" "" "$_out"

# marker + state -> emits recovery JSON and consumes marker
_clear_state; _seed_full_state
printf '%s trigger=auto\n' "2026-07-15T00:00:00Z" > "$HOME/.claude/.skill-compact-pending-${TOKEN}"
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
_json_status=1
printf '%s' "$_out" | jq empty >/dev/null 2>&1 && _json_status=0
assert_equals "prompt-carrier emits valid JSON" "0" "$_json_status"
assert_contains "prompt-carrier envelope has hookSpecificOutput key" '"hookSpecificOutput"' "$_out"
assert_contains "prompt-carrier envelope names UserPromptSubmit event" '"hookEventName":"UserPromptSubmit"' "$_out"
# --- finding 3 (emit guard): static envelope-shape pin. additionalContext MUST
# always be a JSON string — this is the regression pin for the empty-jq-
# substitution bug (jq -Rs failing would previously still be substituted,
# producing a malformed/empty additionalContext value). ---
assert_equals "finding3: additionalContext is a JSON string (envelope shape)" "0" \
    "$(printf '%s' "$_out" | jq -e '.hookSpecificOutput.additionalContext | type == "string"' >/dev/null 2>&1; echo $?)"
assert_contains "prompt-carrier emits recovery block" "Post-Compaction State Recovery" "$_out"
assert_contains "prompt-carrier carries confirmed intent" "fix auto-compact recovery" "$_out"
assert_equals "prompt-carrier consumes the marker" "no" \
    "$([ -f "$HOME/.claude/.skill-compact-pending-${TOKEN}" ] && echo yes || echo no)"

# second run after consumption -> silent (no double injection)
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
assert_equals "prompt-carrier silent after marker consumed" "" "$_out"

# foreign-token marker -> untouched and silent
_clear_state
printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
printf 'x trigger=auto\n' > "$HOME/.claude/.skill-compact-pending-session-OTHER"
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
assert_equals "prompt-carrier ignores foreign-session marker" "" "$_out"
assert_file_exists "foreign marker left in place" "$HOME/.claude/.skill-compact-pending-session-OTHER"
rm -f "$HOME/.claude/.skill-compact-pending-session-OTHER"

# stale marker (>24h) -> consumed silently
_clear_state; _seed_full_state
printf 'x trigger=auto\n' > "$HOME/.claude/.skill-compact-pending-${TOKEN}"
touch -t 202601010000 "$HOME/.claude/.skill-compact-pending-${TOKEN}"
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
assert_equals "stale marker suppressed" "" "$_out"
assert_equals "stale marker consumed" "no" \
    "$([ -f "$HOME/.claude/.skill-compact-pending-${TOKEN}" ] && echo yes || echo no)"

# --- SessionStart hook: renderer payload + marker consumption ---
SS_HOOK="${PROJECT_ROOT}/hooks/compact-recovery-hook.sh"
_clear_state; _seed_full_state
printf 'x trigger=manual\n' > "$HOME/.claude/.skill-compact-pending-${TOKEN}"
_out="$(printf '{"transcript_path":"%s","source":"compact"}' "$_derived_transcript" \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$SS_HOOK" 2>/dev/null)"
assert_contains "SessionStart emits composition section" "Composition Recovery" "$_out"
assert_contains "SessionStart carries confirmed intent" "fix auto-compact recovery" "$_out"
assert_contains "SessionStart carries openspec changes" "compact-recovery-prompt-carrier" "$_out"
assert_equals "SessionStart consumes the marker" "no" \
    "$([ -f "$HOME/.claude/.skill-compact-pending-${TOKEN}" ] && echo yes || echo no)"

# e2e conformance: everything pre-compact checkpointed reappears (Scenario 1+2)
_clear_state; _seed_full_state
printf '{"session_id":"s1","transcript_path":"%s","trigger":"auto"}' "$_derived_transcript" \
    | PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PRE_HOOK" >/dev/null 2>&1
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
for _needle in "superpowers:writing-plans" "fix auto-compact recovery" "compact-recovery-prompt-carrier"; do
    assert_contains "e2e survival: ${_needle}" "${_needle}" "$_out"
done

# --- finding 2 (marker GC): stale .skill-compact-pending-* markers must be
# pruned by session-start-hook's age-based find alongside composition/openspec
# state; a fresh marker (recent mtime) must survive. Uses the real hook, not a
# mock, per the finding's instructions. ---
echo "--- finding2: stale compact-pending marker pruned by session-start ---"
SESSION_START_HOOK="${PROJECT_ROOT}/hooks/session-start-hook.sh"
_clear_state
_STALE_MARKER="$HOME/.claude/.skill-compact-pending-session-orphan-old"
_FRESH_MARKER="$HOME/.claude/.skill-compact-pending-session-fresh-recent"
printf 'x trigger=auto\n' > "$_STALE_MARKER"
printf 'x trigger=auto\n' > "$_FRESH_MARKER"
touch -t 200001010000 "$_STALE_MARKER" 2>/dev/null || touch -d "2000-01-01 00:00:00" "$_STALE_MARKER" 2>/dev/null || true
CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$SESSION_START_HOOK" </dev/null >/dev/null 2>&1 || true
assert_equals "finding2: stale compact-pending marker pruned" "no" \
    "$([ -f "$_STALE_MARKER" ] && echo yes || echo no)"
assert_equals "finding2: fresh compact-pending marker preserved" "yes" \
    "$([ -f "$_FRESH_MARKER" ] && echo yes || echo no)"
rm -f "$_STALE_MARKER" "$_FRESH_MARKER" 2>/dev/null

print_summary

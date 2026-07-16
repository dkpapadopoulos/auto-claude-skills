# Compact-Recovery Prompt-Carrier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Post-compaction state recovery fires on AUTO compaction again (dead since Claude Code ~2.1.179) and the recovery payload carries confirmed intent + active OpenSpec changes.

**Architecture:** PreCompact (still fires on auto — proven) arms a per-session-token marker file; a NEW second UserPromptSubmit hook consumes the marker on the next prompt and injects recovery context; the existing SessionStart(compact) hook (manual `/compact` only) consumes it first when it fires. One shared renderer lib feeds both emitters. Spec: `openspec/changes/compact-recovery-prompt-carrier/`.

**Tech Stack:** Bash 3.2 (`/bin/bash`), jq (optional at runtime — all paths fail open without it), repo test harness (`tests/test-helpers.sh`).

## Global Constraints

- Bash 3.2 compatible: no associative arrays; NEVER quote operands inside `$(( ))`; validate numerics with `[[ "$V" =~ ^[0-9]+$ ]]` before arithmetic.
- Every hook path fails open: any error → exit 0; no `set -e`; guard every `source` with `2>/dev/null || true` (ERR-trap + unguarded-source gotcha).
- New prompt-path hook common case must cost ~one glob test: no stdin read, no jq fork before the marker existence check.
- Marker/state files are session-token-scoped: `~/.claude/.skill-compact-pending-<token>`; token resolution is payload-first via `resolve_session_token_from_transcript`, singleton fallback.
- jq strings use `\u`-escapes for control chars, never raw bytes.
- Syntax-check every touched hook with `/bin/bash -n` AND run tests under `/bin/bash`.
- `hooks/lib/compact-recovery-render.sh` is advisory-only — do NOT add it to `_GATE_ENFORCE_LIBS`.
- Commits: `<type>: <description>`, each ending with the Co-Authored-By trailer.

---

### Task 1: Shared renderer lib

**Files:**
- Create: `hooks/lib/compact-recovery-render.sh`
- Test: `tests/test-compact-recovery.sh` (new — created in this task, extended by later tasks)

**Interfaces:**
- Produces: `render_compact_recovery <session-token> [trigger]` — prints the recovery block to stdout; prints NOTHING when no recoverable state exists; never non-zero-exits the caller. Later tasks source this file and call this function.

- [ ] **Step 1: Write the failing tests**

Create `tests/test-compact-recovery.sh`:

```bash
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
assert_contains "$_out" "Team checkpoint body" "renderer emits team checkpoint"
assert_contains "$_out" "superpowers:writing-plans" "renderer emits composition chain"
assert_contains "$_out" "fix auto-compact recovery" "renderer emits confirmed intent"
assert_contains "$_out" "compact-recovery-prompt-carrier" "renderer emits non-archived change slug"
assert_not_contains "$_out" "old-archived-change" "renderer omits archived changes"

# --- renderer: empty state emits nothing ---
_clear_state
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_equals "" "$_out" "renderer emits nothing with no state"

# --- renderer: malformed state degrades to remaining sections ---
_clear_state; _seed_full_state
printf 'NOT JSON{' > "$HOME/.claude/.skill-composition-state-${TOKEN}"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '${TOKEN}' auto" 2>/dev/null)"
assert_contains "$_out" "fix auto-compact recovery" "renderer survives malformed composition state"
assert_not_contains "$_out" "NOT JSON" "renderer does not leak malformed content"

# --- renderer: empty token still renders team checkpoint ---
_clear_state
printf '# Team checkpoint body\n' > "$HOME/.claude/team-checkpoint.md"
_out="$(/bin/bash -c ". '${RENDER_LIB}' && render_compact_recovery '' manual" 2>/dev/null)"
assert_contains "$_out" "Team checkpoint body" "empty token renders token-independent sections"

print_summary
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd .claude/worktrees/compact-recovery-carrier && /bin/bash tests/test-compact-recovery.sh < /dev/null`
Expected: FAIL (renderer lib does not exist; every assert fails).

- [ ] **Step 3: Implement the renderer**

Create `hooks/lib/compact-recovery-render.sh`:

```bash
#!/bin/bash
# compact-recovery-render.sh — shared post-compaction recovery renderer.
# Sourced by compact-recovery-hook.sh (SessionStart, manual /compact) and
# compact-recovery-prompt-hook.sh (UserPromptSubmit prompt-carrier).
# render_compact_recovery <token> [trigger] prints the recovery block to
# stdout, or nothing when no recoverable state exists. Fail-open: every
# sub-render degrades independently; never exits the caller.
# Advisory-only output (NOT gate enforcement) — deliberately excluded from
# the _GATE_ENFORCE_LIBS canary list, like consol-marker.sh.
# Spec: openspec/changes/compact-recovery-prompt-carrier.

render_compact_recovery() {
    local _token="${1:-}"
    local _trigger="${2:-}"
    local _sections=""

    # --- Team checkpoint (token-independent) ---
    local _ckpt="${HOME}/.claude/team-checkpoint.md"
    if [ -f "$_ckpt" ]; then
        local _team=""
        _team="$(cat "$_ckpt" 2>/dev/null)" || _team=""
        if [ -n "$_team" ]; then
            _sections="=== Team State Recovery (from pre-compaction checkpoint) ===
${_team}
=== End Team State Recovery ==="
        fi
    fi

    if [ -n "$_token" ] && command -v jq >/dev/null 2>&1; then
        # --- Composition chain state (single jq fork; empty when no chain) ---
        local _comp="${HOME}/.claude/.skill-composition-state-${_token}"
        if [ -f "$_comp" ]; then
            local _chain=""
            _chain="$(jq -r '
                if ((.chain // []) | length) > 0 then
                  "Chain: "        + (.chain | join(" -> "))            + "\n" +
                  "Completed: "    + ((.completed // []) | join(", "))  + "\n" +
                  "Current step: " + (.chain[.current_index // 0] // "unknown") + "\n" +
                  "Resume from: "  + (.chain[.current_index // 0] // "unknown")
                else empty end' "$_comp" 2>/dev/null)" || _chain=""
            if [ -n "$_chain" ]; then
                [ -n "$_sections" ] && _sections="${_sections}
"
                _sections="${_sections}=== Composition Recovery (from pre-compaction state) ===
${_chain}
=== End Composition Recovery ==="
            fi
        fi

        # --- Confirmed intent (marker file; path owned by openspec-state.sh) ---
        local _intent_file="${HOME}/.claude/.skill-confirmed-intent-${_token}"
        if [ -f "$_intent_file" ]; then
            local _intent=""
            _intent="$(head -c 2048 "$_intent_file" 2>/dev/null)" || _intent=""
            if [ -n "$_intent" ]; then
                [ -n "$_sections" ] && _sections="${_sections}
"
                _sections="${_sections}Confirmed intent (persisted pre-compaction): ${_intent}"
            fi
        fi

        # --- Active OpenSpec changes (bounded to 6; single jq fork) ---
        local _ostate="${HOME}/.claude/.skill-openspec-state-${_token}"
        if [ -f "$_ostate" ]; then
            local _changes=""
            _changes="$(jq -r '
                [.changes // {} | to_entries[]
                  | select(.value.archived_at == null)
                  | "- " + .key
                    + ((.value.capability_slug // "") | if . == "" then "" else " (capability: " + . + ")" end)
                ] | .[0:6] | join("\n")' "$_ostate" 2>/dev/null)" || _changes=""
            if [ -n "$_changes" ]; then
                [ -n "$_sections" ] && _sections="${_sections}
"
                _sections="${_sections}Active OpenSpec changes:
${_changes}"
            fi
        fi
    fi

    [ -z "$_sections" ] && return 0

    printf '%s\n' "=== Post-Compaction State Recovery${_trigger:+ (trigger=${_trigger})} ===
Reference state restored from pre-compaction checkpoints. Verify against the repo before acting on it.
${_sections}
=== End Post-Compaction State Recovery ==="
    return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/bin/bash tests/test-compact-recovery.sh < /dev/null`
Expected: PASS (all asserts), `All tests passed.`

- [ ] **Step 5: Syntax-check and commit**

```bash
/bin/bash -n hooks/lib/compact-recovery-render.sh
git add hooks/lib/compact-recovery-render.sh tests/test-compact-recovery.sh
git commit -m "feat: shared post-compaction recovery renderer (intent + openspec changes)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: PreCompact arms the marker (and logs before dependency checks)

**Files:**
- Modify: `hooks/pre-compact-hook.sh` (full body reorder — 39 lines)
- Test: `tests/test-compact-recovery.sh` (append)

**Interfaces:**
- Produces: `~/.claude/.skill-compact-pending-<token>` containing `<utc-ts> trigger=<auto|manual|unknown>`. Tasks 3 and 4 consume it.

- [ ] **Step 1: Append failing tests**

Append to `tests/test-compact-recovery.sh` (before `print_summary`):

```bash
# --- pre-compact: writes marker + log even with cozempic absent ---
PRE_HOOK="${PROJECT_ROOT}/hooks/pre-compact-hook.sh"
_clear_state
printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
_fake_transcript="$HOME/fake-transcript.jsonl"
printf '{"type":"user"}\n' > "$_fake_transcript"
printf '{"session_id":"s1","transcript_path":"%s","trigger":"auto"}' "$_fake_transcript" \
    | PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PRE_HOOK" >/dev/null 2>&1
assert_equals "0" "$?" "pre-compact exits 0 without cozempic"
assert_file_exists "$HOME/.claude/.skill-compact-pending-${TOKEN}" "pre-compact writes pending marker without cozempic"
_marker_body="$(cat "$HOME/.claude/.skill-compact-pending-${TOKEN}" 2>/dev/null)"
assert_contains "$_marker_body" "trigger=auto" "marker records the trigger"
assert_file_exists "$HOME/.claude/.compact-events.log" "pre-compact logs event without cozempic"
```

Note: `PATH="/usr/bin:/bin"` keeps jq visible (`/usr/bin/jq` on macOS; if `command -v jq` resolves elsewhere on the machine, extend PATH minimally rather than including cozempic's dir).

- [ ] **Step 2: Run to verify the new asserts fail**

Run: `/bin/bash tests/test-compact-recovery.sh < /dev/null`
Expected: Task-1 asserts PASS; new asserts FAIL (current hook exits before logging when cozempic is missing, and never writes a marker).

- [ ] **Step 3: Reorder the hook and add the marker write**

Replace the full body of `hooks/pre-compact-hook.sh` with:

```bash
#!/bin/bash
# pre-compact-hook.sh — log compaction, arm the recovery marker, then
# checkpoint/prune via cozempic (optional dependency).
# Runs on both auto and manual compaction. Fail-open: errors exit 0.
#
# Called by Claude Code PreCompact hook. stdin receives JSON with:
#   session_id, transcript_path, trigger ("auto"|"manual"), cwd
#
# ORDER MATTERS: logging + marker MUST precede the cozempic dependency
# check — auto-compaction recovery rides the marker (prompt-carrier; see
# openspec/changes/compact-recovery-prompt-carrier) and must work on
# machines without cozempic.

set -o pipefail

# --- Read hook input ---
INPUT="$(cat)" || INPUT=""
TRANSCRIPT_PATH=""
TRIGGER="unknown"
if command -v jq >/dev/null 2>&1; then
    _F="$(printf '%s' "$INPUT" | jq -r '[.transcript_path // "", .trigger // "unknown"] | join("\u001f")' 2>/dev/null)" || _F=""
    TRANSCRIPT_PATH="${_F%%$'\x1f'*}"
    TRIGGER="${_F#*$'\x1f'}"
fi

# --- Log compaction event (for future adaptive calibration) ---
LOG_FILE="$HOME/.claude/.compact-events.log"
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    FILE_SIZE=$(stat -f%z "$TRANSCRIPT_PATH" 2>/dev/null || stat -c%s "$TRANSCRIPT_PATH" 2>/dev/null || echo "unknown")
    printf '%s trigger=%s size_bytes=%s path=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TRIGGER" "$FILE_SIZE" "$TRANSCRIPT_PATH" >> "$LOG_FILE" 2>/dev/null
fi

# --- Arm the post-compaction recovery marker (prompt-carrier) ---
# Payload-first token resolution (issue #51); singleton fallback.
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
if [ -f "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_session_token_from_transcript >/dev/null 2>&1 && \
        _SESSION_TOKEN="$(resolve_session_token_from_transcript "${TRANSCRIPT_PATH}")"
fi
[ -z "$_SESSION_TOKEN" ] && [ -f "${HOME}/.claude/.skill-session-token" ] && \
    _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
if [ -n "$_SESSION_TOKEN" ]; then
    printf '%s trigger=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TRIGGER" \
        > "${HOME}/.claude/.skill-compact-pending-${_SESSION_TOKEN}" 2>/dev/null || true
fi

# --- cozempic checkpoint + prune (optional; PATH discovery as before) ---
if ! command -v cozempic >/dev/null 2>&1; then
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
fi
if command -v cozempic >/dev/null 2>&1; then
    cozempic checkpoint 2>/dev/null
    cozempic treat current -rx standard --execute 2>/dev/null
fi

exit 0
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `/bin/bash -n hooks/pre-compact-hook.sh && /bin/bash tests/test-compact-recovery.sh < /dev/null`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/pre-compact-hook.sh tests/test-compact-recovery.sh
git commit -m "fix: pre-compact logs + arms recovery marker before cozempic dependency check

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Prompt-carrier hook + registration

**Files:**
- Create: `hooks/compact-recovery-prompt-hook.sh`
- Modify: `hooks/hooks.json` (UserPromptSubmit array — append one entry)
- Test: `tests/test-compact-recovery.sh` (append)

**Interfaces:**
- Consumes: the Task-2 marker; `render_compact_recovery` from Task 1.
- Produces: `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}` on stdout when recovery fires; NOTHING otherwise. Appends `event=post_compact_prompt` to `~/.claude/.compact-events.log`.

- [ ] **Step 1: Append failing tests**

Append before `print_summary`:

```bash
# --- prompt-carrier hook ---
PROMPT_HOOK="${PROJECT_ROOT}/hooks/compact-recovery-prompt-hook.sh"
_payload() { printf '{"transcript_path":"%s","prompt":"proceed"}' "$_fake_transcript"; }

# no marker -> silent
_clear_state
printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
assert_equals "" "$_out" "prompt-carrier silent with no marker"

# marker + state -> emits recovery JSON and consumes marker
_clear_state; _seed_full_state
printf '%s trigger=auto\n' "2026-07-15T00:00:00Z" > "$HOME/.claude/.skill-compact-pending-${TOKEN}"
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
assert_json_valid "$_out" "prompt-carrier emits valid JSON"
assert_contains "$_out" "Post-Compaction State Recovery" "prompt-carrier emits recovery block"
assert_contains "$_out" "fix auto-compact recovery" "prompt-carrier carries confirmed intent"
if [ -f "$HOME/.claude/.skill-compact-pending-${TOKEN}" ]; then
    fail_test "prompt-carrier consumes the marker"
else
    pass_test "prompt-carrier consumes the marker"
fi

# second run after consumption -> silent (no double injection)
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
assert_equals "" "$_out" "prompt-carrier silent after marker consumed"

# foreign-token marker -> untouched and silent
_clear_state
printf '%s' "$TOKEN" > "$HOME/.claude/.skill-session-token"
printf 'x trigger=auto\n' > "$HOME/.claude/.skill-compact-pending-session-OTHER"
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
assert_equals "" "$_out" "prompt-carrier ignores foreign-session marker"
assert_file_exists "$HOME/.claude/.skill-compact-pending-session-OTHER" "foreign marker left in place"
rm -f "$HOME/.claude/.skill-compact-pending-session-OTHER"

# stale marker (>24h) -> consumed silently
_clear_state; _seed_full_state
printf 'x trigger=auto\n' > "$HOME/.claude/.skill-compact-pending-${TOKEN}"
touch -t 202601010000 "$HOME/.claude/.skill-compact-pending-${TOKEN}"
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
assert_equals "" "$_out" "stale marker suppressed"
if [ -f "$HOME/.claude/.skill-compact-pending-${TOKEN}" ]; then
    fail_test "stale marker consumed"
else
    pass_test "stale marker consumed"
fi
```

If `test-helpers.sh` has no `pass_test`/`fail_test`, use its actual pass/fail primitives (check `assert_equals`'s internals) — the assertion INTENT above is normative, the helper name is not.

- [ ] **Step 2: Run to verify the new asserts fail**

Expected: hook file missing → all new asserts FAIL.

- [ ] **Step 3: Implement the hook**

Create `hooks/compact-recovery-prompt-hook.sh`:

```bash
#!/bin/bash
# compact-recovery-prompt-hook.sh — UserPromptSubmit prompt-carrier for
# post-compaction state recovery. Since Claude Code ~2.1.179, AUTO
# compaction no longer emits SessionStart(source=compact), so
# compact-recovery-hook.sh never fires for the unattended case (see
# openspec/changes/compact-recovery-prompt-carrier). PreCompact arms a
# per-token marker; this hook re-injects state on the NEXT prompt and
# consumes the marker. When SessionStart(compact) DOES fire (manual
# /compact), it consumes the marker first — no double injection.
#
# Fail-open: every failure exits 0 silently. Common path (no marker for
# any session) is ONE glob test — no stdin read, no jq fork.

trap 'exit 0' ERR

# Cheap common-path bailout.
compgen -G "${HOME}/.claude/.skill-compact-pending-*" >/dev/null 2>&1 || exit 0

# jq is required both to resolve the token and to emit JSON — bail BEFORE
# consuming the marker so recovery is not lost on a jq-less machine.
command -v jq >/dev/null 2>&1 || exit 0

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

INPUT=""
if [ ! -t 0 ]; then
    INPUT="$(cat 2>/dev/null)" || INPUT=""
fi
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)" || TRANSCRIPT_PATH=""

# Payload-first token resolution (issue #51); singleton fallback.
_SESSION_TOKEN=""
if [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_session_token_from_transcript >/dev/null 2>&1 && \
        _SESSION_TOKEN="$(resolve_session_token_from_transcript "${TRANSCRIPT_PATH}")"
fi
[ -z "$_SESSION_TOKEN" ] && [ -f "${HOME}/.claude/.skill-session-token" ] && \
    _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
[ -z "$_SESSION_TOKEN" ] && exit 0

MARKER="${HOME}/.claude/.skill-compact-pending-${_SESSION_TOKEN}"
[ -f "$MARKER" ] || exit 0    # another session's marker — not ours to consume

# Stale marker (>24h): a crashed session must not inject into a much later
# one that reuses the token. Consume silently. Numerics validated before
# arithmetic (Bash 3.2 quoted-operand gotcha).
_NOW="$(date +%s 2>/dev/null)" || _NOW=""
_MTIME="$(stat -f %m "$MARKER" 2>/dev/null || stat -c %Y "$MARKER" 2>/dev/null)" || _MTIME=""
if [[ "$_NOW" =~ ^[0-9]+$ ]] && [[ "$_MTIME" =~ ^[0-9]+$ ]]; then
    _AGE=$(( _NOW - _MTIME ))
    if [ "$_AGE" -gt 86400 ]; then
        rm -f "$MARKER" 2>/dev/null
        exit 0
    fi
fi

_TRIGGER="$(sed -n '1s/.*trigger=//p' "$MARKER" 2>/dev/null)" || _TRIGGER=""
rm -f "$MARKER" 2>/dev/null || true

BLOCK=""
if [ -f "${PLUGIN_ROOT}/hooks/lib/compact-recovery-render.sh" ]; then
    # shellcheck source=lib/compact-recovery-render.sh
    . "${PLUGIN_ROOT}/hooks/lib/compact-recovery-render.sh" 2>/dev/null || true
    command -v render_compact_recovery >/dev/null 2>&1 && \
        BLOCK="$(render_compact_recovery "$_SESSION_TOKEN" "$_TRIGGER" 2>/dev/null)" || BLOCK=""
fi
[ -z "$BLOCK" ] && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
    "$(printf '%s' "$BLOCK" | jq -Rs .)"

# Telemetry: same log the auto-compact drift was detected in.
printf '%s event=post_compact_prompt trigger=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_TRIGGER:-unknown}" \
    >> "${HOME}/.claude/.compact-events.log" 2>/dev/null || true
exit 0
```

- [ ] **Step 4: Register in hooks.json**

In `hooks/hooks.json`, append to the existing `UserPromptSubmit` array (targeted edit — after the `skill-activation-hook.sh` entry object):

```json
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/compact-recovery-prompt-hook.sh",
            "timeout": 5
          }
        ]
      }
```

- [ ] **Step 5: Run tests, syntax check, validate JSON, commit**

```bash
/bin/bash -n hooks/compact-recovery-prompt-hook.sh
jq empty hooks/hooks.json
/bin/bash tests/test-compact-recovery.sh < /dev/null
git add hooks/compact-recovery-prompt-hook.sh hooks/hooks.json tests/test-compact-recovery.sh
git commit -m "feat: UserPromptSubmit prompt-carrier restores post-compaction recovery for auto compaction

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: SessionStart hook uses the shared renderer and consumes the marker

**Files:**
- Modify: `hooks/compact-recovery-hook.sh:40-65` (replace team-checkpoint + composition sections)
- Test: `tests/test-compact-recovery.sh` (append)

**Interfaces:**
- Consumes: Task-1 renderer, Task-2 marker.
- Produces: plain-text recovery block on stdout (SessionStart hooks inject raw stdout — NOT JSON); marker consumed.

- [ ] **Step 1: Append failing tests**

Append before `print_summary`:

```bash
# --- SessionStart hook: renderer payload + marker consumption ---
SS_HOOK="${PROJECT_ROOT}/hooks/compact-recovery-hook.sh"
_clear_state; _seed_full_state
printf 'x trigger=manual\n' > "$HOME/.claude/.skill-compact-pending-${TOKEN}"
_out="$(printf '{"transcript_path":"%s","source":"compact"}' "$_fake_transcript" \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$SS_HOOK" 2>/dev/null)"
assert_contains "$_out" "Composition Recovery" "SessionStart emits composition section"
assert_contains "$_out" "fix auto-compact recovery" "SessionStart carries confirmed intent"
assert_contains "$_out" "compact-recovery-prompt-carrier" "SessionStart carries openspec changes"
if [ -f "$HOME/.claude/.skill-compact-pending-${TOKEN}" ]; then
    fail_test "SessionStart consumes the marker"
else
    pass_test "SessionStart consumes the marker"
fi

# e2e conformance: everything pre-compact checkpointed reappears (Scenario 1+2)
_clear_state; _seed_full_state
printf '{"session_id":"s1","transcript_path":"%s","trigger":"auto"}' "$_fake_transcript" \
    | PATH="/usr/bin:/bin" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PRE_HOOK" >/dev/null 2>&1
_out="$(_payload | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "$PROMPT_HOOK" 2>/dev/null)"
for _needle in "superpowers:writing-plans" "fix auto-compact recovery" "compact-recovery-prompt-carrier"; do
    assert_contains "$_out" "$_needle" "e2e survival: ${_needle}"
done
```

- [ ] **Step 2: Run to verify the intent/changes asserts fail**

Expected: marker-consumption + intent + openspec asserts FAIL (current hook renders neither and ignores markers); composition assert may already pass.

- [ ] **Step 3: Modify the hook**

In `hooks/compact-recovery-hook.sh`, replace lines 40–65 (the `--- Re-inject team checkpoint ---` and `--- Re-inject composition state ---` sections) with:

```bash
# --- Consume the pending marker (prompt-carrier coordination; see
# openspec/changes/compact-recovery-prompt-carrier) ---
_TRIGGER=""
if [ -n "$_SESSION_TOKEN" ]; then
    _MARKER="${HOME}/.claude/.skill-compact-pending-${_SESSION_TOKEN}"
    if [ -f "$_MARKER" ]; then
        _TRIGGER="$(sed -n '1s/.*trigger=//p' "$_MARKER" 2>/dev/null)" || _TRIGGER=""
        rm -f "$_MARKER" 2>/dev/null || true
    fi
fi

# --- Re-inject recovery state (shared renderer: team checkpoint,
# composition chain, confirmed intent, active OpenSpec changes) ---
if [ -f "${_PLUGIN_ROOT}/hooks/lib/compact-recovery-render.sh" ]; then
    # shellcheck source=lib/compact-recovery-render.sh
    . "${_PLUGIN_ROOT}/hooks/lib/compact-recovery-render.sh" 2>/dev/null || true
    command -v render_compact_recovery >/dev/null 2>&1 && \
        render_compact_recovery "$_SESSION_TOKEN" "$_TRIGGER" 2>/dev/null
fi
```

Keep everything else (payload read, depth-counter reset, post-compact logging) unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `/bin/bash -n hooks/compact-recovery-hook.sh && /bin/bash tests/test-compact-recovery.sh < /dev/null`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/compact-recovery-hook.sh tests/test-compact-recovery.sh
git commit -m "refactor: SessionStart compact recovery uses shared renderer, consumes prompt-carrier marker

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Full-suite verification + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]` section)

- [ ] **Step 1: Full suite under /bin/bash**

Run: `/bin/bash tests/run-tests.sh < /dev/null`
Expected: all files pass, including `test-compact-recovery.sh`; zero regressions.

- [ ] **Step 2: Live smoke of both prompt-hook paths**

```bash
# common path timing (no marker):
time (printf '{"prompt":"hi"}' | /bin/bash hooks/compact-recovery-prompt-hook.sh)
# expected: no output, real time ~0.01s
```

- [ ] **Step 3: CHANGELOG entry under [Unreleased] → Fixed/Added**

```markdown
- **compact-recovery prompt-carrier**: post-compaction state recovery works for AUTO compaction again (Claude Code ~2.1.179 stopped emitting `SessionStart(source=compact)`; recovery now rides a PreCompact marker consumed at the next prompt). Recovery payload now also carries the confirmed-intent marker and active OpenSpec changes. `pre-compact-hook.sh` logs and arms the marker before its optional cozempic dependency check.
```

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for compact-recovery prompt-carrier

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:** Scenario 1 (auto → next-prompt recovery + marker consumed) → Task 3 tests; Scenario 2 (manual consumes first, no double inject) → Task 4 test + Task 3 "silent after consumed"; Scenario 3 (intent + changes in payload) → Tasks 1/3/4 asserts; Scenario 4 (cozempic-less marker+log, jq-less/malformed fail-open) → Task 2 tests + Task 1 malformed test + Task 3 jq-guard-before-consume.
- **Placeholder scan:** clean — one deliberate adaptive note (helper primitive names in Task 3 Step 1) with normative intent stated.
- **Type consistency:** `render_compact_recovery <token> [trigger]` used identically in Tasks 1, 3, 4; marker path `.skill-compact-pending-<token>` and body `<ts> trigger=<t>` consistent across Tasks 2–4.

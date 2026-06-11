# Fix Token Singleton Race Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hook readers resolve the session token from their own stdin payload's `transcript_path` instead of the shared singleton, eliminating cross-session last-writer-wins races (issue #51).

**Architecture:** New `hooks/lib/session-token.sh` is the single source of the `session-<transcript-basename>` format; five hook readers convert to payload-first resolution with singleton fallback; the activation hook re-stamps the singleton for no-payload SKILL.md consumers.

**Tech Stack:** Bash 3.2 (`/bin/bash`), jq (optional at runtime — every path fails open), repo test harness (`tests/test-helpers.sh`).

**Spec:** `docs/plans/2026-06-11-fix-token-singleton-race-design.md` + `openspec/changes/fix-token-singleton-race/`

**Conventions that bite (from CLAUDE.md / memory):**
- Never `set -e` in routing hooks; `[[ =~ ]]` non-match exits 1.
- No quoted operands in `$(( ))` under bash 3.2; syntax-check every hook edit with `/bin/bash -n` AND exercise under `/bin/bash`.
- Minimize jq forks — batch extractions; `\x1f` is the field separator; arbitrary-content fields go LAST in the join.
- Run the suite foreground: `bash tests/run-tests.sh </dev/null` (session-start hook hangs if stdin is held open).
- `setup_test_env` exports `CLAUDE_PLUGIN_ROOT="${TEST_HOME}/.claude"` — hook invocations in tests must override with `CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}"`.

---

### Task 1: `hooks/lib/session-token.sh` + unit tests

**Files:**
- Create: `hooks/lib/session-token.sh`
- Create: `tests/test-session-token-race.sh` (sections U1–U4)
- Modify: `tests/run-tests.sh` (register the new test file the same way the other `test-session-token-*.sh` files are listed)

- [ ] **Step 1: Write the failing unit tests**

Create `tests/test-session-token-race.sh`:

```bash
#!/usr/bin/env bash
# test-session-token-race.sh — Regression: token resolution MUST be payload-first.
#
# Root cause (issue #51): ~/.claude/.skill-session-token is a shared singleton
# with last-writer-wins semantics. Concurrent sessions overwrite it; any hook
# that resolves "my token" by reading it back evaluates ANOTHER session's
# composition state. Observed live: the push gate denied a legitimate push
# because the singleton pointed at a different conversation's incomplete chain.
#
# Fix under test: hooks derive the token from their own stdin payload's
# transcript_path (hooks/lib/session-token.sh); the singleton is fallback only.
#
# Bash 3.2 compatible. Sources test-helpers.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LIB="${PROJECT_ROOT}/hooks/lib/session-token.sh"
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
ACTIVATION="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
COMPLETION="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-session-token-race.sh ==="

if ! command -v jq >/dev/null 2>&1; then
    _record_pass "jq unavailable — payload-first resolution is jq-gated; skipping"
    print_summary
    exit 0
fi

# ---------------------------------------------------------------------------
# U1–U4: lib unit checks
# ---------------------------------------------------------------------------
echo "--- U: session-token.sh unit checks ---"
setup_test_env
mkdir -p "${HOME}/.claude"
if [ -f "${LIB}" ]; then
    # shellcheck source=../hooks/lib/session-token.sh
    . "${LIB}"
    U1="$(session_token_from_transcript "/tmp/proj/conv-ALPHA.jsonl")"
    assert_equals "U1: session_token_from_transcript format" "session-conv-ALPHA" "${U1}"
    U2="$(session_token_from_transcript "")"
    assert_equals "U2: empty transcript -> empty token" "" "${U2}"
    printf '%s' "singleton-token" > "${HOME}/.claude/.skill-session-token"
    U3="$(resolve_session_token '{"transcript_path":"/tmp/proj/conv-ALPHA.jsonl"}')"
    assert_equals "U3: payload beats singleton" "session-conv-ALPHA" "${U3}"
    U4="$(resolve_session_token '{"session_id":"no-transcript-here"}')"
    assert_equals "U4: no transcript_path -> singleton fallback" "singleton-token" "${U4}"
else
    _record_fail "U1: hooks/lib/session-token.sh exists" "missing ${LIB}"
fi
teardown_test_env
```

(Keep the file ending with `print_summary` — later tasks append sections above it.)

- [ ] **Step 2: Run to verify it fails**

Run: `/bin/bash tests/test-session-token-race.sh </dev/null`
Expected: `FAIL: U1: hooks/lib/session-token.sh exists` (file missing).

- [ ] **Step 3: Write the lib**

Create `hooks/lib/session-token.sh`:

```bash
#!/bin/bash
# session-token.sh — shared session-token derivation/resolution.
#
# The token format `session-<transcript-basename>` is defined HERE and only
# here; the SessionStart writer and every hook reader source this file so the
# two can never drift.
#
# Payload-first contract (issue #51): ~/.claude/.skill-session-token is a
# shared singleton with last-writer-wins semantics across concurrent sessions.
# Hooks that receive a stdin payload MUST derive their token from their own
# payload's transcript_path and treat the singleton as fallback only.
#
# Bash 3.2 compatible. Fail-open: functions echo an empty string on failure.

# session_token_from_transcript <transcript_path>
# Echoes session-<basename .jsonl>; echoes nothing on empty/invalid input.
session_token_from_transcript() {
    local _tp="${1:-}" _conv=""
    [ -z "${_tp}" ] && return 0
    _conv="$(basename "${_tp}" .jsonl 2>/dev/null)" || _conv=""
    [ -z "${_conv}" ] && return 0
    printf 'session-%s' "${_conv}"
}

# resolve_session_token_from_transcript <transcript_path>
# For hooks that already extracted transcript_path (batched jq call).
# Payload-derived token when possible; singleton fallback; empty on total failure.
resolve_session_token_from_transcript() {
    local _token=""
    _token="$(session_token_from_transcript "${1:-}")"
    if [ -z "${_token}" ]; then
        _token="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)" || _token=""
    fi
    printf '%s' "${_token}"
}

# resolve_session_token <stdin-json>
# Extracts transcript_path itself (one jq fork). Prefer the
# *_from_transcript variant when the caller already has a jq call to batch into.
resolve_session_token() {
    local _json="${1:-}" _tp=""
    if [ -n "${_json}" ] && command -v jq >/dev/null 2>&1; then
        _tp="$(printf '%s' "${_json}" | jq -r '.transcript_path // empty' 2>/dev/null)" || _tp=""
    fi
    resolve_session_token_from_transcript "${_tp}"
}
```

- [ ] **Step 4: Verify pass, register in run-tests.sh**

Run: `/bin/bash -n hooks/lib/session-token.sh && /bin/bash tests/test-session-token-race.sh </dev/null`
Expected: U1–U4 PASS. Add the file to `tests/run-tests.sh` next to `test-session-token-resume.sh` (mirror the existing invocation style exactly).

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/session-token.sh tests/test-session-token-race.sh tests/run-tests.sh
git commit -m "feat: shared payload-first session-token lib (#51)"
```

---

### Task 2: Convert `openspec-guard.sh` (the false-deny site)

**Files:**
- Modify: `hooks/openspec-guard.sh:11-30`
- Test: `tests/test-session-token-race.sh` (sections G1–G3, appended before `print_summary`)

- [ ] **Step 1: Write the failing gate-race tests**

Append to `tests/test-session-token-race.sh` (before `print_summary`):

```bash
# ---------------------------------------------------------------------------
# G1–G3: openspec-guard keys to the payload token, not the singleton
# ---------------------------------------------------------------------------
echo "--- G: push gate vs foreign singleton ---"

# write_comp_state <token> <completed-json-array>
write_comp_state() {
    jq -n --argjson done "$2" '{
        chain: ["requesting-code-review","verification-before-completion"],
        completed: $done, current_index: 0
    }' > "${HOME}/.claude/.skill-composition-state-$1"
}

# run_guard_with <payload-json> — echoes guard stdout
run_guard_with() {
    printf '%s' "$1" | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null
}

PUSH_A='{"transcript_path":"/tmp/proj/conv-A.jsonl","tool_input":{"command":"git push origin main"}}'

# G1: A incomplete, singleton points at B (complete) -> must DENY from A state
setup_test_env
mkdir -p "${HOME}/.claude"
write_comp_state "session-conv-A" '[]'
write_comp_state "session-conv-B" '["requesting-code-review","verification-before-completion"]'
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
G1_OUT="$(run_guard_with "${PUSH_A}")"
assert_contains "G1: guard denies from OWN (payload) state despite foreign singleton" "${G1_OUT}" '"permissionDecision":"deny"'
teardown_test_env

# G2: A complete, singleton points at B (incomplete) -> must ALLOW (no deny)
setup_test_env
mkdir -p "${HOME}/.claude"
write_comp_state "session-conv-A" '["requesting-code-review","verification-before-completion"]'
write_comp_state "session-conv-B" '[]'
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
G2_OUT="$(run_guard_with "${PUSH_A}")"
if printf '%s' "${G2_OUT}" | grep -q '"permissionDecision":"deny"'; then
    _record_fail "G2: guard allows when OWN chain complete (foreign singleton incomplete)" "got deny: ${G2_OUT}"
else
    _record_pass "G2: guard allows when OWN chain complete (foreign singleton incomplete)"
fi
teardown_test_env

# G3: payload without transcript_path -> singleton fallback still gates
setup_test_env
mkdir -p "${HOME}/.claude"
write_comp_state "session-conv-B" '[]'
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
G3_OUT="$(run_guard_with '{"tool_input":{"command":"git push origin main"}}')"
assert_contains "G3: no transcript_path -> singleton fallback still denies" "${G3_OUT}" '"permissionDecision":"deny"'
teardown_test_env
```

(If `assert_contains` has a different arg order in `test-helpers.sh`, match the existing helper signature.)

- [ ] **Step 2: Run to verify G1 fails**

Run: `/bin/bash tests/test-session-token-race.sh </dev/null`
Expected: G1 FAIL (guard reads singleton → B's complete chain → no deny). G2/G3 may pass incidentally; G1 is the red bit.

- [ ] **Step 3: Convert the guard**

In `hooks/openspec-guard.sh`, replace the extraction block (lines 11–18) with:

```bash
# Extract transcript_path + command in ONE jq fork (\x1f-joined; transcript
# first — a path cannot contain \x1f, the command may contain anything).
_COMMAND=""
_TRANSCRIPT=""
if command -v jq >/dev/null 2>&1; then
    _FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[.transcript_path // "", .tool_input.command // ""] | join("\u001f")' 2>/dev/null)" || _FIELDS=""
    _TRANSCRIPT="${_FIELDS%%$'\x1f'*}"
    _COMMAND="${_FIELDS#*$'\x1f'}"
else
    # Fallback: grep for command field (may miss commands with embedded quotes)
    _COMMAND="$(printf '%s' "${_INPUT}" | grep -o '"command" *: *"[^"]*"' | head -1 | sed 's/"command" *: *"//;s/"$//')" || true
fi
```

And replace the singleton read (lines 26–30) with:

```bash
# Resolve session token payload-first (issue #51): the singleton is shared
# across concurrent sessions (last-writer-wins) and may name ANOTHER session.
_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
if [ -f "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh"
    _SESSION_TOKEN="$(resolve_session_token_from_transcript "${_TRANSCRIPT}")"
else
    [ -f "${HOME}/.claude/.skill-session-token" ] && \
        _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
[ -z "${_SESSION_TOKEN}" ] && exit 0
```

The later `_PLUGIN_ROOT` definition (~line 102) becomes redundant — delete the duplicate assignment there and let the consol-marker sourcing reuse this one.

- [ ] **Step 4: Verify pass**

Run: `/bin/bash -n hooks/openspec-guard.sh && /bin/bash tests/test-session-token-race.sh </dev/null`
Expected: U1–U4, G1–G3 all PASS.
Also run the existing guard regression: `/bin/bash tests/test-openspec-state.sh </dev/null` — must stay green.

- [ ] **Step 5: Commit**

```bash
git add hooks/openspec-guard.sh tests/test-session-token-race.sh
git commit -m "fix: openspec-guard resolves token payload-first (#51)"
```

---

### Task 3: Convert `skill-activation-hook.sh` (+ singleton re-stamp)

**Files:**
- Modify: `hooks/skill-activation-hook.sh:23-27`
- Test: `tests/test-session-token-race.sh` (sections A1–A2)

- [ ] **Step 1: Write the failing tests**

Append before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# A1–A2: activation hook keys state to payload token and re-stamps singleton
# ---------------------------------------------------------------------------
echo "--- A: activation hook payload keying + re-stamp ---"
setup_test_env
mkdir -p "${HOME}/.claude"
# Registry must exist for routing; copy the repo fallback registry like
# existing routing tests do.
cp "${PROJECT_ROOT}/config/fallback-registry.json" "${HOME}/.claude/.skill-registry-cache.json"
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
printf '%s' '{"transcript_path":"/tmp/proj/conv-A.jsonl","prompt":"let'"'"'s brainstorm a new feature design"}' | \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" SKILL_PROJECT_ROOT="${TEST_TMPDIR}" /bin/bash "${ACTIVATION}" >/dev/null 2>&1 || true
A1_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
assert_equals "A1: singleton re-stamped to payload-derived token" "session-conv-A" "${A1_TOKEN}"
if [ -f "${HOME}/.claude/.skill-prompt-count-session-conv-A" ]; then
    _record_pass "A2: per-prompt state keyed to payload token, not foreign singleton"
else
    _record_fail "A2: per-prompt state keyed to payload token, not foreign singleton" \
        "$(ls "${HOME}/.claude" 2>/dev/null | tr '\n' ' ')"
fi
teardown_test_env
```

(A2's observable: the activation hook bumps `.skill-prompt-count-<token>` on every routed prompt. If inspection during implementation shows a different cheapest observable — e.g. composition-state writes need a chain-trigger prompt — assert on the prompt-counter file as written here; it is unconditional.)

- [ ] **Step 2: Run to verify RED** — A1 and A2 FAIL (hook reads singleton, never re-stamps).

- [ ] **Step 3: Convert the hook**

Replace lines 23–27 of `hooks/skill-activation-hook.sh`:

```bash
# Capture stdin once; extract transcript_path + prompt in the SAME single jq
# fork the prompt already cost (\x1f-joined, transcript first — the prompt may
# contain anything, a path cannot contain \x1f).
_HOOK_INPUT="$(cat 2>/dev/null)" || _HOOK_INPUT=""
_FIELDS="$(printf '%s' "${_HOOK_INPUT}" | jq -r '[.transcript_path // "", .prompt // ""] | join("\u001f")' 2>/dev/null)" || _FIELDS=""
_TRANSCRIPT="${_FIELDS%%$'\x1f'*}"
PROMPT="${_FIELDS#*$'\x1f'}"

# Resolve session token payload-first (issue #51): the singleton races across
# concurrent sessions; our own payload names our conversation.
_SESSION_TOKEN=""
if [[ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]]; then
  # shellcheck source=lib/session-token.sh
  . "${PLUGIN_ROOT}/hooks/lib/session-token.sh"
  _SESSION_TOKEN="$(resolve_session_token_from_transcript "${_TRANSCRIPT}")"
else
  [[ -f "${HOME}/.claude/.skill-session-token" ]] && _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi

# Re-stamp the singleton with OUR resolved token so no-payload SKILL.md
# consumers later in this turn read this conversation's token (narrows the
# residual no-payload race to one prompt-width; see issue #51).
if [[ -n "${_SESSION_TOKEN}" && -n "${_TRANSCRIPT}" ]]; then
  printf '%s' "${_SESSION_TOKEN}" > "${HOME}/.claude/.skill-session-token" 2>/dev/null || true
fi
```

Note the edge-case guard: only re-stamp when the token came from the payload (`_TRANSCRIPT` non-empty) — re-stamping a singleton-fallback token is a no-op churn.

- [ ] **Step 4: Verify GREEN + routing regression**

Run: `/bin/bash -n hooks/skill-activation-hook.sh && /bin/bash tests/test-session-token-race.sh </dev/null && bash tests/test-routing.sh </dev/null`
Expected: all PASS, routing suite unchanged.

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-activation-hook.sh tests/test-session-token-race.sh
git commit -m "fix: activation hook payload-first token + singleton re-stamp (#51)"
```

---

### Task 4: Convert `skill-completion-hook.sh`

**Files:**
- Modify: `hooks/skill-completion-hook.sh:21-36`
- Test: `tests/test-session-token-race.sh` (section C1)

- [ ] **Step 1: Write the failing test**

Append before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# C1: completion hook advances OWN state despite foreign singleton
# ---------------------------------------------------------------------------
echo "--- C: completion hook payload keying ---"
setup_test_env
mkdir -p "${HOME}/.claude"
write_comp_state "session-conv-A" '[]'
write_comp_state "session-conv-B" '[]'
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
printf '%s' '{"transcript_path":"/tmp/proj/conv-A.jsonl","tool_input":{"skill":"superpowers:requesting-code-review"},"tool_response":{"content":"ok"}}' | \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${COMPLETION}" >/dev/null 2>&1 || true
C1_A="$(jq -r '.completed | index("requesting-code-review") != null' "${HOME}/.claude/.skill-composition-state-session-conv-A" 2>/dev/null)"
C1_B="$(jq -r '.completed | index("requesting-code-review") != null' "${HOME}/.claude/.skill-composition-state-session-conv-B" 2>/dev/null)"
assert_equals "C1: own (payload) state advanced" "true" "${C1_A}"
assert_equals "C1: foreign (singleton) state untouched" "false" "${C1_B}"
teardown_test_env
```

- [ ] **Step 2: Run to verify RED** — "own state advanced" FAILS (hook used singleton → advanced B).

- [ ] **Step 3: Convert the hook**

In `hooks/skill-completion-hook.sh`, replace lines 21–36 (singleton read + two separate jq extractions) with:

```bash
# Resolve token payload-first (issue #51); batch transcript + is_error + skill
# name into ONE jq fork (was two) — \x1f-joined, controlled fields only.
_FIELDS="$(printf '%s' "${_INPUT}" | jq -r '[.transcript_path // "", (.tool_response.is_error // false | tostring), (.tool_input.name // .tool_input.skill // "")] | join("\u001f")' 2>/dev/null)" || _FIELDS=""
_TRANSCRIPT="${_FIELDS%%$'\x1f'*}"
_REST="${_FIELDS#*$'\x1f'}"
_IS_ERROR="${_REST%%$'\x1f'*}"
_RAW="${_REST#*$'\x1f'}"

_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
if [ -f "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh"
    _SESSION_TOKEN="$(resolve_session_token_from_transcript "${_TRANSCRIPT}")"
else
    [ -f "${HOME}/.claude/.skill-session-token" ] && \
        _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
[ -z "${_SESSION_TOKEN}" ] && exit 0

_STATE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
[ -f "${_STATE}" ] || exit 0
jq empty "${_STATE}" >/dev/null 2>&1 || exit 0

[ "${_IS_ERROR}" = "true" ] && exit 0
[ -z "${_RAW}" ] && exit 0
```

(The `_BARE="${_RAW##*:}"` line and everything after stays as-is.)

- [ ] **Step 4: Verify GREEN**

Run: `/bin/bash -n hooks/skill-completion-hook.sh && /bin/bash tests/test-session-token-race.sh </dev/null`
Expected: all sections PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/skill-completion-hook.sh tests/test-session-token-race.sh
git commit -m "fix: completion hook payload-first token, batched jq (#51)"
```

---

### Task 5: Convert `consolidation-stop.sh` + `compact-recovery-hook.sh`

**Files:**
- Modify: `hooks/consolidation-stop.sh:7-9`
- Modify: `hooks/compact-recovery-hook.sh:15-20,49-51`
- Test: `tests/test-session-token-race.sh` (section S1)

- [ ] **Step 1: Write the failing test**

Append before `print_summary`:

```bash
# ---------------------------------------------------------------------------
# S1: compact-recovery resets the counter for the PAYLOAD token
# ---------------------------------------------------------------------------
echo "--- S: compact-recovery payload keying ---"
setup_test_env
mkdir -p "${HOME}/.claude"
printf '%s' "session-conv-B" > "${HOME}/.claude/.skill-session-token"
printf '%s' '{"transcript_path":"/tmp/proj/conv-A.jsonl"}' | \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${PROJECT_ROOT}/hooks/compact-recovery-hook.sh" >/dev/null 2>&1 || true
if [ -f "${HOME}/.claude/.skill-prompt-count-session-conv-A" ]; then
    _record_pass "S1: compact-recovery keyed to payload token"
else
    _record_fail "S1: compact-recovery keyed to payload token" \
        "$(ls "${HOME}/.claude" 2>/dev/null | tr '\n' ' ')"
fi
teardown_test_env
```

(consolidation-stop's token use is only observable via openspec-state writes that need fixture scaffolding; its conversion is identical in shape to the guard's and is covered by the lib unit tests + review. S1 covers the stdin-read-reordering risk, which is the riskier edit.)

- [ ] **Step 2: Run to verify RED** — S1 FAILS (counter written for session-conv-B).

- [ ] **Step 3: Convert both hooks**

`hooks/compact-recovery-hook.sh` — move the stdin read to the TOP (it currently reads the singleton at line 17 but only drains stdin at line 50). Replace lines 15–20 with:

```bash
# Read the payload FIRST (issue #51): token resolution must be payload-first,
# and stdin must be drained before any early use of the singleton.
INPUT=""
if [ ! -t 0 ]; then
    INPUT="$(cat 2>/dev/null)" || INPUT=""
fi
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)" || TRANSCRIPT_PATH=""

_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
if [ -f "${_PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT}/hooks/lib/session-token.sh"
    _SESSION_TOKEN="$(resolve_session_token_from_transcript "${TRANSCRIPT_PATH}")"
else
    [ -f "${HOME}/.claude/.skill-session-token" ] && _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
if [ -n "$_SESSION_TOKEN" ]; then
    printf '0' > "${HOME}/.claude/.skill-prompt-count-${_SESSION_TOKEN}" 2>/dev/null || true
fi
```

Then delete the now-duplicate `INPUT="$(cat)"` and `TRANSCRIPT_PATH=` lines in the logging section at the bottom (lines 49–51) — the variables are already populated.

`hooks/consolidation-stop.sh` — replace lines 7–9 with:

```bash
# Resolve session token payload-first (issue #51); Stop hooks receive a JSON
# payload with transcript_path on stdin.
_INPUT=""
if [ ! -t 0 ]; then
    _INPUT="$(cat 2>/dev/null)" || _INPUT=""
fi
_PLUGIN_ROOT_TOK="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
_SESSION_TOKEN=""
if [ -f "${_PLUGIN_ROOT_TOK}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${_PLUGIN_ROOT_TOK}/hooks/lib/session-token.sh"
    _SESSION_TOKEN="$(resolve_session_token "${_INPUT}")"
else
    [ -f "${HOME}/.claude/.skill-session-token" ] && _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi
[ -z "${_SESSION_TOKEN}" ] && exit 0
```

(Behavioral parity: the original exited 0 when the singleton was missing; exit 0 on empty token preserves that.)

- [ ] **Step 4: Verify GREEN**

Run: `/bin/bash -n hooks/compact-recovery-hook.sh && /bin/bash -n hooks/consolidation-stop.sh && /bin/bash tests/test-session-token-race.sh </dev/null`
Expected: all PASS. Also `echo '{}' | /bin/bash hooks/consolidation-stop.sh` exits 0 quickly (no hang, fail-open).

- [ ] **Step 5: Commit**

```bash
git add hooks/consolidation-stop.sh hooks/compact-recovery-hook.sh tests/test-session-token-race.sh
git commit -m "fix: stop/compact hooks payload-first token (#51)"
```

---

### Task 6: `session-start-hook.sh` sources the lib (format single-sourcing)

**Files:**
- Modify: `hooks/session-start-hook.sh:70-78`

- [ ] **Step 1: Re-run the existing resume regression as the safety net**

Run: `/bin/bash tests/test-session-token-resume.sh </dev/null` — green baseline (R1–R3).

- [ ] **Step 2: Replace the inline derivation**

Replace lines 70–78 (`_CONV_ID` block through the `session_id` elif) of `hooks/session-start-hook.sh` with:

```bash
# Conversation-stable id: token format is single-sourced in lib/session-token.sh
# so the writer and the payload-first readers (issue #51) can never drift.
_SESSION_TOKEN=""
if [ -n "${_HOOK_TRANSCRIPT}" ] && [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh"
    _SESSION_TOKEN="$(session_token_from_transcript "${_HOOK_TRANSCRIPT}")"
fi
if [ -z "${_SESSION_TOKEN}" ] && [ -n "${_HOOK_SESSION_ID}" ]; then
    _SESSION_TOKEN="session-${_HOOK_SESSION_ID}"
fi
if [ -z "${_SESSION_TOKEN}" ]; then
```

…and keep the existing reuse-window/random block as the body of that final `if` (it currently lives in the `else` arm — reindent only, no logic change). The `printf … > .skill-session-token` write at line 109 stays.

- [ ] **Step 3: Verify**

Run: `/bin/bash -n hooks/session-start-hook.sh && /bin/bash tests/test-session-token-resume.sh </dev/null && /bin/bash tests/test-session-token.sh </dev/null && /bin/bash tests/test-session-token-reuse.sh </dev/null`
Expected: all green — derivation behavior identical.

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "refactor: session-start sources shared token lib (#51)"
```

---

### Task 7: CHANGELOG + full suite + tasks.md checkboxes

**Files:**
- Modify: `CHANGELOG.md` (under `## [Unreleased]` `### Fixed`)
- Modify: `openspec/changes/fix-token-singleton-race/tasks.md` (tick completed boxes)

- [ ] **Step 1: CHANGELOG entry**

Append under `## [Unreleased]` → `### Fixed` (create the subsection if absent, preserving existing entries):

```markdown
- Session-token resolution is now payload-first: hooks derive the token from
  their own stdin `transcript_path` instead of the shared
  `~/.claude/.skill-session-token` singleton, eliminating cross-session
  last-writer-wins races that false-blocked the push gate (issue #51). The
  singleton remains as fallback and is re-stamped per prompt for no-payload
  SKILL.md consumers. New shared lib `hooks/lib/session-token.sh`; regression
  `tests/test-session-token-race.sh`.
```

- [ ] **Step 2: Full suite, foreground**

Run: `bash tests/run-tests.sh </dev/null`
Expected: all suites pass, including the new file.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md openspec/changes/fix-token-singleton-race/tasks.md
git commit -m "docs: changelog + task checkboxes for token race fix (#51)"
```

---

### Post-implementation (composition chain, not plan tasks)

REVIEW → requesting-code-review (artifact + contract only; hooks touched ⇒ security + adversarial perspectives) → fix findings → verification-before-completion → openspec-ship (sync path — change folder exists upfront) → finishing-a-development-branch (PR referencing #51).

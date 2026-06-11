# Design: Fix Token Singleton Race (issue #51)

**Date:** 2026-06-11
**Issue:** https://github.com/damianpapadopoulos/auto-claude-skills/issues/51
**Capability:** skill-routing
**OpenSpec change:** `openspec/changes/fix-token-singleton-race/`

## Problem

`~/.claude/.skill-session-token` is a shared singleton with last-writer-wins
semantics. Every hook reader (`openspec-guard.sh`, `skill-activation-hook.sh`,
`skill-completion-hook.sh`, `consolidation-stop.sh`, `compact-recovery-hook.sh`)
resolves "my session's token" by reading this file back. With ≥2 concurrent
sessions in the same `$HOME`, whichever session's SessionStart fired last owns
the pointer, so a hook in session A evaluates session B's composition state.
Observed failure: the push gate denied a legitimate push because the singleton
pointed at another session's (incomplete) chain. PR #43 (reuse window) and
PR #47 (transcript_path keying) fixed *derivation instability*; neither
addresses *pointer contention* — the token each hook derives is fine, the
read-back is what races.

## Key insight

The token is **directly derivable** from each hook's own stdin payload: every
Claude Code hook event delivers `transcript_path`, and the token format is
`session-$(basename <transcript_path> .jsonl)` (established by PR #47 in
`session-start-hook.sh`). Readers never needed the pointer file — they can
compute the same value from their own payload, race-free. This dominates the
per-transcript-pointer-file alternative (`.skill-session-token-<hash>`), which
would add a file-indirection layer to arrive at a value already in hand.

## Design

### New: `hooks/lib/session-token.sh`

Two functions, Bash 3.2, fail-open:

- `session_token_from_transcript <transcript_path>` — echoes
  `session-<basename .jsonl>`; echoes nothing on empty input. Single source of
  truth for the token format, shared by writer and readers so they can never
  drift.
- `resolve_session_token <stdin-json>` — extracts `transcript_path` via jq
  (when available), maps through `session_token_from_transcript`; on any
  failure (empty payload, no jq, missing field) falls back to reading the
  singleton; echoes empty string if both fail. Callers already treat an empty
  token as "exit 0 / skip" — unchanged.

### Converted readers (payload-first, singleton fallback)

| Hook | Change |
|------|--------|
| `openspec-guard.sh` | Batch `transcript_path` into the existing jq command extraction (`[.transcript_path // "", .tool_input.command // ""] | join("")`, transcript first — it cannot contain `\x1f`); resolve payload-first. No-jq grep fallback keeps working for the command; token then falls back to the singleton as today. |
| `skill-activation-hook.sh` | Capture stdin once; ONE jq emits `[.transcript_path // "", .prompt // ""] | join("")`; split with `${VAR%%$'\x1f'*}` / `${VAR#*$'\x1f'}` (transcript first because the prompt may contain anything). Resolve payload-first. After resolution, **re-stamp the singleton** with the resolved token (see below). Net jq forks: unchanged (the prompt extraction fork is reused). |
| `skill-completion-hook.sh` | Batch `transcript_path` into the existing extraction jq calls (merge `is_error` + skill-name + transcript into one `join("")` call — net fork count goes DOWN by one); resolve payload-first. |
| `consolidation-stop.sh` | Stop hooks receive a payload too; read stdin (new), resolve payload-first, fall back to singleton. |
| `compact-recovery-hook.sh` | Move the `INPUT="$(cat)"` read (currently line 50, *after* the singleton read at 17) to the top; resolve payload-first using the `transcript_path` extraction that already exists at line 51. |

### Writer (`session-start-hook.sh`)

Sources the lib and uses `session_token_from_transcript` for the primary path
(replacing the inline basename logic), keeping `session_id` / reuse-window /
random fallbacks unchanged. Continues to stamp the singleton — it remains the
only resolution source for no-payload consumers.

### Singleton retention + re-stamp

The singleton stays for consumers with no stdin payload: the four SKILL.md
flows that run `cat ~/.claude/.skill-session-token` from the conversation
(`openspec-ship`, `product-discovery`, `implementation-drift-check`,
`runtime-validation`). To keep it as fresh as possible for them, the
activation hook re-stamps it with the payload-resolved token on every routed
prompt. This narrows the SKILL.md race window from "since the last SessionStart
anywhere" to "since this conversation's current prompt" — not eliminated
(documented residual risk), but the gate-correctness bug (hook readers) is
fully fixed because hooks no longer consult the singleton when a payload is
present.

### Failure modes

- Payload lacks `transcript_path` → singleton fallback (today's behavior).
- jq missing → singleton fallback; guard's no-jq grep path unchanged.
- Both unavailable → empty token → every caller already exits/skips (fail-open).
- Derivation mismatch (SessionStart wrote a `session_id`/random token because
  *its* payload lacked transcript_path, but in-turn payloads carry it): hook
  reads a payload-derived token with no state → gates no-op. Fail-open and
  correct-leaning (no false denies); accepted, documented. Resolution must NOT
  prefer "whichever token has state" — that reintroduces the race. The
  narrower fail-closed variant raised in adversarial review ("no state under
  derived token + singleton differs → use singleton state") is rejected for
  the same reason: it re-gates ad-hoc pushes against foreign sessions'
  chains — the original #51 false-deny. The asymmetry it defends against
  (PreToolUse has transcript_path while the state-writing hooks don't) has
  not been observed; when the writers have it, state and guard converge.

## Capabilities Affected

- `skill-routing` — session token resolution contract (ADDED requirement:
  Payload-First Session Token Resolution). No routing/scoring changes.

## Out-of-Scope

- Eliminating the residual no-payload SKILL.md race (narrowed by re-stamp;
  revival trigger: a SKILL.md helper writes state to a wrong token in the wild).
- Changing the token format or state-file naming.
- Counter files (`.skill-prompt-count-*`, zero-match) — already token-scoped;
  they inherit the fix via the resolved token.
- `hooks/lib/openspec-state.sh` API.

## Acceptance Scenarios

1. GIVEN composition state for token A (review NOT completed) where A derives
   from transcript A, AND the singleton contains token B (other session wrote
   last), WHEN `openspec-guard.sh` receives a `git push` PreToolUse payload
   with transcript_path A, THEN it DENIES based on A's state — the race no
   longer masks the gate.
2. GIVEN A's chain fully completed and B's chain incomplete, singleton = B,
   WHEN the guard runs with payload transcript A, THEN the push is ALLOWED
   (proves the guard did not read B's state through the singleton).
3. GIVEN a payload without `transcript_path`, WHEN any converted hook runs,
   THEN it resolves via the singleton exactly as before (back-compat).
4. GIVEN jq is unavailable, WHEN converted hooks run, THEN they fail open
   (exit 0, no crash, singleton fallback where greppable).
5. GIVEN the singleton contains token B, WHEN `skill-activation-hook.sh`
   processes a prompt whose payload carries transcript A, THEN composition
   state reads/writes are keyed to token A AND the singleton is re-stamped
   to token A afterward.
6. GIVEN the singleton contains token B, WHEN `skill-completion-hook.sh`
   receives a successful chain-member Skill PostToolUse payload with
   transcript A, THEN `.completed` advances in A's state file, not B's.

## Testing

New `tests/test-session-token-race.sh` (sources `test-helpers.sh`, jq-gated
skip like `test-session-token-resume.sh`) covering scenarios 1–6 plus lib unit
checks (`session_token_from_transcript` format, `resolve_session_token`
precedence). Every edited hook: `/bin/bash -n` + exercised under `/bin/bash`
3.2 (quoted-arithmetic / ERE gotchas). Full suite via
`bash tests/run-tests.sh </dev/null`.

## Divergences (auto-generated at ship time)

**Acceptance Scenarios:**
- [x] 1. Foreign-singleton + own incomplete chain → guard DENIES from own state — implemented as designed (G1)
- [x] 2. Own chain complete + foreign incomplete singleton → push ALLOWED — implemented as designed (G2)
- [x] 3. Payload without transcript_path → singleton fallback — implemented as designed (G3, U4)
- [x] 4. jq unavailable → fail-open — implemented as designed (jq-gated skip + grep fallback preserved; not separately fixtured, consistent with repo convention)
- [x] 5. Activation hook keys state to payload token + re-stamps singleton — implemented with hardening: re-stamp is tmp+mv atomic (review finding), guarded to payload-derived tokens only (A1, A2)
- [x] 6. Completion hook advances own conversation's .completed — implemented as designed (C1 dual assertion)

**Scope changes:**
- Added: `basename --` option-terminator guard in the lib (U5) and ST1 consolidation-stop regression pin — review-driven, within capability scope
- Removed: none
- Modified: none

**Design decision changes:**
- Adversarial review proposed a fail-closed singleton fallback for the
  derived-token-without-state case; rejected (re-introduces the #51 false-deny
  on ad-hoc pushes) — rationale recorded in Decisions & Trade-offs of the
  archived change design.md.

## Why

`~/.claude/.skill-session-token` is a shared singleton with last-writer-wins
semantics. With concurrent Claude sessions in one `$HOME`, hook readers that
resolve "my token" by reading the singleton back get whichever session wrote
last, then evaluate that session's composition state. Observed live (issue
#51): the openspec-guard push gate falsely denied a legitimate push because
the singleton pointed at another session's incomplete chain. PR #43 and PR #47
fixed token *derivation* instability; this is *pointer contention*, which they
cannot address.

## What Changes

- New `hooks/lib/session-token.sh`: `session_token_from_transcript` (single
  source of truth for the `session-<transcript-basename>` format) and
  `resolve_session_token <stdin-json>` (payload-first, singleton fallback,
  fail-open).
- Five hook readers (`openspec-guard.sh`, `skill-activation-hook.sh`,
  `skill-completion-hook.sh`, `consolidation-stop.sh`,
  `compact-recovery-hook.sh`) resolve the token from their own stdin payload's
  `transcript_path` instead of reading the singleton; singleton remains the
  fallback when the payload lacks the field or jq is missing.
- `session-start-hook.sh` sources the lib for the token format; fallback
  derivation (session_id / reuse-window / random) and singleton write
  unchanged.
- `skill-activation-hook.sh` re-stamps the singleton with the resolved token
  per routed prompt, narrowing (not eliminating) the residual race for
  no-payload SKILL.md consumers.
- New regression test `tests/test-session-token-race.sh` interleaving two
  simulated sessions.

## Capabilities

### Modified Capabilities

- `skill-routing`: session token resolution becomes payload-first (ADDED
  requirement; no existing requirement text changes).

## Impact

- Affected code: `hooks/lib/session-token.sh` (new), 6 hooks, 1 new test file.
- No changes to token format, state-file naming, routing/scoring, or the
  `openspec-state.sh` helper API.
- Residual (documented, out of scope): no-payload SKILL.md helpers still read
  the singleton; window narrowed to one prompt-width by the re-stamp.

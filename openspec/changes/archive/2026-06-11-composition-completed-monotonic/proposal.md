## Why

During the 2026-06-11 PR #49 merge session, the composition state's `.completed` array regressed 5→3→2 across consecutive prompts. The UserPromptSubmit walker's state write rebuilt `.completed` purely from `max(_current_idx-1, _last_skill_chain_idx)`, ignoring the on-disk array that the PostToolUse completion hook advances when chain Skills actually return. A prompt that re-anchored EARLIER in the chain ("merge PR49" matched the requesting-code-review trigger `(^|[^a-z])pr($|[^a-z])` after verification had already run) truncated recorded progress and re-armed the `openspec-guard.sh` push gate against already-reviewed work. The prior fix (ce88014) floored against non-chain last-invoked skills but not against a backward-moving anchor.

## What Changes

The walker's state write now unions its computed chain-prefix with the existing on-disk `.completed` whenever the chain is unchanged — projected through the chain for order and dedup. `.completed` becomes monotonic within the same chain; resets happen only on chain switch, pure-cancel prompts, or session-token rotation. Fail-open: missing/malformed prior state or jq failure degrades to the prefix-only write. `current_index` intentionally remains the prompt's anchor index (display-only; the push gate keys off `.completed`).

## Capabilities

### Modified Capabilities
- `skill-routing`: composition-state `.completed` gains a monotonicity contract (new ADDED requirement; existing floor behavior unchanged).

## Impact

- `hooks/skill-activation-hook.sh` — one additional jq call at the state-write site, only when a prior state file exists.
- `tests/test-routing.sh` — 2 fixtures: same-chain backward re-anchor must not truncate (red-green verified, with a writer-ran canary); chain switch must still reset (no cross-chain leak).
- `CLAUDE.md` — composition-state gotcha bullet documents the monotonic contract.
- `hooks/openspec-guard.sh` untouched; `hooks/skill-completion-hook.sh` untouched (its idempotent merge now composes losslessly with the walker).

## Why

Text reaches the `UserPromptSubmit` hook without having been typed by the user: a message from another agent session, a subagent's final report handed back to the session that dispatched it, and a background-task notification followed by `<system-reminder>` blocks. The activation hook routed all of it as if it were a prompt.

Measured over 745 distinct non-human inputs from five weeks of real transcripts: 111 received a routing block and 109 of those a `MUST INVOKE` line — a hand-back that says "the test fails" was told to start `systematic-debugging`. Two blind labellers then classified the 109 mandated inputs: 107 are reports, hand-backs or notices, 2 are work orders the mandated skill did not fit, and none is a work order it did fit (the 65 that had been excerpted were re-read in full).

A second, unrelated defect was found on the way: the frontmatter parser treated a hyphenated key such as `allowed-tools:` as a continuation of the list key above it, so that key's items were appended to the previous key. It reproduces on real third-party skills.

## What Changes

- **Non-human input gets no routing DISPLAY.** The activation hook recognises the three shapes above and skips its final print for them. Scoring, the composition-chain walk and every state write run exactly as before.
- **It is display-only on purpose.** The first implementation exited before routing, which also skipped the composition-state write. The push gate runs its chain checks only when that file exists, so a push after a peer's work order went from DENY to allow. That was caught in review before publication; the regression now asserts the gate's decision, not the state file.
- **Fail-open classification.** If either jq definition (the shared notification classifier or this hook's own) fails to compile, the hook retries without it and routes the prompt rather than dropping it.
- **Frontmatter:** a hyphenated key is a key boundary. Its own value is not ingested; it no longer leaks into the key above. Control characters in emitted values are replaced by spaces.
- **Descriptions:** three one-line descriptions of superpowers skills, and one eval rubric, are aligned with what those skills do in 6.4.2.

A third change was built, measured and **removed** before this proposal: hiding the routing block on a plain question. Its measured effect was too small for its heuristics (2 of 83 held-out wrong mandates), and it is not part of this change.

## Capabilities

### Modified Capabilities

- `skill-routing`: non-human input is routed for state and not displayed; frontmatter discovery treats a hyphenated key as a boundary.

## Impact

- `hooks/skill-activation-hook.sh` — the classifier, its retries, and the suppression of two prints. Nothing in scoring, selection or the chain walk changes.
- `hooks/session-start-hook.sh` — the frontmatter key pattern.
- `config/default-triggers.json`, `config/fallback-registry.json`, `README.md` — description text only.
- `tests/test-activation-nonhuman-skip.sh`, `tests/test-push-gate-display-suppression.sh`, `tests/test-frontmatter-hyphen-keys.sh`, `tests/test-superpowers-description-drift.sh` — new. `tests/test-injection-budget.sh` — ratchet lowered by the 63 bytes saved.
- The shared classifier `hooks/lib/task-notification.sh` is unchanged, so `egress-consent-turn-hook.sh` still treats these inputs as the user and still withdraws approvals over them.

**Known residual, recorded rather than fixed:** a session fed only by peer messages still has a chain armed and never sees the routing block; it first hears of the chain at a gate deny, which names the invocation it wants. Whether automated text should arm a chain at all is a separate question and is not decided here.

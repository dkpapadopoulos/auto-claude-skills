## Why

A `.claude/knowledge/` fact could be committed, pass `scripts/knowledge-validate.sh`, and never be injected into a single session. The knowledge lane had three components and only two agreed on the index format:

- producer `scripts/knowledge-rebuild-index.sh` emits `- [Title](file.md) — desc`
- consumer `hooks/session-start-hook.sh` injects ONLY index lines matching `^- \[`
- validator `scripts/knowledge-validate.sh` checked `grep -qF "(slug.md)"` — anywhere in the file, any format

So a hand-edited or model-edited entry the injector drops — bold-wrapped `- **[Title](file.md)**`, an indented sub-bullet, a numbered item — passed validation while reaching no session. Silent in both directions, and worse than a private-memory bug: `.claude/knowledge/` is the committed *team* surface, so the repo believed a fact was published to teammates' agents while it was invisible to all of them. No test pinned the injector's predicate.

Found by porting an external project's failure shape (claude-mem #3379: an observer prompt taught `keyword: description` while the injection SQL exact-matched bare keywords, so tagged observations never surfaced) onto this repo's own producer/consumer seams. The same sweep also produced the second change here, and rejected a third candidate on measurement.

## What Changes

1. `scripts/knowledge-validate.sh` filters `index.md` through the injector's own predicate first, then looks for the slug in what survives — validating what the consumer actually receives rather than a looser superset. Composing the predicate (rather than duplicating it as a regex) also avoids interpolating a slug into a pattern.
2. `tests/test-knowledge.sh` gains two regressions: an example-based test that extracts `^- \[` from `hooks/session-start-hook.sh` itself and first proves the fixture is genuinely dropped by that real predicate, and a structural test asserting the validator's and the hook's predicate literals are byte-identical so neither side can drift.
3. `skills/agent-team-review/SKILL.md` adds one proportionality / root-cause question to the `quality-reviewer` brief, pinned by `tests/test-adversarial-governance.sh` to that specific lens.

Deliberately NOT changed: `scripts/memory-validate.sh` carries the same loose predicate against `MEMORY.md`, but auto-memory is a Claude Code built-in with no injector of ours, so there is no consumer contract to align to. The rule is "match your consumer", not "tighten every grep".

## Capabilities

### Modified Capabilities
- `unified-context-stack`: the committed-knowledge tier's validator now enforces the session-start injector's contract, closing a silent non-delivery path.
- `adversarial-review`: the `quality-reviewer` lens gains a proportionality / root-cause question.

## Impact

- `scripts/knowledge-validate.sh` — index check composes the injector predicate; error message names the required bullet shape and points at the rebuild script.
- `skills/agent-team-review/SKILL.md` — one added reviewer question.
- `tests/test-knowledge.sh`, `tests/test-adversarial-governance.sh` — regressions.
- `CHANGELOG.md` — entries under Fixed and Added.
- No dependency, manifest, hook, or config change. No change to the Forgetful / auto-memory backend split.

## Why

After a compaction, Claude Code re-attaches each previously invoked skill cut to its first 5,000 tokens (exactly 20,000 characters, ending in "[... skill content truncated for compaction; use Read on the skill path if you need the full text]"), and all re-attached skills share a 25,000-token budget, newest first; a skill that does not fit is dropped entirely. Sources, measured 2026-10-25: the Claude Code docs ("Skill content lifecycle"), the installed 2.1.308 binary (5,000 and 25,000 token constants), and 25 truncated re-attachments in local transcripts (2.1.277-2.1.308), including this repo's `openspec-ship` (22,183 → 20,000).

Five owned skills exceed the line: incident-analysis (83,053 bytes), alert-hygiene (65,670), agent-team-review (47,871), runtime-validation (23,790), openspec-ship (22,289). Their later instructions vanish after compaction in exactly the long sessions that use them, and each also costs its full size on every invocation. Superpowers 7.0.1 already moved its skills under the line.

## What Changes

- Each over-limit `SKILL.md` keeps its load-bearing instructions in a core under the budget and moves situational detail, verbatim, into `skills/<name>/references/*.md`, named from the core with the condition under which to Read it. Nothing is deleted.
- A test fails when an owned `SKILL.md` exceeds 19,500 bytes, except for a listed set of pending skills, each with a size ceiling equal to its current size that falls with the file and may rise only in a commit whose message states the reason.
- Order: openspec-ship, runtime-validation, agent-team-review, alert-hygiene, incident-analysis (its word-count ratchet moves in the same commit).

## Capabilities

### Modified Capabilities

- `auto-claude-skills`: owned skills fit the post-compaction re-attach budget.
- `runtime-validation`: the visual-regression report's session-scope note now lives in `skills/runtime-validation/references/report-template.md`.
- `adversarial-review`: the `quality-reviewer` brief now lives in `skills/agent-team-review/references/reviewer-prompts.md`.

## Impact

- `skills/{openspec-ship,runtime-validation,agent-team-review,alert-hygiene,incident-analysis}/SKILL.md` and new `references/` files; a new size test; content tests that grep those SKILL.md files (they may need to read the reference files too).
- No routing, hook or behaviour change beyond what a model reads at first load.

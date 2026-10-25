# Design: owned skills fit the post-compaction re-attach budget

## Intent

Keep every owned skill's instructions present after compaction, and stop paying a large skill's full size on every invocation. Owner-approved 2026-10-25 ("proceed with your recommendations"), after the limit was measured.

## Approaches considered

1. **Reorder only** — move load-bearing rules into the first 19,900 characters and rely on the truncation marker's "use Read" for the rest. Cheap, but depends on the model noticing; a full 5,000-token skill still crowds the 25,000-token shared budget; no saving at first load.
2. **Core plus references (chosen)** — the superpowers 7.0.1 pattern and the documented Claude Code practice: a core `SKILL.md` under the budget, situational detail in `references/` read on demand. Survives compaction, frees budget for other skills, and cuts the cost of every invocation.
3. **Shrink by deletion** — rejected: this content is owner-written and test-guarded; moving is enough.

## Decisions

1. **Budget: 19,500 bytes per owned `SKILL.md`, frontmatter included.** The re-attach cut is 20,000 characters including a ~110-145-character base-directory header; bytes are at least characters, and frontmatter is stripped before re-attachment, so 19,500 file bytes is inside the line with margin.
2. **The core holds:** the trigger/purpose, every hard rule and gate, the step sequence, and an index of reference files, each with the condition that says when to Read it ("Before writing the archive, Read references/archive.md"). Situational detail (long tables, schemas, worked examples, rationale, per-provider variants) moves verbatim.
3. **Validation before rollout:** after the first split (openspec-ship), one behavioral check — a headless isolated-HOME run in which the skill is invoked and the situation that needs a reference file arises — confirms the model Reads the reference. If it does not, the core must carry that rule inline instead.
4. **Guard:** `tests/test-skill-reattach-budget.sh` fails for any owned `SKILL.md` over 19,500 bytes, except entries in an explicit pending list whose recorded ceilings may only fall; a skill leaves the list when split. Content tests that grep a moved passage are pointed at its new file in the same commit. A skill whose rules alone exceed the budget (agent-team-review: 30,546 bytes after every non-rule block moved) moves its situational detail anyway and stays pending at its new size, with its core ordered so the load-bearing rules come first and end inside the first 19,500 bytes, until a prose pass.
5. **One skill per commit, each reviewed for "no instruction lost"** (every imperative in the old file located in the core or a named reference file).

## Out of scope

Rewording or shortening the skills' content beyond the move (a separate prose pass); external plugins' skills; any routing or hook change.

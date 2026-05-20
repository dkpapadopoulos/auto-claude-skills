# Forgetful consolidation sequencing — design

## Problem

In a recent SHIP-phase session on a separate project, two architectural learnings (`SPY+AGG benchmark backfill`, `Replay DB seed-once`) were saved to per-project auto-memory at `~/.claude/projects/<project>/memory/` but never written to Forgetful, despite being cross-project infrastructure patterns that warrant cross-session persistence.

The session model framed the miss as "auto-mode classifier blocked after push denial." Investigation confirmed there is no classifier in this plugin — Forgetful writes are explicit `mcp__forgetful__execute_forgetful_tool` calls the model must make. The actual cause is workflow sequencing: the ship-and-learn doc does not order memory consolidation relative to `git push`, so when the push gate fires (REVIEW/VERIFY/consolidation warnings in `hooks/openspec-guard.sh`), the model jumps to satisfying the gate and never returns to the explicit Forgetful write.

Forgetful MCP itself is healthy: `get_current_user` returns a populated profile, `FORGETFUL_CONNECTION_CHECK=1` is set, and the project list responds. The MCP layer is not the problem; the workflow contract around it is incomplete.

This is the first observed miss since Forgetful integration shipped (PR #37, 2026-05-19, plugin v3.35.0 — see [[project_forgetful_integration_tightening]]). One miss on day 2 of adoption is not yet a pattern that justifies new enforcement mechanism.

## Capabilities Affected

- `unified-context-stack` — the `ship-and-learn` phase doc dictates the consolidation contract. Edit `skills/unified-context-stack/phases/ship-and-learn.md` to order consolidation explicitly before `git push`.

That is the only subsystem touched in code. The follow-on data action (recovering the two orphaned learnings) writes to Forgetful via MCP but does not modify the plugin.

## Out-of-Scope

- **No hard-block consolidation guard.** `hooks/openspec-guard.sh:99-121` stays advisory. Promoting it to hard-deny is the documented revival trigger if 2+ more misses occur in the next 4 weeks; until then it would be premature mechanism.
- **No new hooks.** `consolidation-stop.sh` reminder + `openspec-guard.sh` warning are sufficient signals; the gap is operational ordering, not signal strength.
- **No changes to Forgetful MCP setup, banner, or detection.** Those shipped in PR #37 and are working.
- **No changes to per-project auto-memory.** It already worked correctly in the affected session — that is why the learnings were not lost outright.
- **No retroactive automation to mirror auto-memory into Forgetful.** Different scopes (project-local vs cross-project) — see [[reference_memory_backend_boundary]] and `skills/unified-context-stack/tiers/historical-truth.md`. Dual-write is explicitly discouraged.

## Approach

**Change 1 — re-order the consolidation step in `ship-and-learn.md`.**

Today the doc reads: as-built docs (OpenSpec) → consolidation marker → Memory Consolidation section. The `git push` step is not anchored in the ordering, so the model can interleave it after as-built but before consolidation.

Edit the phase doc to make the ordering explicit and to call out the push-gate interaction:

> Memory consolidation MUST complete before the first `git push` attempt of the SHIP phase. The push gate in `openspec-guard.sh` will interrupt the SHIP flow if consolidation hasn't run, and re-entering the gate path tends to drop the consolidation step. Sequence: as-built docs → memory consolidation → consolidation marker → push.

Keep the change minimal — one re-ordered paragraph plus one short rationale line. No new sections, no new mechanism.

**Change 2 — recover the two orphaned learnings.**

User pastes the content (or summarises) of `SPY+AGG benchmark backfill` and `Replay DB seed-once`. I write them to Forgetful using `create_memory` with `source_repo`, `confidence`, and `encoding_agent` provenance. They are cross-project infrastructure patterns (benchmark backfill, replay DB seed) — Forgetful is the right home, per the memory-backend boundary in `historical-truth.md`.

**Change 3 — pre-commit a kill criterion in the design doc and in Forgetful.**

Capture the rule: "If Forgetful consolidation is skipped 2+ more times in the next 4 weeks (by 2026-06-17), promote `openspec-guard.sh:99-121` from `_WARNINGS` to hard-deny." This belongs in the design doc and as a Forgetful memory so it survives this session.

## Acceptance Scenarios

1. **Given** the SHIP phase has begun with new architectural learnings, **when** the model reads `ship-and-learn.md`, **then** memory consolidation appears as a step that explicitly precedes `git push`, with a one-line rationale that the push gate cannot interrupt the path if consolidation already ran.
2. **Given** the two orphaned learnings have been recovered, **when** I query Forgetful for `"SPY AGG benchmark"` and `"replay DB seed"`, **then** matching memories with non-null `source_repo` and `confidence` are returned in `primary_memories`.
3. **Given** the kill criterion is recorded, **when** reviewing this work on 2026-06-17, **then** I can find the trigger ("2+ skipped consolidations") in both the design doc and Forgetful, and decide whether to promote the warning to a hard block.
4. **Given** Forgetful consolidation is skipped 0–1 more times in the next 4 weeks, **when** the kill date arrives, **then** no hard-block guard is added — the lightweight ordering fix is judged sufficient.

## Decision

Proceed with the three changes above. No new mechanism, doc-only code change, plus a one-time data recovery and a pre-committed kill criterion. Defer any guard hardening to the recurrence trigger.

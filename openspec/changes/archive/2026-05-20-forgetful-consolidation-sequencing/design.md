# Design: Forgetful consolidation sequencing

## Architecture

The SHIP phase composition runs five steps: REVIEW → VERIFY → SHIP (openspec-ship) → SHIP (memory consolidation) → SHIP (finishing-a-development-branch). Memory consolidation lives in the Memory Consolidation section of `skills/unified-context-stack/phases/ship-and-learn.md` and is implemented as an explicit operator action — the model calls `mcp__forgetful__execute_forgetful_tool create_memory` (or the fallback flat-file write).

The push gate is `hooks/openspec-guard.sh:99-121`. It fires on `git push` invocations and emits a `CONSOLIDATION GUARD` warning via the `_WARNINGS` accumulator when the consolidation marker is missing or stale. The gate is advisory, not blocking.

Failure mode the change addresses: when the model reaches SHIP and attempts `git push` before consolidating, the gate warning fires and the operator response path tends to satisfy the gate's surface requirement (re-run, retry, push) without returning to the consolidation step. The explicit Forgetful write is never made.

The fix is a single doc edit that anchors consolidation in the SHIP sequence: as-built docs → memory consolidation → consolidation marker → `git push`. By placing consolidation upstream of the push attempt, the gate cannot interrupt the path.

## Dependencies

None. This change is documentation-only.

## Decisions & Trade-offs

**Decision 1 — doc-only fix, not a hard guard.** A hard-deny consolidation guard would mechanically prevent the miss but introduces friction on every push, including ad-hoc pushes outside the SHIP composition where consolidation is not relevant. One miss on day 2 of Forgetful adoption is not yet a pattern. Adding mechanism now would over-fit to a single data point.

**Decision 2 — pre-commit a kill criterion rather than monitor passively.** Without a written-down trigger, "wait and see" becomes "forget and never harden." The kill criterion (2+ misses by 2026-06-17) is specific, dated, and recorded in three places (design doc, per-project memory file, Forgetful memory id 8) so it survives session boundaries.

**Decision 3 — recover the orphaned learnings rather than write them off.** The two missed learnings (`SPY+AGG benchmark backfill`, `Replay DB seed-once`) describe cross-project infrastructure patterns valuable beyond the originating Dion session. Per the memory-backend boundary documented in `tiers/historical-truth.md`, Forgetful is the right home for cross-session architectural knowledge.

**Rejected alternative — promote the warning to hard-deny now.** Rejected because one miss is a workflow gap, not a pattern. Documented as the revival path with a concrete trigger.

**Rejected alternative — add a PostToolUse hook that auto-mirrors auto-memory to Forgetful.** Rejected because dual-write violates the orthogonality principle established in PR #37: per-project auto-memory is project-local conversation memory; Forgetful is cross-project architectural memory. Different scopes, different retention semantics. An auto-mirror would erase the scope distinction.

## Capabilities Affected

- `unified-context-stack` — extends the Memory Consolidation section of the Ship & Learn phase with an explicit push-ordering requirement.

## Out-of-Scope

- Hard-deny consolidation guard in `hooks/openspec-guard.sh`. Deferred behind the 2026-06-17 kill criterion.
- New hooks, scripts, or runtime mechanism.
- Changes to Forgetful MCP detection, banner, or capability flags. PR #37 work stays as-is.
- Per-project auto-memory schema or write path. Already correct.
- Retroactive automation to mirror auto-memory into Forgetful. Different scopes by design.

## Acceptance Scenarios

1. **Given** the SHIP phase has begun with new architectural learnings, **when** the model reads `skills/unified-context-stack/phases/ship-and-learn.md`, **then** memory consolidation appears as a step that explicitly precedes `git push`, with a one-line rationale that the push gate cannot interrupt the path if consolidation already ran.
2. **Given** the two orphaned learnings have been recovered, **when** `mcp__forgetful__query_memory` is called for `"SPY AGG benchmark"` or `"replay DB seed-once"`, **then** matching memories with non-null `source_repo` (`damianpapadopoulos/Dion`) and `confidence` (0.85) are returned in `primary_memories`.
3. **Given** the kill criterion is recorded, **when** reviewing this work on 2026-06-17, **then** the trigger ("2+ skipped consolidations") is findable in the design doc, the per-project memory file `project_forgetful_consol_kill_criterion.md`, and Forgetful memory id 8.
4. **Given** Forgetful consolidation is skipped 0–1 more times in the next 4 weeks, **when** the kill date arrives, **then** no hard-block guard is added — the lightweight ordering fix is judged sufficient and the kill criterion memory is removed.

## Decision

Ship the doc-only sequencing fix. Recover the two orphaned learnings. Pre-commit the kill criterion. Defer guard hardening to the recurrence trigger.

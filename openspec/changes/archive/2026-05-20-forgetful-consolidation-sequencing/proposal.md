## Why

The Forgetful MCP integration shipped in PR #37 (plugin v3.35.0, 2026-05-19) but the SHIP-phase consolidation flow did not anchor memory consolidation relative to `git push`. On day 2 of adoption a user reported the first observed consolidation miss: per-project auto-memory captured two cross-project learnings (`SPY+AGG benchmark backfill`, `Replay DB seed-once`) but Forgetful did not. Root cause was workflow sequencing — the `Memory Consolidation` section in `skills/unified-context-stack/phases/ship-and-learn.md` did not call out that consolidation must precede the first `git push`, so the push gate in `hooks/openspec-guard.sh:99-121` interrupted the SHIP flow and the operator recovery path dropped the explicit Forgetful write.

One miss on day 2 of adoption is a workflow gap, not a pattern. Adding mechanism (hard-deny guard) would be premature. The fix is a documentation re-order plus a pre-committed kill criterion.

## What Changes

1. **Explicit push-ordering callout in the phase doc:** the `Memory Consolidation` section in `skills/unified-context-stack/phases/ship-and-learn.md` now opens with a `**Sequence:**` callout stating that consolidation MUST complete before the first `git push` of SHIP, names the push gate by its exact path (`hooks/openspec-guard.sh`), and gives the concrete ordered sequence `as-built docs → memory consolidation → consolidation marker → git push`.
2. **Recovery of the two orphaned learnings:** the two cross-project learnings that originally missed Forgetful were recovered into Forgetful via `mcp__forgetful__execute_forgetful_tool create_memory` with `source_repo`, `confidence`, and `encoding_agent` provenance, scoped to a new `Dion` Forgetful project.
3. **Pre-committed kill criterion for guard hardening:** if Forgetful consolidation is skipped 2+ more times before 2026-06-17, promote `hooks/openspec-guard.sh:99-121` from the `_WARNINGS` accumulator path to a hard `deny` path, mirroring the REVIEW/VERIFY push-gate pattern at lines 39-59. Recorded in `~/.claude/projects/.../memory/project_forgetful_consol_kill_criterion.md` (per-project) and Forgetful memory id 8 (cross-session).

## Capabilities

### Modified Capabilities
- `unified-context-stack`: extends the Ship & Learn phase with an explicit push-ordering requirement for memory consolidation. Builds on the Memory Consolidation contract introduced by PR #37.

## Impact

- `skills/unified-context-stack/phases/ship-and-learn.md` — one new paragraph (`**Sequence:**` callout) at the top of the `Memory Consolidation` section. No other doc structural changes.
- Forgetful MCP state — three new memories (ids 6, 7, 8) and a new `Dion` project (id 2). Out of repo diff scope; verifiable via `mcp__forgetful__query_memory`.
- `~/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/` — new file `project_forgetful_consol_kill_criterion.md` plus `MEMORY.md` index entry. Out of repo diff scope.

Out of scope (deferred behind kill criterion):
- Hard-deny consolidation guard in `hooks/openspec-guard.sh:99-121` — stays advisory until 2+ more misses by 2026-06-17.
- New hooks or runtime mechanism.
- Changes to Forgetful MCP setup, banner, or detection (PR #37 shipped and is working).

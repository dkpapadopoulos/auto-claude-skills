# Forgetful consolidation sequencing — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-order the memory-consolidation step in `ship-and-learn.md` so it explicitly precedes `git push`, recover two orphaned learnings (`SPY+AGG benchmark backfill`, `Replay DB seed-once`) from Dion auto-memory into Forgetful, and pre-commit a kill criterion for harder enforcement.

**Architecture:** Doc-only change to one phase file plus three Forgetful `create_memory` writes (two recovery, one kill-criterion). No new mechanism, no new hooks. Defers any guard hardening to a documented recurrence trigger (2+ skips by 2026-06-17).

**Tech Stack:** Markdown (skill phase doc), Forgetful MCP `mcp__forgetful__execute_forgetful_tool`, existing `bash tests/run-tests.sh` regression suite.

---

## File Structure

- **Modify:** `skills/unified-context-stack/phases/ship-and-learn.md` — add explicit push-ordering callout in the Memory Consolidation section.
- **No code files touched.** All other tasks operate on Forgetful state via MCP.
- **Source files (read-only):**
  - `~/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-Dion/memory/project_spy_agg_benchmark_backfill.md`
  - `~/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-Dion/memory/feedback_replay_db_seed_once.md`

---

### Task 1: Re-order consolidation before push in `ship-and-learn.md`

**Files:**
- Modify: `skills/unified-context-stack/phases/ship-and-learn.md`

- [ ] **Step 1: Read the current file to confirm current ordering**

Run: `cat skills/unified-context-stack/phases/ship-and-learn.md`
Expected: lines 32-56 contain the `## Memory Consolidation` section with no explicit ordering vs `git push`.

- [ ] **Step 2: Insert push-ordering callout at the top of the Memory Consolidation section**

Use the Edit tool to replace this exact block:

```
## Memory Consolidation

Evaluate your available tools and execute the highest available tier:
```

with:

```
## Memory Consolidation

**Sequence:** Memory consolidation MUST complete before the first `git push` of the SHIP phase. If you push before consolidating, the push gate in `hooks/openspec-guard.sh` will interrupt the flow with a CONSOLIDATION GUARD warning, and the operator path back to the consolidation step is fragile — recovery typically drops it. Order: as-built docs → memory consolidation → consolidation marker → `git push`.

Evaluate your available tools and execute the highest available tier:
```

- [ ] **Step 3: Verify the edit landed cleanly**

Run: `grep -n "Sequence:" skills/unified-context-stack/phases/ship-and-learn.md`
Expected: one line matching `**Sequence:** Memory consolidation MUST complete before the first \`git push\``

- [ ] **Step 4: Run the test suite to confirm no regression**

Run: `bash tests/run-tests.sh`
Expected: all suites pass (routing, registry, context). The change is doc-only so no test should fail; if any does, stop and investigate before continuing.

- [ ] **Step 5: Commit the doc change**

```bash
git add skills/unified-context-stack/phases/ship-and-learn.md docs/plans/2026-05-20-forgetful-consolidation-sequencing-design.md docs/plans/2026-05-20-forgetful-consolidation-sequencing-plan.md
git commit -m "docs: order memory consolidation before git push in ship-and-learn"
```

Note: `docs/plans/` is gitignored — `git add` will refuse without `-f`. Use `git add -f docs/plans/2026-05-20-*.md` if needed.

---

### Task 2: Recover orphaned `SPY+AGG benchmark backfill` learning into Forgetful

**Files:**
- Read: `/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-Dion/memory/project_spy_agg_benchmark_backfill.md`
- Write: Forgetful `create_memory`

- [ ] **Step 1: Read the source memory file**

Use the Read tool on `/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-Dion/memory/project_spy_agg_benchmark_backfill.md`.

Extract: title (from `name:` frontmatter), description (from `description:` frontmatter), body (everything after the closing `---`), updated_at if present.

- [ ] **Step 2: Verify it isn't already in Forgetful**

Run via `mcp__forgetful__execute_forgetful_tool`:

```json
{"tool_name": "query_memory", "arguments": {"query": "SPY AGG benchmark backfill CLI gap", "query_context": "checking duplicate before recovery write"}}
```

Expected: `primary_memories` is empty or contains nothing whose title matches `SPY+AGG benchmark backfill`. If a match exists, STOP — manual review needed.

- [ ] **Step 3: Write to Forgetful with provenance**

Run via `mcp__forgetful__execute_forgetful_tool`:

```json
{
  "tool_name": "create_memory",
  "arguments": {
    "title": "SPY+AGG benchmark backfill",
    "content": "<paste full body from source memory file, ≤2000 chars; if longer, summarise preserving rationale + decision>",
    "context": "Recovered from Dion per-project auto-memory after SHIP-phase consolidation was missed on 2026-05-19. Cross-project pattern — applies to any quant/replay workload needing historical fill.",
    "keywords": ["spy", "agg", "benchmark", "backfill", "replay", "dion"],
    "tags": ["pattern", "infrastructure", "recovered"],
    "importance": 7,
    "source_repo": "damianpapadopoulos/Dion",
    "source_files": ["per-project auto-memory: project_spy_agg_benchmark_backfill.md"],
    "confidence": 0.85,
    "encoding_agent": "claude-opus-4-7"
  }
}
```

Expected: response with non-null `id` and the title echoed back.

- [ ] **Step 4: Verify by querying**

Run via `mcp__forgetful__execute_forgetful_tool`:

```json
{"tool_name": "query_memory", "arguments": {"query": "SPY AGG benchmark backfill", "query_context": "post-write verification"}}
```

Expected: `primary_memories[0].title` is `"SPY+AGG benchmark backfill"` and `source_repo` is `"damianpapadopoulos/Dion"`.

---

### Task 3: Recover orphaned `Replay DB seed-once` learning into Forgetful

**Files:**
- Read: `/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-Dion/memory/feedback_replay_db_seed_once.md`
- Write: Forgetful `create_memory`

- [ ] **Step 1: Read the source memory file**

Use the Read tool on `/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-Dion/memory/feedback_replay_db_seed_once.md`.

Extract: title (from `name:` frontmatter), description, body, and the `Why:` / `How to apply:` lines if present (feedback memories use that structure per project CLAUDE.md memory schema).

- [ ] **Step 2: Verify it isn't already in Forgetful**

Run via `mcp__forgetful__execute_forgetful_tool`:

```json
{"tool_name": "query_memory", "arguments": {"query": "replay DB seed once Dion", "query_context": "checking duplicate before recovery write"}}
```

Expected: no matching primary memory. If a match exists, STOP — manual review needed.

- [ ] **Step 3: Write to Forgetful with provenance**

Run via `mcp__forgetful__execute_forgetful_tool`:

```json
{
  "tool_name": "create_memory",
  "arguments": {
    "title": "Replay DB seed-once",
    "content": "<paste full body including Why: / How to apply: lines; ≤2000 chars>",
    "context": "Recovered from Dion per-project auto-memory after SHIP-phase consolidation was missed on 2026-05-19. Cross-project rule — applies to any replay/backtest harness with a deterministic seed-once contract.",
    "keywords": ["replay", "db", "seed", "deterministic", "dion", "feedback"],
    "tags": ["rule", "infrastructure", "recovered"],
    "importance": 7,
    "source_repo": "damianpapadopoulos/Dion",
    "source_files": ["per-project auto-memory: feedback_replay_db_seed_once.md"],
    "confidence": 0.85,
    "encoding_agent": "claude-opus-4-7"
  }
}
```

Expected: response with non-null `id`.

- [ ] **Step 4: Verify by querying**

Run via `mcp__forgetful__execute_forgetful_tool`:

```json
{"tool_name": "query_memory", "arguments": {"query": "replay DB seed once", "query_context": "post-write verification"}}
```

Expected: `primary_memories[0].title` is `"Replay DB seed-once"`.

---

### Task 4: Pre-commit kill criterion for guard hardening

**Files:**
- Write: Forgetful `create_memory`
- Write: append to `~/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/MEMORY.md`
- Create: `~/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/project_forgetful_consol_kill_criterion.md`

- [ ] **Step 1: Create the per-project memory file with frontmatter**

Use the Write tool to create `/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/project_forgetful_consol_kill_criterion.md` with this exact content:

```markdown
---
name: forgetful-consol-kill-criterion
description: If Forgetful consolidation is skipped 2+ more times before 2026-06-17, promote openspec-guard.sh consolidation check from warning to hard-deny
metadata:
  type: project
---

If Forgetful consolidation is skipped 2+ more times before 2026-06-17, promote the consolidation check in `hooks/openspec-guard.sh:99-121` from the `_WARNINGS` accumulator path to a hard `deny` path, mirroring the REVIEW/VERIFY push-gate pattern at lines 39-59.

**Why:** First miss observed 2026-05-19 (one day after Forgetful integration shipped in PR #37). One miss on day 2 is not yet a pattern. Adding mechanism now would be premature. See [[project_forgetful_integration_tightening]].

**How to apply:** When reviewing SHIP-phase telemetry around 2026-06-17, count Forgetful consolidation misses since 2026-05-20. ≤1 miss → keep advisory-only and remove this entry. ≥2 misses → execute the guard hardening above; design lives at `docs/plans/2026-05-20-forgetful-consolidation-sequencing-design.md` in the auto-claude-skills repo.
```

- [ ] **Step 2: Add the index entry to MEMORY.md**

Use the Edit tool on `/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/MEMORY.md` to insert this line in the `## Project` section (keep chronological-by-write order, i.e. append near the end of the Project list before `## Reference`):

```
- [Forgetful consolidation kill criterion](project_forgetful_consol_kill_criterion.md) — promote openspec-guard consol check to hard-deny if ≥2 more skips by 2026-06-17
```

- [ ] **Step 3: Mirror the kill criterion to Forgetful**

Run via `mcp__forgetful__execute_forgetful_tool`:

```json
{
  "tool_name": "create_memory",
  "arguments": {
    "title": "Forgetful consolidation guard kill criterion (auto-claude-skills)",
    "content": "If Forgetful consolidation is skipped 2+ more times before 2026-06-17, promote the consolidation check in hooks/openspec-guard.sh:99-121 from the _WARNINGS accumulator path to a hard deny path, mirroring the REVIEW/VERIFY push-gate pattern at lines 39-59. First miss observed 2026-05-19. Review date: 2026-06-17. ≤1 miss → keep advisory. ≥2 → harden. Design: docs/plans/2026-05-20-forgetful-consolidation-sequencing-design.md.",
    "context": "Pre-committed kill criterion — avoids premature mechanism after the first consolidation miss on day 2 of Forgetful integration adoption.",
    "keywords": ["forgetful", "consolidation", "guard", "kill-criterion", "openspec-guard", "auto-claude-skills"],
    "tags": ["decision", "kill-criterion", "deferred-work"],
    "importance": 8,
    "source_repo": "damianpapadopoulos/auto-claude-skills",
    "source_files": ["docs/plans/2026-05-20-forgetful-consolidation-sequencing-design.md", "hooks/openspec-guard.sh"],
    "confidence": 0.95,
    "encoding_agent": "claude-opus-4-7"
  }
}
```

Expected: response with non-null `id`.

- [ ] **Step 4: Verify Forgetful entry by querying**

Run via `mcp__forgetful__execute_forgetful_tool`:

```json
{"tool_name": "query_memory", "arguments": {"query": "forgetful consolidation kill criterion 2026-06-17", "query_context": "post-write verification"}}
```

Expected: `primary_memories[0]` contains the kill-criterion memory.

---

### Task 5: Run final regression check and write consolidation marker

**Files:**
- Run: `bash tests/run-tests.sh`
- Touch: consolidation marker via shared helper

- [ ] **Step 1: Re-run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: all suites pass. The only code path that could regress is registry/routing if the phase doc was structurally malformed (e.g., broken markdown headers used by future tooling); test failure here means the Step 2 edit needs review.

- [ ] **Step 2: Touch the consolidation marker (eat our own dog food)**

```bash
source hooks/lib/consol-marker.sh
touch "$(consol_marker_path)"
ls -l "$(consol_marker_path)"
```

Expected: marker file created at the path returned by `consol_marker_path`, mtime ≥ last commit mtime.

- [ ] **Step 3: Confirm openspec-guard would not warn on subsequent commit**

Run: `bash -n hooks/openspec-guard.sh && echo "syntax ok"`
Then: simulate a final mental walk-through — last commit was Step 1 of Task 1; marker was just touched; `_marker_time >= _last_commit` should hold; consolidation warning suppressed.

Expected: no execution issue; this is a sanity step, not a hard gate.

---

## Self-Review

- **Spec coverage:**
  - Acceptance scenario 1 (consolidation precedes push in doc) → Task 1.
  - Acceptance scenario 2 (Forgetful query returns recovered learnings) → Tasks 2 & 3, verification steps.
  - Acceptance scenario 3 (kill criterion findable in design doc + Forgetful) → Task 4 Steps 1-3.
  - Acceptance scenario 4 (no hard guard added) → out-of-scope by design; no task implements it.
- **Placeholder scan:** Two intentional `<paste full body…>` markers in Tasks 2 & 3 Step 3. These are operator inputs whose values depend on reading the source files in Step 1 of each task — kept explicit rather than guessed. Not a planning failure.
- **Type consistency:** All Forgetful calls use the same `tool_name` and argument shape returned by `discover_forgetful_tools`. `source_repo` slug is consistent (`damianpapadopoulos/Dion`, `damianpapadopoulos/auto-claude-skills`). Memory slugs match between MEMORY.md index entry and the file name.
- **Branch hygiene:** Plan does not include branch creation — assumed running on a working branch the operator chose. If running on `main`, create a branch before Task 1 Step 5.

# Phase 5: Ship & Learn

Before completing the session, consolidate what was learned.

## REQUIRED Before Memory Consolidation: As-Built Documentation

If the session produced working code from a Superpowers plan, generate permanent "as-built" documentation before consolidating learnings:

**Tier 1: OpenSpec CLI** (`command -v openspec` succeeds)
- Execute the `openspec-ship` skill to create a retrospective change folder under `openspec/changes/<feature>/`
- Use `/opsx:propose` (default profile) to scaffold and populate with schema-native templates
- Run `openspec validate <feature>` to verify the change folder
- Update `CHANGELOG.md` under `[Unreleased]`
- Use `/opsx:archive` with delta-spec sync prompt: sync deltas to canonical `openspec/specs/<capability>/spec.md`, then move to archive

**Tier 2: Claude-Native Fallback** (OpenSpec CLI not available)
- Generate the same artifact contract using the templates in the `openspec-ship` skill
- Same change-folder structure, same filenames, same required section headings, compatible content
- Manually move change folder to `openspec/changes/archive/`. Create canonical spec only if none exists; skip canonical update with warning if one already exists

**Skip Condition:** Skip ONLY if no Superpowers plan was executed (debugging, reviewing, or non-feature work). Scope and size of the change are NOT skip criteria — if a plan was executed, as-built documentation is required regardless of how small the change.

**REQUIRED before completing session:** If you discovered any architectural rules, API quirks, or project conventions during this session, you MUST consolidate them using the highest available tier below before claiming the work is done. After consolidation, write the marker via the shared helper so the path stays in sync with `openspec-guard.sh` and `consolidation-stop.sh` (which look for it):

```bash
. "$CLAUDE_PLUGIN_ROOT/hooks/lib/consol-marker.sh"
touch "$(consol_marker_path)"
```

The helper keys the marker off the git remote URL when one is configured, so worktrees and clones of the same repo share a single marker. Falls back to the absolute project path when there's no remote.

## Memory Consolidation

**Sequence:** Memory consolidation MUST complete before the first `git push` of the SHIP phase. If you push before consolidating, the push gate in `hooks/openspec-guard.sh` will interrupt the flow with a CONSOLIDATION GUARD warning, and the operator path back to the consolidation step is fragile — recovery typically drops it. Order: as-built docs → memory consolidation → consolidation marker → `git push`.

Evaluate your available tools and execute the highest available tier:

### IF forgetful_memory = true
Use Forgetful to permanently store (see `tiers/historical-truth.md` for tool mechanics):
- New architectural rules or conventions discovered
- Project-specific quirks that would be useful in future sessions
- Decisions made and their rationale

### IF context_hub_cli = true
Execute `chub annotate <library-id> "<note>"` to record:
- API workarounds or undocumented behaviors discovered
- Version-specific gotchas (e.g., "React Router v7 requires X wrapper in our setup")

### IF NEITHER are available
Append findings to `docs/learnings.md` using standard file editing:

```
## YYYY-MM-DD: [Brief Title]

**Context:** [What task was being performed]
**Learning:** [The specific insight or workaround]
**Applies to:** [Which part of the codebase]
```

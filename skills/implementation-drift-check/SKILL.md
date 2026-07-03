---
name: implementation-drift-check
description: Use when verifying an implementation still matches its spec or plan — during REVIEW or SHIP, or on demand to check drift, confirm you are still on plan, or run a spec check — surfacing spec deviations, unvalidated assumptions, and untested code paths against Intent Truth
---

# Implementation Drift Check

Detect spec drift, surface unvalidated assumptions, and identify coverage gaps by comparing the current implementation against its Intent Truth (specs, plans, eval packs).

## When to Use

- **Auto-co-selection (REVIEW + SHIP):** Fires automatically during REVIEW phase (parallel) and SHIP phase (sequential fallback) when comparison material exists. The SHIP entry is suppressed if the skill already ran during REVIEW (session-marker gate).
- **Explicit invocation (IMPLEMENT):** Invoke directly during implementation with prompts like "check drift", "am I still on plan", "spec check". When no comparison material exists, degrades to assumptions-only mode.

### Comparison Sources (any of these triggers auto-fire)

- `openspec/changes/<feature>/specs/` (active OpenSpec change)
- `docs/plans/*-design.md`, `docs/plans/*-plan.md`, `docs/plans/*-spec.md` (canonical live intent)
- `openspec/specs/<capability>/spec.md` (post-ship canonical)
- `docs/superpowers/specs/*-design.md`, `docs/superpowers/plans/*.md` (legacy fallback)
- `tests/fixtures/evals/*.json` (eval pack scenarios)

## Auto-Co-Selection Guard

The hook enforces an **artifact-presence** gate mechanically before this skill is emitted into the composition chain. This is a cheap filesystem glob check (~5ms) in the post-jq Bash filter. If no artifacts match, the composition entry is suppressed -- the LLM never sees it.

**Glob patterns checked (canonical first, legacy fallback):**

1. `openspec/changes/*/` (any active OpenSpec change)
2. `docs/plans/*-design.md` (canonical design artifact)
3. `docs/plans/*-plan.md` (canonical plan artifact)
4. `docs/plans/*-spec.md` (canonical spec artifact)
5. `openspec/specs/*/spec.md` (any canonical spec)
6. `docs/superpowers/specs/*-design.md` (legacy design spec)
7. `docs/superpowers/plans/*.md` (legacy plan)
8. `tests/fixtures/evals/*.json` (any eval pack)

**Mode selection is LLM-evaluated.** When the hook emits the entry (artifacts exist), this SKILL.md guides mode selection:

- **Full drift mode:** At least one spec or plan artifact is available for cross-referencing against the implementation diff.
- **Assumptions-only mode:** No spec/plan artifacts exist (e.g., explicit invocation during implementation without a written spec), or only eval packs are available. Degrades gracefully to surfacing assumptions and gaps without drift analysis.

## Step 1: Gather Comparison Material

Read in priority order using canonical retrieval precedence. Stop reading duplicates -- if a source was already consumed at a higher priority level, skip it.

### Priority 1: Active OpenSpec Changes (highest authority)

```
openspec/changes/<feature>/specs/
```

Active work-in-progress specs from OpenSpec. These represent the most current intent and override all other sources when present.

### Priority 2: Canonical Live Intent

```
docs/plans/*-design.md
docs/plans/*-plan.md
docs/plans/*-spec.md
```

The canonical location for live design documents, implementation plans, and specifications. These are the primary Intent Truth for features that have not yet shipped.

### Priority 3: OpenSpec Canonical Specs (post-ship)

```
openspec/specs/<capability>/spec.md
```

Post-ship authoritative specifications. These represent the as-built state of shipped capabilities and serve as the baseline for incremental work.

### Priority 4: Archived Intent (optional)

```
docs/plans/archive/
```

Shipped intent history. Not required for drift analysis, but useful for understanding the evolution of a feature when the current implementation diverges from original intent.

### Priority 5: Legacy Superpowers (deprecated fallback)

```
docs/superpowers/specs/*-design.md
docs/superpowers/plans/*.md
```

Legacy location for design specs and plans. These paths are deprecated in favor of `docs/plans/` but are checked as a fallback for older features that have not been migrated.

### Priority 6: Eval Pack Scenarios

```
tests/fixtures/evals/*.json
```

Behavioral eval packs committed as test fixtures. These define example-based behavioral expectations and are cross-referenced for coverage gaps in both modes.

### Determine Mode

After gathering, select mode:

- If **any** spec or plan artifact was found (Priority 1-5): use **full drift mode** (Steps 2 + 3 + 4 + 5).
- If **only** eval packs or **nothing** was found: use **assumptions-only mode** (Steps 3 + 4 + 5, skip Step 2).

## Step 2: Analyze Drift (Full Mode)

When comparison material exists, run `git diff` against the relevant base (main branch or last reviewed commit) and cross-reference against gathered material across three drift dimensions.

### Spec Alignment

For each requirement or acceptance scenario found in specs, check whether the implementation addresses it.

| Flag | Meaning |
|------|---------|
| `implemented-as-specified` | Implementation matches the spec requirement |
| `modified-from-spec` | Implementation addresses the requirement but differs from spec (include evidence of what changed and why) |
| `added-without-spec` | Implementation includes behavior not described in any spec |
| `specified-not-implemented` | Spec requirement has no corresponding implementation in the diff |

### Plan Alignment

For each task in the implementation plan, check whether the git diff includes changes to the expected files and scope.

| Flag | Meaning |
|------|---------|
| `completed-as-planned` | Task completed with expected files and scope |
| `modified-from-plan` | Task completed but files or scope differ from plan |
| `added-without-plan` | Changes exist that correspond to no planned task |
| `planned-not-implemented` | Planned task has no corresponding changes in the diff |

### Review-Induced Drift

If code review findings were addressed (check for review-round commits or explicit review feedback in conversation), identify whether fixes changed the behavioral contract -- not just code quality improvements.

Flag any scope changes introduced by review feedback. This dimension catches drift that is invisible to spec/plan alignment because it was introduced after the original implementation.

## Step 3: Surface Assumptions and Gaps (Always Runs)

This step runs in both full drift mode and assumptions-only mode.

### Assumptions Made

What does the implementation assume about inputs, environment, dependencies, or user behavior that is not validated by tests? List each assumption with the file and line range where it appears.

### Untested Paths

What code paths in the diff have no test exercise? Cross-reference test files against implementation files. Flag:
- Functions/methods with no corresponding test
- Conditional branches (error handlers, fallbacks, edge cases) not covered
- Integration boundaries (API calls, file I/O, external services) without mocks or integration tests
- **Test-weakening (gate-gaming):** if `project-verification` reported `gate_gaming_status: suspect` — or the diff deleted assertions, added skip/xfail/disabled markers, or loosened a fixture to make a previously-failing gate pass — flag it as a blocking drift finding. A path that *was* tested and is now un-tested is drift, not coverage.
- **Coverage gap (test-adequacy):** if `project-verification` reported `coverage_adequacy_status: suspect` (new code below the changed-line coverage floor), surface it as a blocking coverage-gap drift signal, mirroring the gate-gaming treatment above — this catches new code shipping untested, whereas gate-gaming catches existing tests getting weaker. `unverified` or an absent status is not itself drift (fail-open, no coverage tooling present) and MUST NOT be surfaced as a finding on that basis alone.

### Edge Cases Identified

What boundary conditions does the implementation handle that are not explicitly specified? These represent implicit assumptions that may or may not be correct.

### Eval Pack Gaps

If eval packs exist in `tests/fixtures/evals/*.json`, identify:
- Scenarios defined in eval packs that have no corresponding test implementation
- Implementation behavior not covered by any eval pack scenario
- Eval pack scenarios whose `expected` values conflict with the actual implementation

## Step 4: Report

Terminal output always. Two report shapes depending on mode.

### Full Drift Mode Report

Title: `## Implementation Drift Check`

Six sections:

```markdown
## Implementation Drift Check

### Spec Alignment
| Requirement | Status | Evidence |
|-------------|--------|----------|
| [requirement from spec] | [flag] | [file:line or diff reference] |

### Plan Alignment
| Task | Status | Notes |
|------|--------|-------|
| [task from plan] | [flag] | [file changes or scope note] |

### Review-Induced Changes
- [behavioral contract changes introduced by review feedback, if any]

### Assumptions
- [unvalidated assumption] (file:line)

### Untested Paths
- [code path without test coverage] (file:line)

### Recommended Actions
- [ ] [actionable item to resolve drift or close gaps]
```

### Assumptions-Only Mode Report

Title: `## Assumptions & Gaps`

Three sections:

```markdown
## Assumptions & Gaps

### Assumptions
- [unvalidated assumption] (file:line)

### Untested Paths
- [code path without test coverage] (file:line)

### Recommended Actions
- [ ] [actionable item to close gaps]
```

## Step 5: Persistence

### Terminal Output

Always emit the report to terminal. This is the primary output channel.

### Spec/Design Document Annotation

When drift is found (any `modified-from-spec`, `added-without-spec`, `specified-not-implemented`, `modified-from-plan`, `added-without-plan`, `planned-not-implemented` flag, or Review-Induced changes), append a concise **"Post-Implementation Notes"** section to the relevant spec or design document:

```markdown
## Post-Implementation Notes

_Added by implementation-drift-check on YYYY-MM-DD_

- [concise summary of each drift finding]
- [recommended follow-up actions]
```

Append to the first matching document in priority order:
1. `docs/plans/*-design.md` (canonical)
2. `openspec/changes/<feature>/specs/` (active OpenSpec)
3. `docs/superpowers/specs/*-design.md` (legacy)

If the document already has a "Post-Implementation Notes" section, append to it rather than creating a duplicate.

### Session Marker

After completing (regardless of mode or findings), write the session marker to prevent duplicate execution during SHIP fallback:

```bash
touch ~/.claude/.skill-drift-check-ran-$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)
```

This marker is checked by the SHIP phase session-marker gate. If the marker exists, the SHIP fallback entry is suppressed.

## Verification

Before reporting "no drift", confirm:

- The comparison ran against the highest-authority source available (active OpenSpec change > canonical live intent > archived), and which source was used is stated.
- Each spec/plan requirement was checked against the actual implementation -- not assumed aligned.
- Assumptions and untested paths are listed explicitly; an empty list means "verified none", not "did not look".
- The session marker is written only after the analysis actually ran.

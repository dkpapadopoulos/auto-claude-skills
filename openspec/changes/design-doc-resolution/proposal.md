# Proposal: readers find the design doc themselves

## Why

The registered hint cut (PR #427) removed PERSIST DESIGN, the only text that asked the model to
record a design doc's path in session state. When it was shown, 5 of 188 sessions ran it. The
readers of that path then found nothing and did nothing, without saying so. Separately, the
spec-driven session notice states "design intent persisted to openspec/changes/ (committed)",
which the hook never checks.

## What Changes

- New `scripts/resolve-design-doc.sh`: read-only, four outcomes (`resolved`, `stale`,
  `ambiguous`, `absent`), exit 3 for "could not check".
- `openspec-ship` calls it in Step 3, before it creates or moves anything, and its Step 7c
  (Divergences) acts on that kept outcome; `deploy-gate` check 4 calls it directly. Both say
  what they found. `openspec-ship`'s per-outcome table, and where each source's doc sits after
  the archive steps, is `references/design-doc-outcomes.md`.
- `openspec-ship` Step 7b (archive) is unchanged: only recorded paths are moved.
- The spec-driven notice becomes "spec-driven preset active: design intent belongs in
  openspec/changes/<feature>/; not verified this session".
- No injected prompt text is added. The compliance census closed further display proposals.

## Capabilities

- **Modified:** `skill-routing` (two requirements added, one modified). The `openspec-ship`
  requirements already live there.

## Impact

- Default-mode users with no design doc see one more line at SHIP ("No design doc found").
- A doc found by filename may be the wrong one where two changes share a slug; it is labelled
  and never moved.
- **Not changed, and still silent:** the PLAN-phase design-completeness note and the
  post-compaction list of active changes. Both run in hooks on the per-prompt or recovery path
  and neither changes a decision.
- **Deliberate reductions, not covered by anything else:** VERTICAL SLICES, DEBUG ESCALATION,
  JIRA PR TITLE and CARRY SCENARIOS stay removed. `deploy-gate` checks PR status and never
  creates or titles a PR, so the Jira rule has no owned home. A user who wants one of these can
  put it in their own `CLAUDE.md`.
- **Not built:** a spec-driven presence check (it needs a decision on what it measures first),
  and an audit of whether the push gate's review record stays valid after later commits.

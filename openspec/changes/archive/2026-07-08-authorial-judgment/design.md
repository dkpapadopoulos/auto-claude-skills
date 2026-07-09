# Design: authorial-judgment skill

## Architecture

A single `role: domain` skill, activated by regex triggers, that instructs the
model to run a **post-draft revision pass** over authored persuasive prose. It
does not steer drafting and does not gate any SDLC phase — on activation it says:
produce (or take) the draft, then apply this pass before final delivery.

Files:

- `skills/authorial-judgment/SKILL.md` — frontmatter + the 6 distilled moves +
  the §1 hard gate. Kept lean (well under the fat-SKILL.md guard line).
- `skills/authorial-judgment/references/red-flags.md` — the source doc's two
  overlapping taxonomies (§11 Red Flag Taxonomy, §13 feedback labels) merged into
  **one** table: `flag -> what it means -> repair`, plus the feedback-capture shape.
- `config/default-triggers.json` + `config/fallback-registry.json` — mirrored
  routing entries (these two files always move together).
- `tests/fixtures/routing/authorial-judgment.txt` — MATCH/NO_MATCH done-gate.

### The 6 distilled moves (SKILL.md core)

The source doc's 14 sections carry ~6 distinct signals; the rest are restatements.
The mapping:

1. Authorial position, not persona (§10, §1)
2. Real objection = real friction (§3, §4)
3. Deliberation only when earned (§2)
4. Sharpening re-articulation (§6, §9)
5. Rhythm follows thought (§7)
6. AI-inversion refusal (§12, §14)

Hard gate (§1), stated once: texture must come from real details / real
uncertainty / real editorial judgment; if none exist, keep the prose clean — do
not decorate the absence. This is the anti-hallucination guard.

## Trade-offs

- **Distill vs faithful port.** We distill (approach B) rather than paste all 14
  sections (A). A faithful port would inherit the doc's own redundancy and violate
  its §6 (repetition-as-depth) and §8 (overexplained-baseline) rules, and blow the
  lean-SKILL.md budget. The full source reasoning is preserved in git history and
  this change; the taxonomy is one click away in `references/`.
- **Narrow vs broad triggers.** We fire only on authored persuasive prose, not on
  all "human-facing docs." READMEs/specs/changelogs are the genre where this lens
  is *counterproductive* (they should be complete, linear, certain), so widening
  the trigger would route the skill into writing it actively harms.
- **Revision lens vs drafting steering.** Post-draft only. The doc is a review
  layer by its own framing; steering at draft time would fight the model's
  generation and is harder to bound.

## Dissenting views

- One could argue a lightweight drafting-principles layer (position +
  anti-genericness) should always be available, with a separate heavier review
  audit (approach C). Rejected as over-engineered for a single-author lens and a
  poor fit for the role-cap model — it spends two role slots on one concern.
- One could argue for broader coverage (all prose deliverables) to maximize
  reach. Rejected: coverage into reference/procedural genres is negative value,
  not neutral.

## Decisions

- Name: `authorial-judgment` (clearer in a routing breadcrumb than
  "cognitive-texture"; matches the repo's plain-descriptive house style).
- Role: `domain`, advisory, capped by the existing 2-domain rule.
- Verification is **deterministic** (routing + registry + fixture tests). This is
  advisory prose guidance, not probabilistic agent behavior, so no eval pack is
  warranted.
- Standalone; no cross-links to `doc-coauthoring` (structured docs) or
  `writing-skills` (authoring SKILLS) — confirmed non-overlapping.

## Out-of-scope

- READMEs, API docs, tutorials, how-tos (reference/explanatory writing).
- Specs, changelogs, release notes, status updates, meeting notes (procedural).
- Code, commit messages, tests, config.
- Drafting-time steering; a two-layer generate+review split.

## Implementation Notes (synced at ship time)

- Triggers were tightened twice during REVIEW without changing the spec's
  acceptance scenarios (activation on persuasive prose; suppression on
  reference/procedural/code writing still hold — suppression was strengthened,
  not relaxed):
  1. Held-out routing review removed over-broad bare alternations (`post`
     substring-matching "postgres/postmortem", bare `column`/`generic`/`draft`/
     `copy`) that fired on dev/reference prompts.
  2. Whole-branch review applied the repo-native `(^|[^a-z])` boundary idiom to
     `op.?ed` and `article` (which were substring-matching "developed" and
     "particle"). All regressions are locked into
     `tests/fixtures/routing/authorial-judgment.txt`.
- `available: false` in `fallback-registry.json` matches the repo's established
  fallback-entry shape (parity with `alert-hygiene`), not `true`.

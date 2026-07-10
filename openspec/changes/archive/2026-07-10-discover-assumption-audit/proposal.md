# Proposal: DISCOVER Assumption Audit — evidence-graded business-case assessment

## Why

The DISCOVER phase (`skills/product-discovery/SKILL.md`) synthesizes a discovery
brief and asks a yes/no validation question. Three verified gaps:

1. **No business-case assessment layer** — nothing structures "is this worth
   building": no assumption surfacing/grading, no option set, no
   conditions-under-which-this-holds. (Source: adoption triage of a 21-skill
   consulting-methods pack; mechanics adopted, skills rejected.)
2. **Rubber-stamp HITL** — "does this brief capture the problem accurately?" is
   the zero-friction approval pattern that erodes human understanding
   (curiosity-gap literature; "understanding is the new bottleneck"). The human
   should do the connective work on a map, not approve a smooth paragraph.
3. **Self-graded quality is theater** — any evidence-grading the model assigns
   itself needs a deterministic external check (repo doctrine: self-rated
   confidence is a bias signal, not a discriminator).

Design was adversarially sparred with Codex (fresh, repo-grounded); one FATAL
finding (gitignored artifact kills CI gating) and five NEEDS-CHANGE verdicts
were verified against the repo and folded in. See
`docs/plans/2026-07-10-discover-assess-ledger-design.md` (v3) for the full trail.

## What Changes

1. **Assumption Audit stage** in `skills/product-discovery/SKILL.md` (~20-line
   core; rubric/schema/worked example in
   `skills/product-discovery/references/assumption-audit.md`):
   fact/inference/unknown tags on brief findings; an `## Assumption Ledger`
   section (belief, category, importance, `evidence_kind`, `source_ref`,
   `observed_at`, `claimed_grade` A-F, `kill_threshold`); top-3 materiality
   cutoff for kill-shot tests; option set incl. do-nothing with conditional
   recommendation; **two-step active-choice validation** (criteria/weights
   confirmed before scores are shown — anti-backfill + desirable difficulty);
   serendipity close; proportional (skippable-by-declaration, model-judged).
2. **`scripts/assumption-audit-check.sh`** — deterministic local boundary
   check: ledger section present, fragile assumptions have pre-declared
   thresholds, option set includes do-nothing, and the **evidence-ceiling
   rule**: `claimed_grade` must not exceed the ceiling implied by
   `evidence_kind` (A/B require direct evidence + greppable `source_ref`;
   analogous caps at C; expert_judgment caps at D). Advisory, fail-open,
   NOT CI (artifact home `docs/plans/` is gitignored).
3. **DESIGN-hint routing companion** — one model-gated line in
   `config/default-triggers.json` + `config/fallback-registry.json`
   (both, per canonical-source rule): new-feature ask with no discovery
   brief → suggest product-discovery first.
4. **Opt-in behavioral red fixture** — mock user pushes to proceed on a
   D-grade belief; the skill must surface the fragility (vocabulary-family
   assertions; no engagement-lift claims).

## Capabilities

- **Modified (via ADDED requirements):** `pdlc-closed-loop` — discovery brief
  gains the Assumption Audit; validation becomes two-step active-choice.
- **Touched subsystems:** `skills/product-discovery/`, `scripts/`,
  `config/default-triggers.json`, `config/fallback-registry.json`, `tests/`.

## Impact

- Deferred by design: ledger writes to session state (race surface), autonomy
  assumptions in the ledger (no reader), decision-drift agent judge
  (prerequisite artifact must be used in anger first).
- Accepted v1 limitation: hold/kill outcomes have no LEARN baseline (that
  machinery only covers shipped work); kill list lives in the discovery doc.
- Dogfood kill criterion (pre-committed): if over the next 3-5 real
  discoveries the ledger is consistently skipped or grades pass untouched by
  the human, cut the two-step back or demote the stage.

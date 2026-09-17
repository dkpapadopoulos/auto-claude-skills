# Proposal: design seed — a shipped styleguide plus the method to own one

## Why

The plugin has no design capability. `prototype-lab` compares variants in prose
only and defines "prototype" as repo files (SKILL.md, hooks, scripts);
`runtime-validation` owns UI *evidence* (Playwright, axe, Lighthouse, visual
regression) but nothing upstream of it; `frontend-design` is an external skill
reachable only through a keyword regex and present in no phase composition.
Nothing anywhere ships tokens, a styleguide, or a design system.

The consequence is the failure mode the prior art names directly: one-shotting a
UI without foundations produces mixed results that cannot be evolved. A model
with no enumerated token scale invents `#3B82F6`; a model with no reference
markup imitates whatever templated default it has seen most.

Two halves are wanted, and only one of them is a skill:

1. **Immediate benefit** — an opinionated starter (tokens, styleguide, one
   reference page, checks) a project copies and then owns.
2. **The method** — how to ground a design question, explore alternatives,
   bring a decision back, and verify it in a browser, so a project can author
   and evolve its own styleguide rather than inherit ours forever.

A prior internal note (`docs/plans/2026-09-08-writing-repo-acs-learnings-design.md`)
rejected a `create-design-brief`/`ingest-design` bridge as "a two-product
workflow outside ACS's routing scope". That reasoning is **partly superseded and
partly upheld**: design is now explicitly in scope (superseded), but the bridge
depends on a `DesignSync` MCP tool that is unavailable to many users and is not
authorized in the author's own environment (upheld). This change therefore
builds the local lane and **cuts the bridge**.

## What Changes

**Added — `assets/design-seed/`, copied into a target project, never read from
the plugin at runtime:**

- `tokens.css` — **the** source of truth: scales plus **semantic roles**
  (`--text-numeric`, `--status-hold-fg`, …), light and dark. Roles matter as
  much as finiteness: a closed set prevents inventing a value, not picking the
  wrong allowed one.
- `tokens.json` — the same values for tooling, held to **exact parity** with
  `tokens.css` by a test, so the two can never drift.
- `styleguide.md` — the DO/DON'T pairs a lint **cannot** express (numeric
  display, status semantics, empty vs missing, density), plus the lint's
  **declared coverage boundary**.
- `reference.html` — **one** static, dependency-free page showing realistic
  composition and the hard states (dense numerics, missing vs empty, status,
  light and dark). No framework, no build, no npm, so it cannot rot.
- `checks/token-lint.sh` — requires **token references** for the properties it
  declares it covers, over an explicit file set; exit-code shaped so
  `runtime-validation` can adopt it. Its scope is stated, not implied.
- `ADOPT.md` — the copy procedure, which records provenance (preset name and
  version) and adds a pointer to the project's own agent instructions.

**One default preset ships.** Alternatives are optional and deferred: an
obligatory choice contradicts "benefit immediately".

**Added — `docs/design-seed-method.md`**: the method (ground → explore → decide →
implement → verify) and the local-only lane used when no design project is
reachable. **No stack recommendation** — naming TS/React/Vite/Tailwind/shadcn
adds scope without helping either test, and the tokens are framework-neutral by
construction.

**Added — `tests/fixtures/design-seed/sample-project/`**: a tiny frontend
acceptance fixture, separate from the pilot, because a Python CLI cannot
validate tokens, density or a reference page. It is what proves the lint
catches a seeded violation and that a semantic-token change moves the intended
elements.

**Modified — `config/default-triggers.json` + `config/fallback-registry.json`**:
one DESIGN-phase hint pointing at the seed and the method. **No new skill and no
new trigger regex** — see Decisions in `design.md`.

**NOT built in this change:** any new owned skill; any `DesignSync`-dependent
skill; a design-review skill (`runtime-validation` owns UI evidence); a
component generator (IMPLEMENT owns that); version pinning of any frontend
dependency.

## Capabilities

- **Added: `design-foundations`** — a project's visual conventions as owned,
  checkable artifacts, plus the method for authoring and evolving them.
- **Modified: `pdlc-safety`** — unchanged requirements; the DESIGN hint is
  additive and introduces no gate.
- **Modified: `cross-family-panel`** — the receipt hook's preview verification.
  The durable requirement said a receipt is written only when the harness-returned
  annotation "exists and hashes to the digest"; that annotation is size-gated and
  absent for every real package, so the requirement as written made consent
  unobtainable. The delta keeps the binding and moves where it is checked, and
  records which check ran. Without this delta the spec would read as an
  indictment of the fix, and the next reviewer would revert it.

> ⚠️ NEW CAPABILITY: this change introduces `design-foundations`. Existing
> capabilities considered and rejected: `pdlc-safety` (owns phase gates and the
> prototype-lab requirement, not visual conventions); `runtime-validation` (owns
> UI *evidence* produced after implementation, not the conventions checked
> against); `skill-routing` (owns selection mechanics); `unified-context-stack`
> (owns retrieval tiers). None has a noun-family or subsystem match.

## Impact

- **Code:** new `assets/design-seed/` tree; two shell checks; one docs file; two
  routing-config hint entries; one new test file.
- **Routing:** hint only. No trigger regex is added, so role-cap selection is
  untouched and no incumbent domain skill can be displaced.
- **Gates:** `tests/test-fixture-coverage.sh` and
  `tests/test-skill-content-coverage.sh` govern *owned skills*; this change adds
  none, so neither gate's population changes.
- **Risk accepted:** a project may ship the default palette unchanged. That is
  adoption, not a defect — the seed is meant to be usable as-is, and provenance
  (preset name + version) is recorded so the choice is visible.

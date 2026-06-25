# Addy agent-skills adoption — design & ranked portfolio

**Date:** 2026-06-25
**Status:** DESIGN persisted; awaiting build go/no-go
**Source:** Re-evaluation of `addyosmani/agent-skills` @ `e0d2e43` (2026-06-23 state; 24 skills + 4 agents + references + hooks)
**Prior pass:** PR #50 `adopt-doubt-discipline` (2026-06-11) — see `[[doubt-discipline-adoption]]`
**Method:** phase-by-phase coverage matrix (4 parallel subagents) → Codex file-grounded validation (×2) → design-debate (architect / critic / pragmatist + Codex 4th voice)

## Problem statement

`addyosmani/agent-skills` is a 52k-star, MIT, prompt-text SDLC skill pack. We mined it once (PR #50). It has since reorganized into a clean DEFINE→…→SHIP lifecycle. Question: what *genuinely new* value can auto-claude-skills adopt, given our differentiator is a **regex routing engine + composition chain + hook-injected phase directives that wrap dependency skills and pass context skill→skill** — and that "their PDLC ⊂ ours" was re-confirmed at full breadth.

## Key framing — three capture mechanisms

We don't *own* superpowers skills (brainstorming, TDD, code-review, systematic-debugging, …) but we **own the orchestration**: when/why each skill fires and what context it hands the next. So three mechanisms exist for capturing an external mechanic:

1. **Graft prompt-text into an OWNED skill** — for mechanics that fit one of our 21 skills.
2. **Depend on addy's plugin** — **REJECTED**: `using-agent-skills` is a competing router (linear decision-tree + fixed 16-step lifecycle that contradicts our phase model); ~18/24 skills duplicate ours/superpowers and would collide with role-caps; the repo fully restructured in 12 days (version-drift risk on code we don't control); plugin-gated routing entries are dead unless the plugin is installed. Users who want addy's standalone skills (frontend-ui, performance) can **co-install** both plugins — they coexist, our routing ignores theirs, the model can still invoke them manually. No coupling, nothing required from us.
3. **Hook-injected phase DIRECTIVE + inter-skill context contract** — wraps a dependency skill we can't edit AND threads context skill→skill. This is the unique-to-us mechanism (e.g. today's `DESIGN→PLAN CONTRACT`, `TRIFECTA CHECK`, `PERSIST DESIGN`, `EVAL STRATEGY` injected directives). The deepest value-add the exploration found: **context-handoff contracts between skills** (intent→brainstorming, scope-manifest IMPLEMENT→REVIEW, citations→REVIEW-verifies).

## Capabilities affected

- **`skill-routing`** (primary, MODIFIED via ADDED requirements) — new phase directives + inter-skill context handoffs + routing entries for any new skills.
- **`unified-context-stack`** (content enrichment) — CITE/UNVERIFIED + inline-planning/confusion nuggets in External Truth consumption guidance.
- **`security-scanner`** (content enrichment) — STRIDE threat-model-first pre-pass.
- **`deploy-gate`** skill (content enrichment; no capability spec today) — staged-rollout/rollback thresholds.
- **`batch-scripting`** skill (content enrichment) — Rule-of-500 cross-link.

## Explicit out-of-scope

- Taking addy's plugin as a hard dependency or routing at its skill names (mechanism 2, rejected).
- T3a observability **composition** wiring (deploy-gate/incident-analysis) — deferred behind a revival trigger.
- T3c api-and-interface-design until reframed for Kotlin/Spring.
- All confirmed skips (below).
- No implementation in this DESIGN artifact — build is a separate go decision.

## Ranked portfolio (debate verdict)

### DO NOW — PR 1 (grafts: owned SKILL.md prose, no routing/eval risk)
1. **T2a** deploy-gate staged-rollout/rollback thresholds (canary %, error/latency triggers). *Also the consumer contract T3a later produces against.*
2. **T2b** security-scanner STRIDE threat-model-first (compact checklist; composes with shipped TRIFECTA directive).
3. **T2e** batch-scripting Rule-of-500 cross-link.
4. **T2c + T2d** unified-context-stack CITE/UNVERIFIED + inline-planning/confusion nuggets (collapses T1c & T1e; placed in External Truth *consumption* guidance per Codex dissent).

### DO NEXT — PR 2 (directives, each EVAL-GATED)
5. **T1a** intent-extraction pre-brainstorming directive → writes `confirmed-intent` to session state → brainstorming reads it. Reuses PERSIST-DESIGN→PLAN-guard plumbing. Hard-gated: fires only when ask is underspecified AND no approved brief. Ships only after a red-first quality eval. Clears the standing PR #50 revival trigger for interview-me mechanics.
6. **T1b** scope-manifest IMPLEMENT→REVIEW contract, consumed by agent-team-review / implementation-drift-check. Probationary, hard phase-gated, eval-gated.

### DO LATER — new skills, standalone-first
7. **T3a** thin observability/instrumentation skill, routes on BUILD/SHIP, absorbs T1d's multi-component mechanic. **Composition deferred** behind revival trigger (manual telemetry→deploy-gate handoff hit ≥2×). T2a ships the consumer contract so it exists when/if wired.
8. **T3b** deprecation-and-migration skill — bounded, episodic, no composition.
9. **T3c** api-and-interface-design skill — after T3b; needs Kotlin/Spring reframe.

### DO ALONGSIDE PR1 — PR-T4: skill-authoring anatomy standard (reshaped per Codex round 3)
Adopt addy's consistent skill anatomy (anti-rationalization / Red Flags / Verification) where it
bears weight. Grounded audit of our 21 owned skills (corrected; headings only, not inline mentions):
- Anti-rationalization sections: **0/21**
- Red Flags sections: **2/21** (agent-team-execution, agent-team-review)
- Verification sections: **1/21** — load-bearing for our evidence-before-assertions philosophy, yet near-absent.

**Scope (reshaped):** add OPTIONAL Rationalizations / Red Flags / Verification sections to the
`skill-scaffold` emitted skeleton (Step 2), to be included where a skill bears discipline or makes a
readiness claim — NOT blanket-mandated on tool/domain skills where they would be filler. Backfill
**Verification** sections only on owned skills that make completion/readiness claims.
**Explicitly excluded:** no behavioral-eval enforcement (the runner asserts output regex / tool calls,
not section quality → would be a checkbox); no extension of `docs/skill-frontmatter-schema.md` (that is
routing metadata, not body anatomy). Small standalone PR, low risk.

### SKIP / fold
T1c, T1e, T1d standalone (collapsed/folded above); using-agent-skills (competing router); performance-optimization (frontend-heavy; backend latency covered by incident loop); ci-cd scaffolding (low freq); ADR-lifecycle (openspec covers traceability); frontend AI-aesthetic (belongs to frontend-design plugin).

### DEFER — idea-refine divergent-lens framework (corrected per Codex round 3)
SKIP idea-refine as a standalone skill: low-frequency for backend feature work; output (~80%) covered by
the Out-of-Scope contract + brainstorming + prototype-lab + the new T1a intent-extraction. The one
uncovered nugget is its **divergent-lens framework** (inversion / constraint-removal / audience-shift /
10x / simplification / expert-lens → 5-8 variations, cluster to 2-3). The real gap is narrow: **no
systematic divergent-lens expansion step before options exist.** (Correction: design-debate is NOT
"purely convergent" — its architect proposes and its critic proposes alternatives; the gap is the
absence of structured *divergent generation before any option is on the table*, not convergence.)
**Defer** with a revival trigger: a genuinely greenfield / novel-product ideation task where
brainstorming's 2-3-approaches visibly under-delivers. If revived, do NOT bloat the opt-in, approval-gated
`design-debate` — prefer a separate lightweight divergent mode. Ranks below T1a (which clears a standing
PR #50 trigger and has no equivalent).

## Recommended approach

Sequence by ROI: **PR1 first** (four paragraph-inserts, zero routing/eval risk, resolves both overlaps by claiming the SKILL.md home), then **PR2** (two directives behind red-first evals), then the new skills standalone-first. Each PR is independently shippable through the normal composition chain.

## Dissenting views (recorded)

- **Codex:** T1c/T1e belong as *directives*, not grafts — citation/inline-planning is execution behavior, and grafting it into a retrieval-tier skill violates that tier's boundary ("don't make the context stack a behavior dumping ground"). *Overridden on cost + low item-value; mitigated by placing the nuggets in External Truth consumption guidance rather than a generic behavior dump.*
- **Critic:** T1a should be cut outright — duplicates brainstorming + product-discovery, risks double-interview, has no eval. *Overridden by gating T1a behind the red-first eval the Critic itself named as the only honest path to adoption.*
- **Codex ranked T1b #1** (highest leverage). *Placed in PR2 behind T1a because T1a sits earlier in the chain and clears a standing trigger.*
- **Architect:** rank by edges created, not capabilities added — hence T2a (the consumer contract) outranks the entire T3a observability skill. *Adopted as the sequencing rule.*
- **Codex (round 3) caught load-bearing audit errors** before they reached this doc: my initial anatomy counts (Red Flags 3/21, Verification 9/21) were inflated by matching inline word-mentions instead of section headings — corrected to 2/21 and 1/21. It also flagged a non-existent `behavioral-evaluation/SKILL.md` and the wrong path for the frontmatter schema, which forced T4 to be reshaped (scaffold-only, no eval enforcement, no schema extension), and corrected the false "design-debate is purely convergent" rationale for the idea-refine deferral. *Re-derive load-bearing numbers cross-model — the recurring lesson.*

## Trade-offs accepted

- **Token/crowding cost** of new directives (PR2): mitigated by hard phase-gating + tight triggers; bounded to two new directives, both eval-gated. Honors the lean-injection rejection (PR #45) "no measured benefit" bar.
- **Deferring T3a composition** may be wrong if the telemetry→deploy-gate handoff is the real point — accepted as an explicit revival criterion, not a silent drop.
- **STRIDE graft** risks bloating security-scanner (already ~1600w) — kept to a compact checklist.

## Acceptance scenarios

See `openspec/changes/adopt-addy-mechanics/specs/skill-routing/spec.md`.

## Decision

Awaiting user go/no-go on PR1. No build started.

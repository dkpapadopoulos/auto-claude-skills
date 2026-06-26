# Design — adopt addy agent-skills mechanics

Full ranked portfolio and method in `docs/plans/2026-06-25-addy-adoption-design.md`.
This file captures the architecture, dissents, and decisions from the design debate
(architect / critic / pragmatist + Codex 4th voice, file-grounded).

## Architecture

Three capture mechanisms for an external mechanic:
1. **Graft into an owned skill** (PR1 items) — prose in a SKILL.md we own; zero routing/token cost.
2. **Depend on addy's plugin** — REJECTED (competing router, overlap, version drift).
3. **Hook-injected phase directive + inter-skill context contract** (PR2 items) — the
   unique-to-us mechanism. A `methodology_hints[]` entry, hard phase-gated, that wraps a
   dependency skill we cannot edit and threads context to the next skill via session state.

Sequencing rule (architect): **rank by edges created, not capabilities added.** The
deploy-gate threshold graft (T2a) is the *consumer contract* that the deferred observability
skill (T3a) must later produce against — so the contract ships before the producer.

## Trade-offs

- New directives cost UserPromptSubmit tokens and crowd the existing hint block. Mitigated
  by hard phase-gating + tight triggers + capping PR2 to two directives, both eval-gated.
  Honors the PR #45 lean-injection rejection ("no measured benefit" bar).
- Deferring T3a composition risks under-delivering if the telemetry→deploy-gate handoff is
  the real point. Accepted as an explicit revival criterion, not a silent drop.
- STRIDE graft risks bloating security-scanner — kept to a compact checklist.

## Dissenting views

- **Codex:** T1c/T1e (citation, inline-planning) should be *directives*, not grafts —
  they are execution behavior, and grafting them into a retrieval-tier skill violates that
  tier's boundary. **Decision:** graft anyway (cost + low item-value) but place them in
  External Truth *consumption* guidance, not a generic behavior dump, to respect the boundary.
- **Critic:** cut T1a (intent-extraction) outright — duplicates brainstorming +
  product-discovery, risks double-interview, has no eval. **Decision:** keep, but ship only
  behind a red-first quality eval — the path the Critic named as the only honest one — and
  hard-gate it to fire solely when the ask is underspecified AND no approved brief exists.
- **Codex ranked T1b #1**; placed in PR2 behind T1a (earlier in chain, clears a standing trigger).

## Round 3 additions (meta-axis: anatomy, references, personas)

- **PR-T4 skill-authoring anatomy standard — RESHAPED (Codex round 3).** Adopt anti-rationalization /
  Red Flags / Verification anatomy as OPTIONAL `skill-scaffold` template sections + backfill Verification
  on readiness-claim skills. Grounded audit (headings only): anti-rationalization 0/21, Red Flags 2/21,
  Verification 1/21. **Excludes** behavioral-eval enforcement (the runner asserts regex/tool-calls, not
  section quality) and any frontmatter-schema extension (`docs/skill-frontmatter-schema.md` is routing
  metadata). Codex caught that my initial counts (3/21, 9/21) were inflated by inline-word matches.
- **Agent personas (test-engineer, code-reviewer) — SKIP.** Covered by pr-review-toolkit + agent-team-review;
  our structured FINDING + evidence/confidence/severity-floor contract is stronger than their freeform templates.
- **Reference checklists — mostly captured/skip.** observability-checklist → folded into T3a; security-checklist
  → feeds the PR1 STRIDE graft; performance/accessibility → frontend (skip/low); definition-of-done &
  orchestration-patterns → mild, optional consolidation, LOW. The progressive-disclosure *pattern* is already
  ours (references/ in incident-analysis, project-verification, supply-chain).
- **idea-refine — DEFER (corrected).** Skip standalone; the uncovered nugget is systematic divergent-lens
  expansion before options exist. The "design-debate is purely convergent" rationale was false (it has an
  architect proposing + a critic proposing alternatives) and is removed. Revival trigger recorded in proposal.

## PR2a as-built (intent-extraction directive)

The design above (line 13) envisioned T1a as a `methodology_hints[]` config entry. As built,
PR2a is **hook-resident** — the directive logic lives in `hooks/skill-activation-hook.sh`, not
in `config/*.json`. The four implementation decisions:

- **D-1 — Hook-resident, not a config hint.** Spec Scenario 2 ("MUST NOT appear when a brief/intent
  exists") needs hard, state-aware suppression, and Scenario 3 injects the *actual* confirmed-intent
  text — neither expressible as a static `"when":"always"` hint (the hints jq branch has no gate
  support; only `parallel`/`sequence` do). So a DESIGN-phase hook block (modeled on the PLAN-phase
  design-completeness guard) handles emission, suppression, and handoff. **No `config/*.json` change.**
  This corrects the earlier "JSON entry in both configs, not a hook-code edit" pricing estimate.
- **D-2 — State is a flat marker file** `~/.claude/.skill-confirmed-intent-<token>` written by
  `openspec_state_set_intent` (and read by `openspec_state_read_intent`) in `hooks/lib/openspec-state.sh`.
  Not the openspec-state JSON, because intent is captured *before* a change slug exists. The hook
  sources the lib via `$PLUGIN_ROOT` (the lib lives in the plugin install, not the user's project).
- **D-3 — Eval is a multi-turn, prominent-injection A/B.** `run-behavioral-evals.sh` injects the skill
  body from `SKILL_PATH` and does not fire the working-tree hook (a live `claude -p` fires the *installed*
  hook). The eval went through three corrections, each forced by a red result (recorded in the eval
  README): (1) a single-turn A/B mis-measured a multi-turn directive — the model correctly stops after
  the first question, so out-of-scope/confirmed-intent convergence can't appear in one turn; rebuilt as a
  **two-turn** scenario (`followup` → `claude -p --resume`) asserting on the convergence (turn-2) output.
  (2) Appending the directive to the end of the skill body under-measured it (1/5); injecting it as a
  prominent `<activation_directive>` block above the skill (`--directive-file`) is the faithful mirror of
  how the hook places it in `additionalContext`. (3) At proper n=5 the original directive prose converged
  only 20% (the n=2 "100%" was noise) — the prose was strengthened to make convergence an *imperative
  pre-proposal gate* ("do NOT propose… you MUST emit the convergence block and stop"). **Result: baseline
  0/5 → treatment 5/5 stable** on out-of-scope + confirmed-intent. C3 (persist) is excluded — the eval
  sandboxes Bash, so the model can't run `openspec_state_set_intent`; that path is covered by the
  deterministic `set_intent` unit test + seeded handoff test. The v2 prose is what ships in the hook. See
  `tests/fixtures/intent-extraction/evals/README.md`.
- **D-4 — Precedence:** confirmed-intent marker (→ handoff, suppress) > discovery brief in openspec
  state (→ suppress) > emit directive. DESIGN phase only. No session token → fail-open to emit
  (Scenario 1); production sessions always carry a token, so suppression/handoff hold there.

Deterministic coverage: `tests/fixtures/scenarios/intent-30..33` (routing + must_match directive
presence / must_not_match suppression) and seeded hook tests in `tests/test-routing.sh` (handoff when
intent present; suppression when discovery brief present). The quality bar is the red-first behavioral
eval (manual, opt-in, API-cost — not in CI `run-tests.sh`).

## Decisions & rejected alternatives

- **Rejected:** addy plugin as a dependency / routing at its skill names (mechanism 2).
- **Rejected:** T1c, T1d, T1e as standalone directives (collapsed into grafts / folded into T3a).
- **Rejected now, revivable:** T3a composition wiring; T3b; T3c (reframe-gated); idea-refine divergent nugget.
- **Confirmed skip:** using-agent-skills, performance-optimization, ci-cd scaffolding,
  ADR-lifecycle, frontend AI-aesthetic, addy agent personas.

# Design: Autonomy↔Control Coherence Guidance

## Architecture

Two surfaces for one principle, chosen by placement (where the value lands), not
by mechanism:

```
DESIGN phase (user is shaping an agentic solution)
   │
   ├─ PRIMARY: AUTONOMY CHECK hint  (phase_compositions.DESIGN.hints)
   │     model-assessed from the design → classify autonomy rung,
   │     assess proportional oversight, help design it in BEFORE PLAN
   │     (teaching surface — improves the solution)
   │
   └─ (if guidance skipped and design still hits a safety review) …
         SECONDARY: agent-safety-review Step 2b  (additive backstop)
               record autonomy rung + oversight strength;
               emit proportional advisory when rung 3-4 × weak oversight;
               trifecta Step 1-2 scoring UNCHANGED
```

**Why primary = a DESIGN hint, not a bigger skill change.** The user's intent is
to raise the *quality of solutions users design and the principles they apply* —
that is a design-*time* teaching act, so it belongs where the user is designing
(the DESIGN methodology-hint surface that already carries `TRIFECTA CHECK` /
`EVAL STRATEGY`), not buried in a risk report that only fires reactively.

**Why secondary = additive Step 2b, not a rewrite.** The trifecta table is an
already-validated safety gate with regression tests and a routing fixture. The
disciplined extension is additive (open/closed): a new orthogonal signal that
never changes an existing classification. Data-flow risk and autonomy-control
coherence are genuinely different axes; folding them into one score would destroy
information about *why* something is flagged.

## The primary hint (AUTONOMY CHECK)

Placed in `config/default-triggers.json` → `phase_compositions.DESIGN.hints`
(anchor: beside the `TRIFECTA CHECK` entry at :1298-1300), `"when": "always"`,
but **self-gated in its own text** to fire only for agentic/AI-solution designs —
exactly how `TRIFECTA CHECK` self-gates on "judge from the actual data flow, do
not wait for a keyword trigger." Draft text:

> AUTONOMY CHECK: During DESIGN, if the solution is an agentic/AI system that
> acts on its own, classify its intended autonomy level — advise (proposes; human
> acts) / recommend (human approves each action) / execute-reversible (acts;
> effects bounded & undoable) / execute-irreversible·unattended (hard-to-reverse
> or runs with no per-run human checkpoint). If the level is execute-reversible or
> higher AND proportional oversight is NOT designed in (per-run approval, HITL,
> manifest+dry-run review, or a bounded/reversible blast radius), help the user
> design that oversight in before leaving DESIGN — autonomy without proportional
> control is a liability, not power. Judge from the actual design; this is
> guidance, not a gate.

**Lockstep:** `config/fallback-registry.json` carries the same DESIGN hints
(verified: it contains the `TRIFECTA CHECK` text). The canonical-source rule
requires the identical hint be added there too, or a fallback session would ship
without it. Both files move in one commit.

## The secondary backstop (Step 2b)

Inserted into `skills/agent-safety-review/SKILL.md` between Step 2 (classify
trifecta risk) and Step 3, and one line into the Step 4 output template. It does
**not** read or alter the Step 2 classification. Shape:

- **Step 2b: Assess autonomy-control coherence.** State the autonomy rung
  (advise / recommend / execute-reversible / execute-irreversible·unattended) and
  whether proportional oversight is present. If rung ≥ execute-reversible AND
  oversight is weak, emit an advisory (proportional to the rung). This is
  independent of the trifecta classification — a design can be Standard trifecta
  risk yet still draw an autonomy advisory.
- **Step 4 output** gains one row: `Autonomy: <rung> · Oversight: <strong|weak>`
  and, when flagged, an `Autonomy advisory:` line. Trifecta rows unchanged.

## Taxonomy decision (the brainstorm output)

- **Four named rungs**, not a binary, and not a numeric score. Named rungs give
  the model concrete language to guide the user and map cleanly to the source
  principle; the *flag* keys only off the top two, so trigger precision is binary
  even though the vocabulary is richer. Rejected: a bare "advisory vs autonomous"
  binary (too coarse to guide) and a 1-5 risk score (invites averaging, which the
  safety-gate discipline forbids).
- **Oversight is the second axis, assessed as strong/weak**, not enumerated — the
  examples (per-run approval, HITL, manifest+dry-run, bounded/reversible blast
  radius) are illustrative so the model generalizes rather than pattern-matches a
  closed list.

## Over-fire boundary (the load-bearing guard)

Codex's central concern: a naive autonomy check double-fires on flows the repo
already governs. The boundary is **"silent whenever oversight is strong"**:

| Design | Autonomy | Oversight | Result |
|--------|----------|-----------|--------|
| batch-scripting codemod (manifest + dry-run + approval) | execute | strong | **silent** ✓ |
| normal REVIEW→VERIFY→SHIP with human gates | varies | strong | **silent** ✓ |
| "auto-formats on save, human commits" | execute-reversible | strong (human commits) | **silent** ✓ |
| unattended nightly agent that commits/acts, no checkpoint | execute-irreversible·unattended | weak | **fires** (firm) |
| local-only autonomous refactor, low trifecta, no review step | execute-reversible | weak | **fires** (soft) |

This is why the fire rule is `rung ≥ 3 AND oversight = weak`, never `rung ≥ 3`
alone. The strong-oversight designs supply the missing control leg themselves.

## Trade-offs (accepted)

- **Model-judged, not deterministic.** Autonomy level and oversight strength are
  interpreted by the model, so results vary run-to-run. Accepted: the condition is
  inherently fuzzy (the repo's rule is model-asks over regex for fuzzy conditions),
  and the output is advisory, not a gate — variance costs a softer nudge, never a
  false block. Verification is an eval subset, not an exact-match unit test.
- **Two surfaces, minor duplication.** The principle is stated in the hint and in
  Step 2b. Accepted: they serve different phases (proactive design-time teaching
  vs. a review-time backstop) and the wording is short; a single surface would
  either miss non-safety-reviewed designs (hint only) or stay reactive (Step 2b
  only).
- **Primary surface is guidance the model may not act on.** A hint is not
  enforcement. Accepted by scope — this raises solution quality by teaching, and
  the backstop covers the safety-review path. Enforcement is explicitly out of
  scope and would contradict the skill's "assessment, not a veto" stance.

## Dissenting views

- *"Park it — it's an external-methodology import with only marketing evidence."*
  (My original call.) Overturned: the gap is a verifiable logic hole in our own
  file (SKILL.md:35), confirmed independently by two reviewers. The evidence
  discipline applies to importing frameworks, not to patching our own gate.
- *"Just do the Step 2b; skip the DESIGN hint."* Rejected against the user's
  reframe: a Step 2b alone stays reactive and only fires on trifecta-triggered
  safety reviews — it improves risk-catching, not the *quality of what the user
  designs*. The hint is the surface that actually changes the solution.
- *"Go broad — ship the whole principle set."* Deferred (aperture Option 2):
  prove the single primitive helps before adding the abstraction.

## Decisions

1. Primary = DESIGN methodology hint (teaching); secondary = additive Step 2b
   (backstop). Both, hint-primary.
2. Additive only — trifecta Step 1-2 scoring and the routing fixture are
   untouched.
3. Four named rungs; flag keyed off rungs 3-4 × weak oversight; severity
   proportional.
4. Over-fire boundary = silent when oversight strong.
5. Lockstep the hint into `fallback-registry.json`.
6. Verify red-first with a safety eval subset: one positive, one over-fire
   negative, authored failing before implementation.

## Security posture

Adds advisory guidance text only. No trifecta legs (`private_data`,
`untrusted_input`, `outbound_action` all Absent for this change). Touches
`config/` routing files → push-gate routing-governance requires a clean
`project-verification` verdict covering HEAD before merge (dogfooded).

## Out of Scope

- DesignTheAgent canvas/coach subsystem; broader principle set; trifecta-table
  mutation (Options B/C); any enforcement/gating; generic SDLC guidance;
  a `unified-context-stack/phases/design.md` rewrite (a one-line pointer there is
  optional and deferred).

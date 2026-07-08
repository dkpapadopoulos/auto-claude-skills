# Proposal: Autonomy↔Control Coherence Guidance (DESIGN phase)

## Why

The plugin helps users design **higher-quality solutions**, not merely
lower-risk ones. When a user is designing an **agentic/AI solution**, one
principle governs whether the result is powerful or a liability:

> `power = cognition × control × reach` — a capable agent with wide reach and
> **no proportional control/oversight is a liability, not power.**
> (Surfaced during a DesignTheAgent evaluation; the canvas/coach itself was
> rejected as ~90% redundant — see Out of Scope. This one principle was the
> genuine, non-redundant gap.)

The plugin does not help users apply that principle **at design time**. Two
independent, file-grounded reviews (Claude + Codex) confirmed the gap:

- `skills/agent-safety-review/SKILL.md` scores risk **purely by counting the
  data-flow trifecta** (`private_data` / `untrusted_input` / `outbound_action`),
  SKILL.md:14-35. Autonomy level is never an input.
- SKILL.md:35 gives any design with 0-1 trifecta fields
  **"Standard risk — No special action required"** — regardless of how
  autonomous it is. A design like *"an agent that autonomously refactors and
  makes local commits on non-sensitive code, no external input"* is high
  autonomy, low trifecta → it sails through with no design-time nudge to build
  in proportional oversight.
- The only autonomy reasoning that **does** exist is **downstream at REVIEW**
  (`config/default-triggers.json:1412-1414` ADVERSARIAL REVIEW; `agent-team-review`
  SKILL.md:243-263) — reactive change-review, not design-time guidance. So the
  user gets no help *shaping* the solution; at best they get *flagged* later.

The value target is the **quality of the solution the user is helped to build
and the principle they are helped to apply** — teach autonomy↔control coherence
while they design, so they design the oversight in.

## What Changes

Scope is deliberately **one principle, correctly placed** (the aperture the user
selected — Option 1; the broader principle-*set* is a clean later extension, see
Out of Scope). Two surfaces, primary + backstop:

1. **PRIMARY — DESIGN-phase guidance (teaching surface).** A new methodology
   hint (`AUTONOMY CHECK`) in `phase_compositions.DESIGN.hints`, beside the
   existing `TRIFECTA CHECK` and `EVAL STRATEGY` hints. When the design is an
   agentic/AI solution, it prompts the model to: classify the intended
   **autonomy level** on a four-rung ladder, assess whether **proportional
   oversight** is designed in, and — if not — help the user add it *before*
   leaving DESIGN. This is **model-assessed judgment from the actual design, not
   a regex** (consistent with `TRIFECTA CHECK`'s "judge from the data flow" and
   the repo's standing "model-asks over regex for fuzzy conditions" rule).

2. **SECONDARY — `agent-safety-review` backstop.** A new **Step 2b** (additive;
   does **not** mutate the Step 1-2 trifecta scoring) that records the autonomy
   level and emits a proportional advisory note when autonomy is high and
   oversight weak — catching the case if the design-time guidance was skipped
   and the design still reaches a safety review at low trifecta count.

**The autonomy ladder** (all four named in output, for guidance):

| Rung | Meaning |
|------|---------|
| `advise` | Proposes; a human acts |
| `recommend` | Proposes a specific action; a human approves each one |
| `execute-reversible` | Acts autonomously; effects bounded / observable / easily undone |
| `execute-irreversible · unattended` | Acts autonomously with hard-to-reverse effects, **or** runs recurring/unattended with no per-run human checkpoint |

**Fire rule (the boundary):** guidance/flag engages **only when autonomy is rung
3 or 4 AND oversight is weak** — severity proportional (rung 4 firmer, rung 3
softer). *Weak oversight* = no per-run approval, HITL checkpoint, manifest+dry-run
review, or bounded/reversible blast radius.

**Why it cannot over-fire:** it is silent whenever oversight is strong, so
`batch-scripting` (manifest + dry-run + approval), normal REVIEW→VERIFY→SHIP
human gates, and ordinary "does X automatically with a human approving each run"
all stay silent. Only genuinely unattended / broad-blast-radius autonomous
mutation *without* a human checkpoint engages it.

## Capabilities

- **Modified: `pdlc-safety`** — DESIGN-phase safety guidance gains an
  autonomy↔control coherence dimension (primary hint) and `agent-safety-review`
  gains an additive autonomy advisory (backstop). No new capability.

## Impact

- `config/default-triggers.json` — one hint added to `phase_compositions.DESIGN.hints`.
- `config/fallback-registry.json` — **same hint, in lockstep** (the fallback
  registry carries the DESIGN hints too; canonical-source rule requires both move
  together).
- `skills/agent-safety-review/SKILL.md` — new Step 2b + one autonomy line in the
  Step 4 output template. Additive; Step 1-2 trifecta scoring byte-unchanged.
- `tests/` — **red-first safety eval subset** (this is model-interpreted
  behavior, per EVAL STRATEGY): a positive case (high-autonomy/weak-oversight
  must surface guidance) and a negative **over-fire guard** (manifest+approval
  batch design must **not**). Authored failing before implementation.
- The skill's existing routing fixture (`tests/fixtures/routing/agent-safety-review.txt`)
  is **unaffected** — no trigger change.

## Out of Scope

- The **DesignTheAgent canvas + coach** as a subsystem — rejected as ~90%
  redundant with existing DISCOVER/DESIGN/safety machinery.
- The broader **principle *set*** (role clarity, memory governance, grounded
  context, human oversight as separate cells). This ships the single autonomy↔
  control principle; the set is a clean later extension only if demand appears.
- **Mutating the trifecta risk table** — the rejected Option B (autonomy
  escalates the risk *level*) and Option C (two-axis rewrite). Both re-baseline a
  working safety gate; the advisory note captures the value additively.
- **Enforcement.** This is advisory guidance, not a gate/veto — consistent with
  `agent-safety-review`'s existing "produces an assessment, not a veto" stance.
- Generic SDLC / code-hygiene guidance.

## Governance note (this change)

- **Trifecta of this change itself:** `private_data` Absent, `untrusted_input`
  Absent, `outbound_action` Absent — it adds advisory text to a config file and a
  skill markdown. No lethal-trifecta legs added.
- It **touches `config/` routing files**, so the push-gate routing-governance
  rule applies: merge requires a clean `project-verification` verdict covering
  HEAD (dogfooding). Planned as part of the REVIEW→SHIP chain.

# Design: the four approved composition contracts

Audit provenance `8c027b9`. Behavioural acceptance in `tests/probes/ACCEPTANCE.md`.

## Architecture

Two mechanisms produce all four defects, and conflating them is how the first fix plan
went wrong:

1. **Hook selection** — regex triggers scored in `skill-activation-hook.sh` decide what
   is injected.
2. **Model choice** — the model then picks from the skills it can see. Measured: the
   second-opinion prompt was *not* routed to `panel` (it routes to `brainstorming` and
   `runtime-validation`), yet the model invoked `panel` anyway, because panel is the
   only consultation-shaped option in the roster.

A fix touching only triggers addresses mechanism 1 and leaves mechanism 2 intact.
**Both the triggers and the model-visible descriptions must change.**

D2 and D3 share a root cause. The `Composition:` chain is built by
`_walk_composition_chain`, which anchors on `PROCESS_SKILL` and walks
`precedes`/`requires`. The chain appeared because `brainstorming` co-selected and
supplied the anchor — not because `panel` declares `phase: PLAN`.

## The four contracts

### C1 — single-model consultation (D1)

A dedicated second-opinion method, distinct from `panel`, with two explicit modes:

- **independent opinion** — one named model answers a clean question, and the prior
  answer is **excluded**;
- **answer critique** — the prior answer is **deliberately included**.

Roster size cannot express this, which is why formalising panel's roster is rejected:
the distinction is *what the participant sees*, not how many participants there are.
The upstream `sop` contract already specifies it ("omit prior answer from inferred
question; show inferred question, ask if uncertain").

### C2 — independent consultation versus debate (D2)

Independent consultation and interactive debate get distinct intent contracts **and
distinct model-visible descriptions**. Independence must never be claimed for output
produced by interaction.

### C3 — consultation during development (D3)

A consultation request **preserves an active workflow and does not start an unrelated
one**. This is deliberately not "suppress the chain": suppression would strand a
development session that pauses to consult. Detour → `continue` must resume the
original chain, and a mixed request ("get independent opinions, then implement the
agreed plan") keeps its chain.

### C4 — authorized planning → synthesis (D4)

An authorized composition owner may complete a merge, gated on **evidence about its
inputs**, not on a flag: the inputs must be complete, attributable to distinct
participants, associated with this request, and still fresh. Standalone
model-invocation restrictions on `synthesize` are preserved.

## Trade-offs

- C1 adds a skill rather than reusing panel: more surface, more artifacts (routing
  fixture, content test), against a contract panel structurally cannot express.
- C3 preserves rather than suppresses: more complex than a blanket rule, and the
  blanket rule would break the case the audit could not measure.
- C4 gates on evidence rather than relaxing the flag: more work than a conditional
  exemption, and a conditional exemption is where safety properties rot.

## Dissenting views

An external reviewer argued C1 could be satisfied by formalising panel's roster
behaviour, since the model already narrowed to one participant unprompted. Rejected:
one compensating trace does not establish robustness across model changes, and roster
size does not express the exclude-the-prior-answer requirement.

A second view held that the observed `synthesize` refusal demonstrates the flag
protects provenance. It does not — `synthesize` accepts scratch files and inline
perspectives, so the flag blocks model invocation and nothing more. C4 is therefore
specified on input evidence rather than on the flag.

## Decisions

- Fix order: contracts on paper → consultation/workflow discrimination → C1 routing
  and C2/C3 selection changes as separable increments → C4 last.
- The ported probes are frozen baselines and non-regression detectors, **never**
  acceptance gates: both assert `expect_absent: panel`, so a correct one-participant
  consultation would fail them.
- A phase-agnostic registry value is worth adding as representation, and is **not**
  sufficient for C3.

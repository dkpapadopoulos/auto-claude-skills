# pdlc-closed-loop (delta)

## ADDED Requirements

### Requirement: Assumption Audit in the discovery brief

The DISCOVER-phase discovery brief MUST include an `## Assumption Ledger`
section reconstructing the initiative's logic chain as explicit assumptions,
each row carrying: belief, category, importance (H/M/L), `evidence_kind`
(direct_metric | direct_observation | analogous | expert_judgment | none),
`source_ref`, `observed_at`, `claimed_grade` (A-F), and — for fragile
assumptions (high-importance, grade C or below, top-3 by materiality) — a
kill-shot test with a pre-declared kill/validate `kill_threshold`. The brief
MUST tag findings as fact, inference, or unknown, and MUST present an option
set containing at least a do-nothing baseline with a conditional
recommendation (proceed / proceed-with-conditions naming a hard-number
condition / hold). The stage MUST be skippable only by explicit declaration
for small/obvious work, never silently.

#### Scenario: Ledger produced for a real initiative
- **GIVEN** a discovery session for a new feature with market/value uncertainty
- **WHEN** the discovery brief is synthesized
- **THEN** the brief MUST contain an `## Assumption Ledger` section with graded
  assumptions, at least one fragile assumption carrying a pre-declared
  kill/validate threshold, and an option set including do-nothing

#### Scenario: Evidence ceiling blocks grade inflation
- **GIVEN** a discovery doc whose ledger claims grade A on an assumption whose
  `evidence_kind` is `expert_judgment`
- **WHEN** `scripts/assumption-audit-check.sh` runs against the doc
- **THEN** the checker MUST exit non-zero naming the evidence-ceiling violation
  (expert_judgment caps at D), and a compliant ledger MUST pass with exit 0

### Requirement: Two-step active-choice validation

Discovery validation MUST be an active-choice interaction, not a yes/no
approval. Step one: decision criteria and weights are presented for user
confirmation BEFORE any option scores are shown. Step two: scored options and
the fragile-assumption quadrant are presented, and the user is asked to grade
or veto specific assumptions, choose which kill-shot test runs first, and
confirm or override the conditional recommendation. When the model judges the
work declared small/obvious, validation MAY collapse to a single step, stated
explicitly in chat.

#### Scenario: Weights confirmed before scores exist
- **GIVEN** a discovery session with a genuine option set
- **WHEN** validation begins
- **THEN** the user MUST be shown criteria and weights for confirmation before
  any per-option scores appear in the conversation

#### Scenario: Fragile assumption surfaced against user push
- **GIVEN** a user who asks to proceed on a plan resting on a D-grade belief
- **WHEN** the skill responds
- **THEN** it MUST surface the fragile assumption and its missing evidence
  before agreeing, offering proceed-with-conditions or a kill-shot test (it
  MUST NOT silently proceed)

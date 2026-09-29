# A replication instrument that can see what the design seed governs

## Why

The three-pair pilot of the design seed closed on 2026-09-24. Two pairs favoured
the arm without the seed, one was inconclusive, none favoured the seeded arm.
Issue #298 records why that is not a verdict: the instrument excluded what the
seed supplies and scored what it does not address.

The pilot's own record says where the instrument was narrow. It does not say
why the seeded arm lost, and this change does not claim to know.

| Fact | Where it is recorded |
|---|---|
| The transcription dimension "deliberately does not require tabular figures, alignment or a row height" | the pilot's relevance audit, R5 row |
| Only two of seven dimensions had an anchor for each score, and only those two were scored identically by every judge | registration v3, second read |
| Judges identified the seeded arm in every pair | the pilot's result |
| The brief never mentions numerics, alignment, consistency or states | the pilot's brief |

Two things have changed since the pilot.

1. **The pilot's brief is spent.** #299 amended the seed using the deductions
   the pilot's judges made. The rule it added is the top anchor of the pilot's
   identification dimension. A replication on that brief would measure a seed
   tuned to its instrument.
2. **The seed taught a losing pattern.** Version 1 prescribed a reason in a
   `title` attribute, and the arm that lost on the tooltip was following it. So
   one of the pilot's deductions was a defect in the guidance.

## What Changes

This change is a design and a registration of process. It adds no code and runs
no arm.

- The owner asked for a blind, comparative test of whether the seed improves
  screens. Review by another model family found the design cannot deliver that
  in full. It delivers a **descriptive comparison** under an instrument whose
  contents were specified by parties with controlled exposure to the seed.
- What is measured is chosen for its **value to the task**. It is not chosen to
  detect the seed.
- Presentation is **computed from the rendered page by a script**, specified by
  one party and approved by another. The author writes the code and neither
  specifies nor approves it.
- The **task, the fixture's contents and what is measured** are chosen by
  parties whose exposure to the seed is controlled.
- Exposure is **checked from outside** each party, by a check that fits how the
  party is run.
- A result has to pass an **interpretation gate** fixed in advance, or it is
  reported as inconclusive.
- The pilot's fidelity dimensions and fixture rule carry forward. Its decision
  rule carries forward with one vote per construct.

## Capabilities

- Modified: `design-foundations`

## Impact

- `openspec/changes/design-seed-replication-instrument/` — this design.
- No file under `assets/`, `hooks/`, `config/`, `scripts/`, `skills/` or
  `tests/` changes.
- The work that follows happens in Dion, which is private. This repository will
  record paths and digests only, as it did for the pilot.

## Depends on

PR #315 (#299), merged on 2026-09-29 as `4a7bb0b6`. The replication tests seed
version 2, which is the version on `main` from that commit.

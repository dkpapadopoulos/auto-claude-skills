# A replication instrument that can see what the design seed governs

## Why

The three-pair pilot of the design seed closed on 2026-09-24. Two pairs favoured
the arm without the seed, one was inconclusive, none favoured the seeded arm.
Issue #298 records why that is not a verdict: the instrument excluded what the
seed supplies and scored what it does not address.

The pilot's own record locates the cause more exactly than the issue does.

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

- The replication asks one question: does the seed improve screens? It is blind
  and comparative. The owner chose this over an adherence check.
- Presentation properties are **computed from the rendered page by a script**.
  A judge scores a presentation property only when it carries an anchor for
  each score.
- The **property list is derived by a party that has not seen the seed**, from
  the task alone.
- The **task and its brief are chosen by a party that has not seen the seed**.
  The owner chose this over naming a screen.
- Blindness is **enforced by the launch configuration and checked by a canary**
  before each blind party runs.
- The pilot's fidelity dimensions, decision rule, fixture rule and arm setup
  carry forward unchanged.

## Capabilities

- Modified: `design-foundations`

## Impact

- `openspec/changes/design-seed-replication-instrument/` — this design.
- No file under `assets/`, `hooks/`, `config/`, `scripts/`, `skills/` or
  `tests/` changes.
- The work that follows happens in Dion, which is private. This repository will
  record paths and digests only, as it did for the pilot.

## Depends on

PR #315 (#299). The replication tests seed version 2, so that change has to
merge before anything here is frozen.

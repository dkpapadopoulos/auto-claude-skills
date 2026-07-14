# behavioral-evaluation (delta)

## ADDED Requirements

### Requirement: Composition-directive uptake has a committed eval pack and baseline

The repo MUST carry a committed composition-uptake eval pack (top-level JSON
array, pinned judge assertions, self-contained prompts embedding the
production-shaped composition block) covering at minimum: CURRENT-step
uptake, skip-pressure resistance, the post-step continuation directive, and
a completed-chain over-fire control. A deterministic CI test MUST validate
the pack's structure (array shape, unique ids, judge kind with non-empty
criteria, composition markers present in every prompt). A measured baseline
artifact MUST record per-arm pass rates with the judge model, date, and rep
count. The behavioral run MUST remain opt-in and MUST NOT be a CI gate while
run-to-run variance is unestablished.

#### Scenario: Structure test fails on a malformed pack

- **GIVEN** a pack edit that wraps the array in an object, duplicates an id,
  or drops a judge criteria field
- **WHEN** `tests/test-composition-uptake-pack.sh` runs
- **THEN** it MUST fail naming the violated constraint

#### Scenario: Baseline records the measurement contract

- **GIVEN** a completed opt-in run
- **WHEN** the baseline artifact is read
- **THEN** it MUST contain the judge model, run date, rep count, and one
  pass/total entry per pack arm

#### Scenario: Pack prompts actually embed what they claim to test

- **GIVEN** any prompt in the pack
- **WHEN** the structure test inspects it
- **THEN** the prompt MUST contain a `Composition:` chain and a `[CURRENT]`
  marker (the directive surface whose uptake is being measured)

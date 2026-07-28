# Spec delta: pdlc-safety — shadow-corpus adjudication (Stage C2)

## ADDED Requirements

### Requirement: Adjudication of IMPLEMENT shadow records

`scripts/shadow-adjudicate.sh` MUST record a verdict for a shadow record without
mutating `~/.claude/.push-implement-shadow.jsonl`. Adjudications MUST be appended
to a separate sidecar log, `~/.claude/.push-implement-adjudication.jsonl`,
overridable via `IMPLEMENT_ADJUDICATION_LOG`, created `0600` before first write.

Each adjudication MUST carry `schema_version`, the target `record_id`, a UTC
ISO-8601 `ts`, a `verdict` of exactly `true_catch`, `false_block`, or `unknown`, a
free-text `reason`, a `claimant` of `human` or `agent`, and captured provenance.

`claimant` MUST be `agent` when ANY of the following holds: `CLAUDECODE` is set,
stdout is not a tty, or the parent process is `claude`. Output MUST describe
results as **human-claimed**, and MUST NOT describe them as human-verified.

Adjudicating a record whose `predicate_version` is not 2 MUST be refused with a
non-zero exit and an explanation. The script MUST NOT be sourced by
`hooks/openspec-guard.sh`, MUST NOT be added to `_GATE_ENFORCE_LIBS`, and MUST NOT
write any gate state or emit a `permissionDecision`.

#### Scenario: a human-claimed adjudication is recorded to the sidecar

- **GIVEN** a shadow log containing a `predicate_version: 2` record `rec_a`
- **WHEN** the operator runs `shadow-adjudicate.sh rec_a --verdict true_catch --reason "resolved by one truthful attest"`
- **THEN** exactly one object MUST be appended to the sidecar with
  `record_id: "rec_a"`, `verdict: "true_catch"`, and captured provenance
- **AND** the shadow log MUST be byte-identical to its prior contents

#### Scenario: a v1 record cannot be adjudicated

- **GIVEN** a shadow log whose record `rec_v1` carries `predicate_version: 1`
- **WHEN** the operator attempts to adjudicate `rec_v1`
- **THEN** the command MUST exit non-zero, MUST explain that v1 measured a
  different subject, and MUST NOT append to the sidecar

#### Scenario: an agent-run adjudication is marked and segregated

- **GIVEN** an environment where `CLAUDECODE` is set
- **WHEN** any record is adjudicated
- **THEN** the recorded `claimant` MUST be `agent`
- **AND** that episode MUST be excluded from the headline rate reported by
  `--status` until a `human`-claimed adjudication of the same record exists

### Requirement: Surfacing the next unadjudicated record

`--next` MUST print the oldest `predicate_version: 2` shadow record that has no
adjudication in the sidecar, together with the facts that caused the leg to fire
(`impl_in_chain`, `material_source`, `impl_evidence_kind`), its `repo`, `branch`,
`action`, `diff_base`, its `transcript_path` as the adjudication pointer, and the
exact command needed to label it.

When every v2 record is already adjudicated, `--next` MUST say so and exit 0.
`--next` MUST NOT append to the sidecar or modify any state.

#### Scenario: the oldest unadjudicated record is surfaced with its pointer

- **GIVEN** two v2 records, `rec_old` and `rec_new`, of which only `rec_new` has
  an adjudication in the sidecar
- **WHEN** the operator runs `--next`
- **THEN** the output MUST identify `rec_old`, MUST include its `transcript_path`,
  and MUST include a labeling command naming `rec_old`
- **AND** the sidecar MUST be byte-identical to its prior contents

#### Scenario: a fully adjudicated corpus reports nothing to do

- **GIVEN** a corpus where every v2 record has an adjudication
- **WHEN** the operator runs `--next`
- **THEN** it MUST report that nothing is outstanding and exit 0

### Requirement: Episode-level rate and band readout

`--status` MUST report over independent **episodes**, not records. Records MUST be
grouped into one episode when they share `(repo, branch, session_token)` AND their
`ts` falls within 30 minutes of that episode's FIRST record. The window is
anchored at the first record, not rolling between consecutive records: a rolling
gap would chain an entire day's work into a single episode, driving the
denominator below the real number of decision points.

An episode's verdict MUST resolve worst-verdict-wins: any `false_block` among its
records makes the episode `false_block`; otherwise any `unknown` makes it
`unknown`; otherwise `true_catch`.

`--status` MUST exclude `unknown` episodes, agent-claimed episodes, and records
whose `predicate_version` is not 2 from the headline rate, and MUST report each
excluded population alongside it rather than dropping it silently. It MUST also
print the rate recomputed with every `unknown` counted as a `false_block`.

When fewer than 29 adjudicated episodes exist, or when they span fewer than 2
distinct repos, `--status` MUST print `insufficient data` in place of a rate.
Repo diversity is measured on the `repo` field verbatim, and `--status` MUST list
the contributing repos rather than only counting them, so that two clones of one
project satisfying the requirement are visible to a reader.

When a rate is printed it MUST carry a one-sided 95% **exact Clopper–Pearson**
interval and a band: `DENY` when the upper bound is below 10%, `ADVISORY-ONLY`
when the lower bound is at or above 20%, and `NARROWED` otherwise. Equivalently
and as implemented, `DENY` requires `P(X ≤ k | n, 0.10) < 0.05` and
`ADVISORY-ONLY` requires `P(X ≥ k | n, 0.20) ≤ 0.05`.

A normal approximation MUST NOT be substituted for the exact interval. The
readout is informational and MUST NOT be wired into an enforcement decision.

#### Scenario: a retry burst counts as one episode

- **GIVEN** 11 shadow records sharing one `repo`, `branch`, and `session_token`,
  all within a 9-minute window
- **WHEN** `--status` groups them
- **THEN** they MUST resolve to exactly 1 episode

#### Scenario: the floor suppresses a premature rate

- **GIVEN** 3 adjudicated episodes, all `true_catch`, all in one repo
- **WHEN** `--status` runs
- **THEN** it MUST print `insufficient data` rather than `0%`
- **AND** it MUST report the distance to the 29-episode floor and the 2-repo
  diversity requirement

#### Scenario: the exact interval is used, not a normal approximation

- **GIVEN** 23 adjudicated episodes across ≥2 repos, of which 8 are `false_block`
- **WHEN** `--status` computes the band
- **THEN** the band MUST be `NARROWED`, because `P(X ≥ 8 | 23, 0.20) = 0.0715`
  exceeds 0.05
- **AND** at 9 `false_block` episodes the band MUST be `ADVISORY-ONLY`, because
  `P(X ≥ 9 | 23, 0.20) = 0.0273` does not

#### Scenario: a mixed episode resolves to its worst verdict

- **GIVEN** one episode whose records carry both `true_catch` and `false_block`
- **WHEN** `--status` resolves that episode
- **THEN** the episode MUST count as `false_block`

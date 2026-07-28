# Proposal: shadow-corpus adjudication tooling (Stage C2)

## Why

Stage C1 (PR #163) made the IMPLEMENT leg's would-block events *recordable*. It
did not make them *countable*. Records accumulate in
`~/.claude/.push-implement-shadow.jsonl` with no way to label one, and the
deny-flip's pre-registered decision rule — one-sided 95% upper bound below 10%,
over n=29 independent episodes across ≥2 repos, with a dated horizon of
~2026-09-08 — is arithmetic over a set of labels that nothing can produce.

Without C2 the horizon is not a deadline, it is a date after which we discover
the corpus was never adjudicated. That is the specific failure this change
prevents.

Three facts shape the design:

**1. The corpus governed by the rule is empty.** `predicate_version` 2 recording
began 2026-07-28T08:31Z (PR #168). The 11 existing records are v1 and
unpoolable. So C2 is built against fixtures, and its first real job is to refuse
to compute a rate over a corpus that cannot support one.

**2. Records are not episodes.** The entire v1 log is 11 records from a single
repo+branch inside one 9-minute window — one episode retried eleven times.
Local transcript history clusters at ~4.4 events per repo+branch. A record-level
denominator overstates n by roughly 4x, which would clear a 29-episode floor
with roughly seven real decision points.

**3. The subject can grade its own gate.** This leg governs whether *agent*
pushes are blocked, and an agent with shell access can run the adjudicator.
Labeling would-blocks `false_block` keeps the rate high and prevents the flip,
so the incentive runs toward self-serving labels. `implement-shadow-event/design.md`
already accepts that no genuinely human-bound signal exists in this harness; this
change adds the mitigation that does not depend on one.

## What Changes

A single script, `scripts/shadow-adjudicate.sh`, with three commands:

- `--next` — print the oldest unadjudicated v2 record, why the leg fired, its
  `transcript_path` pointer, and the ready-to-run labeling command.
- `<record_id> --verdict <true_catch|false_block|unknown> --reason "..."` —
  append one adjudication to a sidecar log with captured provenance.
- `--status` — episodes, exclusions, rate, band, distance to floor, horizon.

Adjudications land in a NEW append-only sidecar,
`~/.claude/.push-implement-adjudication.jsonl`. The shadow log is never mutated:
its schema is frozen for readers, the same reasoning that made the SHA binding a
sidecar rather than an in-place change.

## Capabilities (Modified)

- **pdlc-safety** — adds the adjudication surface and the rate/band readout over
  the C1 shadow corpus. No change to any gate decision.

## Impact

Diagnostic-only, like `gate-status.sh` and `push-gate-capture.sh`. The script is
never sourced by `hooks/openspec-guard.sh`, is deliberately EXCLUDED from
`_GATE_ENFORCE_LIBS`, and writes no gate state. Nothing in this change can
change a `permissionDecision`.

Out of scope: the deny-flip itself, any change to the leg or its predicate, and
the C3 consumer that a future flip decision would read. `--status` is
informational and MUST NOT be wired into an enforcement decision.

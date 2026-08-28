# Proposal: measure the review verdict's dispatch telemetry instead of asserting it

## Why

`#197` shipped the review verdict artifact, and it is rigorous almost everywhere.
Its `verdict` is SHA-bound, it refuses to write an unbound clean verdict, and it
imports real GitHub reviews. Two of its fields are the exception.

`dispatch_attempted` and `dispatch_succeeded` are **self-attested by copy-paste.**
Their only writer outside the GitHub-import path is
`skills/agent-team-review/SKILL.md:293`, where they appear as literal flags in a
Bash block the model runs:

    --findings <total> --unresolved-blocking <count> --dispatch-attempted --dispatch-succeeded

They are typed unconditionally. Nothing measures them, and — verified — **nothing
reads them**: the only other occurrences in the repo are the schema definition,
the design doc, and a test fixture.

So the artifact whose entire purpose is to establish that *"a Skill return is not
evidence a review ran"* records whether a reviewer was dispatched by asking the
model to say so. That is the same fallacy the artifact exists to close, one field
down.

The `--from-github` path already shows the better pattern: it **derives** both
flags from a PR that demonstrably has reviews (`record-review-verdict.sh:84`).
This change extends that pattern to local dispatches.

## What Changes

1. **`hooks/reviewer-evidence-hook.sh`** (new) — a `PostToolUse` hook on
   `^(Task|Agent)$` that records an observed reviewer-subagent return into the
   per-(repo+branch) branch ledger. Salvaged from the closed PR #212, where it
   was reviewed and hardened over four fix rounds, with everything gate-facing
   removed.

2. **`scripts/record-review-verdict.sh`** — derives `dispatch_attempted` /
   `dispatch_succeeded` from that observation, the same way the GitHub path
   derives them from a real PR. Explicit flags remain accepted for
   compatibility; an observation outranks them.

3. **`dispatch_evidence`** (new artifact field) — `observed` | `asserted` |
   `imported`. Without it, a pooled corpus cannot distinguish a measured value
   from a typed one, and every record written to date is `asserted`.

4. **`hooks/hooks.json`** — registers the hook on `^(Task|Agent)$`. The tool is
   named `Agent` on current Claude Code; `Task` is retained for older builds.

## Capabilities

### Modified Capabilities
- `pdlc-safety`: the review verdict artifact's dispatch telemetry becomes
  measured rather than asserted, with explicit provenance.

## Impact

- `hooks/reviewer-evidence-hook.sh` — new, diagnostic-only recorder.
- `hooks/hooks.json` — one new `PostToolUse` registration.
- `scripts/record-review-verdict.sh` — derivation + the new field.
- `hooks/lib/review-verdict.sh` — `review_verdict_field`'s jq `//`-falsy fix,
  so a genuine `false` value reads back as `false` (with a zero exit status)
  instead of empty/unknown.
- `skills/agent-team-review/SKILL.md` — the copy-paste flags become unnecessary.

## Explicitly NOT a predicate

`#197`'s spec is binding here and this change does not touch it:

> `dispatch_attempted` and `dispatch_succeeded` MUST be recorded as separate
> telemetry fields and MUST NOT, alone or collapsed, act as a deny predicate.

`#197` rejected dispatch-evidence as a gate on stated reasoning — *"a dispatch
still counts when the reviewer returns empty, reads the wrong base ref, sees one
file of ten, or has its findings discarded."* The session that produced PR #212
then confirmed it four times: reviewers returned non-error having delivered
nothing until explicitly chased. This change makes the telemetry **true**; it
does not promote it.

## Relationship to the closed PR #212

PR #212 built dispatch observation as a *gate* — an advisory leg, its own shadow
corpus, its own pre-registered deny-flip — before discovering `#197` had shipped
a stronger mechanism and had already rejected that approach. It is closed. This
change salvages the one piece that survives the collision: the observer, wired
to a field `#197` already designed for it.

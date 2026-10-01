# Require a MEASURED verdict for the VERIFY gate

## Why

Invoking `verification-before-completion` and executing **nothing** satisfies the push
gate's VERIFY leg (#301). No forged file is involved: `Skill(...)` returns the
instruction body, and `skill-completion-hook.sh` credits the milestone on that
successful return. Under this gate's chosen threat model — *defends against a
non-adversarial model skipping a step* — that is the central case, and it is open.

The three ways VERIFY can be skipped, ordered by how **accidentally** they happen:

| Path | Today | Requires |
|---|---|---|
| Never invoke the skill | denies | — |
| **Invoke, read instructions, execute nothing** | **ALLOWS** | nothing but stopping |
| Hand-write a verdict JSON (#295) | allows | deciding to write a file |

The gate is strongest against the path needing malice and weakest against the one
needing only distraction.

## What Changes

Require, **in addition to** the existing status milestone, a clean verdict whose
`discovery_source` shows it was produced by measurement rather than authored by the
model. `verify-and-record.sh` emits only two such values (`verify-yml`, `explicit`);
the `project-verification` ladder's other rungs (`claude-md-commands`,
`contributing-md`) name a **hand-authored** artifact.

This is the INVERSE of #254 d2, which asked the verdict to *replace* the milestone and
was refused on measurement. Requiring **both** weakens nothing.

The leg ships **advisory-only** with a shadow corpus AND its reader, and flips to deny
only if the pre-registered rule in `design.md` is met.

## Capabilities

**Modified**
- `pdlc-safety` — the VERIFY leg of the push gate gains a measured-verdict requirement,
  advisory at first.

## Impact

- `hooks/openspec-guard.sh` — VERIFY leg reads `discovery_source`; advisory, no `permissionDecision`.
- `hooks/lib/verdict.sh` — a `verdict_is_measured` predicate. Nothing reads
  `discovery_source` today, so this is a new reader over an already-populated field.
- New shadow writer + **reader shipped together** (the #239 failure was a corpus with no reader).
- No change to `verify-and-record.sh`, the artifact schema, or any existing deny leg.

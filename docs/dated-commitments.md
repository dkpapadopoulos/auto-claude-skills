# Dated commitments (`dated-check`)

An issue labelled `dated-check` carries a date the repo has committed to. The
label query reads **one field**: the `due:` line in the issue **body**.

## The convention

> **A deferral edits the body's `due:` line.**
> A comment explaining the deferral is welcome, and is not the record.

Both halves matter. Without the first, the queryable surface and the real
commitment drift and the overdue figure the query reports becomes wrong — and a
wrong number is worse than no number, because it is quotable. Without the
second, the reasoning behind a slip is lost.

This is the signpost/road defect this repo names elsewhere: the pointer is what
gets checked, the truth lives in what it points at, and the two drift apart.

## Checking it

```bash
bash scripts/dated-check-audit.sh
```

Three outcomes, deliberately never two:

| exit | meaning |
|---|---|
| `0` | clean — every body `due:` is the latest date committed to on its issue |
| `1` | divergent — at least one disagrees; each pair is printed |
| `3` | **cannot-check** — no `gh`, no `jq`, an API error, or a body with no parseable `due:` line |

`3` exists because "checked and clean" and "could not check" are different
states and only the first licenses quoting the number. An audit that reports
clean when it could not look is the defect it audits for.

## What counts as a deferral

A date counts only where the surrounding words make it a commitment *and* point
at it: `due: <date>`, `extended to <date>`, `revisit on <date>`,
`paused until <date>`.

A date that merely appears in prose does not. This is not hypothetical — the
first two cuts of the audit reported a false divergence on the live issue
because of the sentence:

> Extended window executed 2026-09-19

That reports **when something happened**; it does not move a deadline. The
audit requires both commitment language and a targeting preposition for exactly
this reason.

The ceiling, stated: a deferral phrased with none of those words is missed, and
the audit reports clean. That is the same failure direction as having no audit,
and the opposite of the false-positive direction, which would manufacture the
wrong number this exists to prevent.

## What this is not

[#182](https://github.com/dkpapadopoulos/auto-claude-skills/issues/182)
pre-registered whether lapsed dated commitments are a **visibility** problem and
resolved that they are a **prioritization** problem. No digest, monitor,
notification or scheduled workflow may be built for them.

`dated-check-audit.sh` adds none: it is run by a person who wants to know
whether the field they are about to quote is current. `tests/test-dated-check-audit.sh`
fails if a workflow ever starts calling it. If it acquires a scheduled caller,
the finding says to delete it rather than trim it.

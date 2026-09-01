---
type: gotcha
title: One red test in the suite silently blocks every routing push, repo-wide
description: .verify.yml declares the whole suite as the gate, so any single failing file makes a clean verdict impossible and routing-governance denies every push touching skills/, config/ or hooks/ — for every session, until someone notices.
tags: [push-gate, verification, verdict, routing-governance, ci]
source: .verify.yml
timestamp: 2026-09-01T00:00:00Z
---

`.verify.yml` is `run: bash tests/run-tests.sh`. Any single failing file makes
`scripts/verify-and-record.sh` write `failed:["tests"]`, and with no clean
verdict `routing-governance` denies every push touching `skills/|config/|hooks/`
— for **every** session, not just the one that broke it.

Measured 2026-08-30: `main` was red on two files, and **neither was a real
defect**. Both were assertions that had drifted from deliberate changes:

- a scenario fixture named injection prose that PR #221 had intentionally
  rewritten;
- a `.claude/knowledge/` `source:` cited a line number the code had moved away
  from.

Two one-line fixes (#226). Between the drift and the fix, nobody in any session
could push a routing change without the manual bypass.

**Why it stays hidden.** A denied push and a red suite look nothing alike from
the operator's seat. The deny names `project-verification` as the remedy, so the
natural response is to re-run verification, watch it fail for reasons that look
unrelated to your branch, and reach for the bypass. Nothing says "the repo's own
suite is red and that is why".

**How to apply.** When pushes start needing the bypass, run
`bash scripts/gate-status.sh` and read the `verification verdict:` line BEFORE
investigating evidence, tokens or branch state. `FAILED (gates: tests)` means the
problem is upstream of your branch entirely.

When checking whether a red is pre-existing, run the **full suite** at `main` —
not the one file you suspect. Checking a single file reported one pre-existing
failure here when there were two, and the second was found only by running
everything on a branch cut from `main`.

**Line-number citations in this directory are drift-prone by construction**: any
edit above the cited line breaks them, and the exact-line check lives in
`tests/test-knowledge.sh` rather than `scripts/knowledge-validate.sh` — the
validator alone would accept a `source:` with no line number. Expect to update
these alongside unrelated changes.

Related: [[hook-ab-needs-real-checkout]], [[check-usage-evidence-before-hardening-skill-path]].

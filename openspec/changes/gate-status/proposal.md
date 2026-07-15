# Proposal: gate-status observability command

## Why

Post-audit triage item 2 (2026-07-15): "confusing gates produce human
bypasses." The push gate now has six deny paths across two evidence layers
(status milestones, sha-bound verdicts) plus token-resolution subtleties; when
it denies without a legible reason the human escape hatch (`!` terminal push)
becomes the default — see the 2026-07-15 unexplained live deny. There is no
way to ask "what would the gate do right now, and why?" without replaying the
hook by hand.

## What Changes

- `scripts/gate-status.sh`: read-only replay of `hooks/openspec-guard.sh`'s
  push decision, in its exact gate order, using the guard's own evidence libs
  (`session-token.sh`, `branch-ledger.sh`, `verdict.sh`). Prints per-gate
  pass/WOULD-DENY, the first denying gate, and the exact remedy. Always exits
  0 (observational).
- `hooks/lib/staleness-delta.sh`: shared docs-vs-source delta classifier; the
  script's staleness observation line and the pre-registered backtest use the
  same code, so live observations stay comparable to the backtest.
- `docs/enforcement-map.md`: one-page anti-folklore map of every blocking and
  advisory surface; pinned to `gate-status.sh --help` by test.
- Backtest artifacts (`backtest-protocol.md`, `backtest-results.md`): the
  pre-registered post-review-staleness backtest that keeps the staleness line
  ADVISORY (decision rule: deny only on ≤5% false-block AND ≥1 catch; measured
  56–94% false-block, 0 catches across 48 evaluable of 108 merged PRs).

## Non-goals

Diagnosing the live-vs-on-disk hook divergence itself (the unexplained deny's
open hypothesis) — gate-status gives the comparison baseline ("every on-disk
gate says allow"), not the in-process introspection.

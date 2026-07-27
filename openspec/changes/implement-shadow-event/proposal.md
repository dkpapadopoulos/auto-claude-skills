# Proposal: IMPLEMENT-leg shadow event (Stage C1)

## Why

The IMPLEMENT-evidence leg of the push gate ships **warn-first**. Its deny-flip is
pre-registered as blocked on a push-replay backtest showing a `<10%` false-block
rate. Nobody can run that backtest, and investigation showed three independent
reasons why — each of which silently invalidates any measurement taken today.

**1. The would-block event is invisible to the capture log.** The IMPLEMENT leg
appends to `_STALE_MSG` and calls `phase_gate_log`, but never sets `_DECISION`
(`hooks/openspec-guard.sh`, Check 0). All seven `_DECISION="deny:*"` assignments
belong to other gates. So an IMPLEMENT would-block is recorded in
`~/.claude/.push-gate-invocation-log` as `decision:"allow"`. Adjudicating
`deny:*` records would measure *other gates' hard denies* — a different
population entirely, and a polished false-block rate for the wrong thing.

**2. The telemetry that does fire is too thin to adjudicate.** `phase_gate_log`
emits a fixed five-field line:
`<ts> gate=push-implement decision=warn skill=push missing=executing-plans`.
No repo, branch, sha, record id, or the facts that would justify a label. Two
such events exist (2026-07-22, 2026-07-27) and neither can be joined to anything.

**3. The sampled population does not match the spec.** The spec requires the leg
on "a push **or merge**" (`specs/pdlc-safety/spec.md`), but the code gates it on
`_gc_is_push = true` only, so `gh pr merge` never fires it.

Separately, the corpus that *does* exist is void: every pre-2026-07-27 deny
record carries either a misclassified replay (PR #153 — the classifier matched
compact JSON while the guard emits pretty) or is a non-push (PR #158 / issue
#155 — a newline inside a quoted argument was parsed as a command boundary, so
5 of 26 live denies were Codex invocations that push nothing).

This change makes the would-block event **referenceable and adjudicable**, and
makes the sampled population match the spec. It deliberately builds no
adjudication tooling and no backtest reader — those need real events to exist
first, and building an instrument before seeing the events is precisely the
mistake that produced items 1–3 above.

## What Changes

- A dedicated append-only JSONL shadow log at
  `~/.claude/.push-implement-shadow.jsonl`, written from the existing Check-0
  warn branch in `hooks/openspec-guard.sh`.
- Each record carries stable identity (`record_id`, `ts`, `schema_version`), a
  `predicate_version`, the adjudication facts, and a `transcript_path` pointer.
- The IMPLEMENT leg fires on `gh pr merge` as well as `git push`, matching the
  spec's declared population. Still advisory-only — no `permissionDecision`.
- A pre-registered false-block definition and decision rule (see `design.md`),
  committed **before** any data is collected.

## Capabilities

**Modified**
- `pdlc-safety` — the IMPLEMENT-evidence leg gains shadow-event emission and
  merge coverage. Its warn-first posture and evidence semantics are unchanged.

## Impact

- **Risk: low.** The leg remains advisory. No `permissionDecision` is added or
  changed, no deny path is touched. All writes are best-effort and fail open.
- **Behaviour change:** the advisory will now also appear on `gh pr merge` when
  the predicate matches. This is a widening of an advisory, not of a deny.
- **New local artifact:** one JSONL file. No network egress, no new authority.
- **Payoff is deferred by design.** At the observed rate (~0.4 events/day) this
  produces no usable rate for weeks. Its entire value is that the clock starts
  now: the episode→outcome link cannot be reconstructed retroactively.

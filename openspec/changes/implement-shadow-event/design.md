# Design: IMPLEMENT-leg shadow event (Stage C1)

## Architecture

### Where the record is written

A **dedicated append-only JSONL** at `~/.claude/.push-implement-shadow.jsonl`,
emitted from the existing Check-0 warn branch in `hooks/openspec-guard.sh`.

Three homes were considered; two are wrong:

- **`.phase-gate-events.log` (existing).** `phase_gate_log`
  (`hooks/lib/phase-evidence.sh`) writes a fixed five-field human-readable line
  and is shared with the attest and skill-seq gates. Changing its signature
  would break those callers; adding a parallel rich format to the same file
  would force every reader to handle two shapes.
- **`.push-gate-invocation-log` (capture).** That log records the *final push
  decision*. The IMPLEMENT leg never reaches a `_DECISION`, so its events would
  be indistinguishable from allows. It also rotates 1000→500, which would orphan
  adjudications of older records.
- **A dedicated file.** Chosen. Independent schema, independent lifecycle, and
  no rotation (below).

`phase_gate_log` continues to fire unchanged — the shadow record is additive.

### Record schema

```json
{
  "schema_version": 1,
  "record_id": "<content hash>",
  "ts": "2026-07-27T18:00:00Z",
  "predicate_version": 1,
  "gate": "push-implement",
  "would_block": true,
  "action": "push" | "gh-merge",
  "repo": "<repo path>",
  "branch": "<branch>",
  "head_sha": "<sha>",
  "impl_in_chain": true,
  "material_source": true,
  "impl_evidence_kind": "none",
  "session_token": "<token>",
  "transcript_path": "<path>"
}
```

`guard_cksum` and `plugin_version` were considered for the schema but are
**deferred, not emitted by v1** — `hooks/lib/implement-shadow.sh`'s
`implement_shadow_record` does not construct or write either field today.
Add them in a follow-up if drift-across-guard-versions turns out to matter
for adjudication.

- **`record_id`** is a content hash over `ts + pid + session_token +
  command_sha + action + nonce`. A first draft used only `ts + pid +
  command_sha`; review flagged that as too weak — `command_sha` repeats and
  `pid` recycles.
- **`predicate_version`** is the load-bearing field. When the IMPLEMENT
  predicate changes, this increments, and records from an older predicate MUST
  NOT be pooled with newer ones. Without it a future refactor silently mixes
  populations.
- **`impl_evidence_kind`** is intended to record which evidence checks were
  tried and missed (ledger / invocation / bridge / attestation), so an
  adjudicator can see *why* the leg fired without re-deriving it. **As built,
  the Check-0 call site hardcodes the literal `"none"`** — by construction
  that is the only value v1 can ever produce, not a summary of which checks
  ran. Deriving the real per-check outcome is future work.
- **`transcript_path`** is the adjudication pointer. Raw command text stays
  unlogged — the existing secret-safety posture is unchanged, and the transcript
  carries richer context than a command line anyway.

### No rotation in v1

The capture log rotates at 1000→500 records. Applying that here would silently
drop unadjudicated events. At ~0.4 events/day, 500 records is years away, so v1
is append-only with no rotation, documented explicitly rather than left implicit.
If the rate rises, rotation MUST exclude unadjudicated records or snapshot their
facts before dropping them.

### Population fix

Check 0 currently requires `_gc_is_push = true`. The spec requires the leg on a
push **or merge**. Extend the condition to accept `_gc_is_ghmerge`. The leg stays
advisory, so this widens an advisory, never a deny. Widening the leg only makes
the record get *written*; it does not make the advisory text reach the user on
a merge outside SHIP phase — `_flush_push_advisories` is still push-gated, so
that half of the population fix is issue #161, tracked and deliberately
deferred, not shipped here.

**Diff-base caveat.** `_diff_touches_material_source` resolves `material_source`
via `_branch_diff_names` — the same branch-local `merge-base(mainline,HEAD)..HEAD`
delta that routing-governance, `_flush_push_advisories`, and the evaluator
surface all use, each with an explicit comment that this delta is unrelated to
the PR actually being merged for `gh pr merge <other-branch>`. A merge record's
`material_source`, `branch`, and `head_sha` therefore describe the invoking
session's *local* branch state, not the merged PR's diff — the two can name
different content entirely (merging someone else's PR from a session sitting on
an unrelated branch). Merge records must be segmented at adjudication time on
this basis; a `diff_base` field that names what was actually diffed is a
follow-up, not built here.

### Failure posture

Every write is best-effort and fails open: an unwritable path, a missing `jq`, or
any error in record construction MUST leave the gate decision byte-identical.
The shadow log is diagnostic and is deliberately NOT added to
`_GATE_ENFORCE_LIBS` — same posture as `push-gate-capture.sh`.

## Pre-registration (committed before any data is collected)

> **`false_block`** — the human could not proceed, OR the gate's message named
> the wrong remedy.
> **`true_catch`** — includes a deny resolved by a single truthful
> `phase_attest`. That is forced explicit intent, not harm.
> **`unknown`** — terminal for the record, but counted against the stage (below).
>
> **Decision rule:** a **one-sided** 95% upper bound below 10%. One-sided is
> correct because the threshold is directional — we care only whether the rate
> is below 10%, not about a symmetric interval.
> **Unadjudicated records are excluded from the rate and reported alongside it.**

Recording this now is the point: defining the bar after seeing the data is the
post-hoc fitting this repo's discipline warns against.

## Trade-offs

- **Deferred payoff.** No usable rate for weeks. Accepted because the
  episode→outcome link provably cannot be reconstructed retroactively — the
  reason this backtest is blocked today.
- **Softer false-block definition is easier to clear.** Mitigated only by
  pre-registration; it is committed before collection, in this file.
- **Human adjudication is socially, not technically, enforced.** There is no
  genuinely human-bound signal available in this harness — TTY, env, and
  parent-process checks are all forgeable by an agent with shell access. C2 will
  therefore record provenance (`$USER`, tty, parent process, script sha, repo
  HEAD, whether agent env vars were present) and label the output
  "human-claimed" rather than "human-verified".

## Dissenting views

- **Codex:** "C2/C3 are not worth building as proposed — they will produce a
  polished rate for the wrong population." Accepted in full; this change is C1
  only, and it retargets the corpus from `deny:*` records to shadow events.
- **Codex:** "The threshold may also be wrong, not just the measurement. A
  first-deny on a legitimate no-implementation push is often forced explicit
  intent, not a hard false block." Accepted — it is the basis for the
  pre-registered `false_block` definition above.
- **Unresolved:** whether `<10%` is the right threshold at all. Not settled
  here; this change only makes it *measurable*. Revisit once ~10 real events
  exist.

## Decisions

1. Dedicated JSONL, not the shared events log and not the capture log.
2. Identity now (`record_id`, `ts`, `schema_version`), because it cannot be
   backfilled.
3. `predicate_version` from day one, so a later predicate change invalidates
   rather than silently pools.
4. Merge coverage added, so the sample matches the spec.
5. Adjudication tooling (C2) and the backtest reader (C3) deliberately deferred
   until real events exist.
6. Spec reconciliation (the spec names `scripts/phase-gate-backtest.sh`, which
   measures the skill-sequencing gate, not this leg) is **out of scope** and
   filed as a follow-up issue rather than silently corrected here.

## Out-of-Scope

- Any change to a `permissionDecision`, deny path, or the deny-flip itself.
- Adjudication tooling (C2) and the backtest consumer (C3).
- Changing or reconciling the `<10%` threshold or the spec's instrument
  reference.
- Rotation, retention, or pruning policy beyond "none in v1".
- The push-gate capture log's schema.

# Design: observed dispatch telemetry for the review verdict

## Architecture

Three pieces, deliberately small. The whole change is "replace an assertion with
a measurement in a field that already exists".

### A. The observer

`hooks/reviewer-evidence-hook.sh`, `PostToolUse` on `^(Task|Agent)$`. This
fires at DISPATCH, not at return: measured by parsing 23 real `Agent` tool
calls across three transcripts, every `tool_result` is a ~310-330 byte
"Spawned successfully…" acknowledgement, and none carries an `is_error`
field — the reviewer's actual report arrives later as a separate task
notification this hook never sees. On a dispatch identified as a reviewer,
with no error reported on the spawn acknowledgement, it calls
`branch_ledger_record "reviewer-ran"`, which stores `<sha> <utc-ts>`.

Salvaged from PR #212 with the gate-facing parts removed. What it keeps, and why
each was earned there rather than assumed here:

- **`(.tool_response | objects | .is_error)`**, not `.tool_response.is_error`.
  The latter is a *typed index*: jq raises on an array, string, or number, the
  `|| exit 0` fires, and the hook records nothing forever, silently. Measured —
  an array-shaped `tool_response` is a plausible shape for an agent returning
  content blocks.
- **Word-boundary intent matching** for `general-purpose`
  (`*[Rr]eview|*[Rr]eview[!a-zA-Z]*`). Measured against the real corpus of
  `description` strings: prefix matching credited 3/9 genuine dispatches;
  word-boundary credits 9/9 at 1/7 false positives. Substring is rejected — it
  credits the *noun* in implementation task names.
- **`^(Task|Agent)$`**. The tool is `Agent` on current Claude Code, verified
  across 12 transcripts. A `^Task$`-only matcher is dead here.

### B. The derivation

`scripts/record-review-verdict.sh` reads the observation and sets the two
telemetry fields, mirroring what the `--from-github` path already does at `:84`.
Precedence, highest first:

1. a resolvable `--from-github` PR → `imported`
2. an observed `reviewer-ran` record for this branch → `observed`
3. explicit `--dispatch-attempted` / `--dispatch-succeeded` flags → `asserted`
4. nothing → both `false`, `dispatch_evidence: "asserted"`

`imported` outranks `observed` when both hold: the values came from the PR
itself, so `imported` is the truthful label (R2). Observation outranks the
flags: if the model asserts a dispatch and no dispatch was observed, the
artifact should say so — that disagreement is the signal, and letting the
assertion win would delete it.

### C. The provenance field

`dispatch_evidence`: `observed` | `asserted` | `imported`.

Without it the corpus silently mixes measured and typed values, and **every
record written to date is `asserted`**. A reader pooling them would treat a
copy-pasted literal as evidence.

## Decisions

**D1 — `schema_version` bumps to 2; `predicate_version` does NOT.** `#197`'s own
rule, from `hooks/lib/review-shadow.sh`: *"when the leg's FIRE CONDITION changes,
bump it… Changing what a record merely DESCRIBES bumps `schema_version` instead,
leaving the corpus poolable and the horizon un-restarted."* This adds a
descriptive field and changes no fire condition, so `#197`'s pre-registered
deadline and n-floor survive untouched. Restarting its horizon would be a real
cost paid for nothing.

**D2 — This stays telemetry. It must never become a predicate.** Binding, from
`#197`'s spec: `dispatch_*` MUST NOT act as a deny predicate, alone or collapsed.
The reasoning is `#197`'s and it is correct: a dispatch still counts when the
reviewer returns empty. The session that built PR #212 observed exactly that four
times — reviewers returning non-error having produced nothing until chased. A
truer telemetry field is still telemetry.

**D3 — Absence records as "not observed", never as "observed false".** If the
hook never fired, or the branch key will not resolve, the derivation falls
through to `asserted`. The honest failure is losing the upgrade, not fabricating
a negative.

**D4 — The hook's write and the script's read MUST resolve the branch key
identically.** Both currently derive the path half from
`git rev-parse --show-toplevel` — the hook via `branch_ledger_record`'s
arg-less fallback, the script via `_ROOT`. `branch_ledger_key` hashes the
**raw path string and branch name**, so a non-canonical path on either side
(a trailing slash, a doubled separator, an unresolved symlink) produces a
different directory and the read silently misses. This is not hypothetical:
it produced a false negative during PR #212's development, where a
`$TMPDIR`-derived path with a doubled slash made a working recorder look
broken. The branch half carries the same hazard from a different cause: each
side derives it from its own cwd, and the two sides can legitimately be
different worktrees on different branches of the same repo — see Trade-offs.
Any future change giving one side an explicit `proj_root` must give it to both.

**D5 — Diagnostic-only, excluded from `_GATE_ENFORCE_LIBS`.** The hook writes no
gate state, emits nothing on stdout, and exits 0 on every path. Same posture as
`implement-shadow.sh` and `pr-diff.sh`.

## Trade-offs

- **The `is_error` field is measured ABSENT from every real `Agent` payload,
  and the error leg never fires in production.** Parsed 23 real `Agent` tool
  calls across three transcripts: every `tool_result` is a spawn
  acknowledgement with no `is_error` field at all, so the `// false` default is
  always taken. A crashed, stopped, or idle reviewer is therefore recorded as a
  successful dispatch every time this hook fires on a reviewer subagent — not
  merely in some untested edge case. This matters **less** here than it did in
  PR #212: as telemetry an over-credit is a wrong data point; as a gate it
  would have been a wrong block. The `| objects` guard still earns its keep —
  it protects a future payload shape that DOES carry the field, and bounds the
  failure to over-crediting rather than a silently dead recorder.
- **Dispatch is still not scrutiny, and is not even confirmed return.** An
  observed dispatch says a subagent was spawned and its spawn was
  acknowledged without error — nothing about whether it ran to completion,
  produced a report, or reviewed anything. That is precisely why it stays
  telemetry.
- **The observer only sees subagent dispatches.** A human review, or one done by
  reading the diff inline, produces no observation and correctly records
  `asserted`. The field measures dispatch, not review.
- **The observation is keyed to the dispatching session's repo+branch.**
  `branch_ledger_key` hashes `<origin-or-path>\x1f<branch>`, and the branch
  half is derived from each side's own cwd, same hazard class as the path half
  D4 already covers. `PostToolUse` fires in the dispatching session's
  cwd/branch; `scripts/record-review-verdict.sh` reads from whatever cwd it is
  invoked from. A review dispatched from one worktree and a verdict recorded
  from another — the repo's own `using-git-worktrees` / `agent-team-execution`
  pattern, not an edge case — resolve DIFFERENT keys, so the write is
  invisible to that read. D3 holds (this degrades to `asserted`, never a
  fabricated negative), but it means the upgrade to `observed` will usually
  not happen in exactly the workflow this hook was built for.

## Dissenting views

**Codex (sparring) recommended keeping PR #212's mechanism as a separate
STATUS-tier leg** rather than reducing it to telemetry. Its argument: `#197`'s
own Trade-offs concede *"A Skill return still credits STATUS… Status stays as-is;
the verdict leg reports the gap"*, and `reviewer-ran` is a strictly stronger
STATUS signal than a `Skill()` return, so it fills a hole `#197` names but does
not close.

**Not adopted.** The argument is sound about the *gap* and wrong about the
*remedy*. Keeping #212's leg means maintaining a second shadow corpus with its
own pre-registered deny-flip, whose stated destination — dispatch evidence as a
deny predicate — `#197`'s spec forbids. A pre-registration that cannot legally
reach its own conclusion should not be maintained for months. The gap Codex
identifies is real and is closed the way `#197` intended: by the verdict layer,
which demands pass/fail and SHA-binding, not by strengthening STATUS.

**Codex was right on two things that shaped this design**, both recorded above:
the fold-as-a-provider idea was a category error (B has no `verdict` content, and
no coherent `--base`/`--head` story), and it caught that `main` currently renders
the dispatch authorization with no observer present.

**On that last point — a correction to PR #212's own reasoning.** Its Sequencing
said shipping the authorization without the evidence layer was *"strictly worse
than today's state where nothing auto-dispatches"*. That rule was written before
`#197` existed. `main` now carries `#197`'s verdict leg, which is a stronger
evidence layer than the one #212 proposed, so the condition the rule guarded
against does not hold. The rule is stale, not violated.

## Capabilities Affected

- `pdlc-safety` — the review verdict artifact's dispatch telemetry, its
  provenance, and the observer that supplies it.

## Out-of-Scope

- **Making dispatch evidence a deny predicate.** Forbidden by `#197`'s spec and
  rejected on reasoning this change agrees with.
- **A second shadow corpus or deny-flip pre-registration.** `#197` owns the
  corpus for this capability.
- **Measuring the `Agent` payload's `is_error` field.** Still unmeasured; the
  `| objects` guard bounds the consequence. Worth a probe, not here.
- **Changing STATUS crediting.** `skill-completion-hook.sh` still credits
  `requesting-code-review` on a `Skill()` return. `#197` decided that stays.
- **The advisory leg, `reviewer-shadow.sh`, and the rest of PR #212.** Closed.

## Acceptance Scenarios

1. **Observed dispatch upgrades the telemetry.** GIVEN a reviewer subagent was
   dispatched with no error reported on this branch, WHEN a verdict is
   recorded without dispatch flags, THEN `dispatch_attempted` and
   `dispatch_succeeded` are `true` and `dispatch_evidence` is `observed`.
2. **Assertion is recorded as assertion.** GIVEN no observation exists, WHEN a
   verdict is recorded WITH `--dispatch-attempted --dispatch-succeeded`, THEN
   both are `true` and `dispatch_evidence` is `asserted`.
3. **Observation outranks a contradicting assertion.** GIVEN no observation
   exists, WHEN a verdict is recorded with the flags, THEN `dispatch_evidence`
   is `asserted` and NOT `observed` — the artifact never reports a measurement it
   did not make.
4. **The telemetry cannot deny.** GIVEN any combination of the above, WHEN the
   push gate evaluates, THEN no `permissionDecision` is derived from
   `dispatch_attempted`, `dispatch_succeeded`, or `dispatch_evidence`.

# Proposal: credit REVIEW on an observed subagent COMPLETION, not on a spawn

## Why

The push gate's REVIEW milestone is credited by `hooks/skill-completion-hook.sh`
the instant `Skill(superpowers:requesting-code-review)` returns. That
`PostToolUse` `^Skill$` event fires at instruction-**load** time, so **the
crediting event cannot witness what it attests**. Measured: 7 of 8 sampled
denied-then-merged PRs merged with zero reviews, and those sessions were
*satisfying* the gate, not evading it.

`hooks/reviewer-evidence-hook.sh` (#220) improved on that by recording a
`reviewer-ran` milestone when a reviewer subagent is **dispatched** — but it
runs on `PostToolUse` for `^(Task|Agent)$`, and for a backgrounded dispatch that
payload is a launch acknowledgement (`status: "async_launched"`,
`content: null`). A reviewer that spawns and then crashes, is stopped, goes
idle, or returns nothing is recorded identically to one that finished.

A completion event exists and this plugin does not subscribe to it.

## What was measured

Live, against Claude Code CLI 2.1.236, in an isolated `claude -p --settings`
session with `PostToolUse` and `Stop` registered in the same run as positive
controls (all three fired, so a non-firing `SubagentStop` would have been
distinguishable from a dead harness):

1. **`SubagentStop` fires**, once per subagent, at completion, including for two
   subagents dispatched in parallel in one message.
2. Its `transcript_path` names the **parent** session, but the payload carries
   `agent_transcript_path` for the subagent's own JSONL (present at hook time),
   plus `agent_id`, `agent_type`, and `last_assistant_message`.
3. `agent_type` is **verbatim and plugin-qualified** — measured
   `pr-review-toolkit:*`-shaped, `general-purpose`, and `Explore`.
4. `PostToolUse` for `Agent` returns `status: "completed"` with full content for
   a **foreground** dispatch, and `status: "async_launched"` with
   `content: null` for `run_in_background: true`. The "spawn acknowledgement"
   documented in `reviewer-evidence-hook.sh` is the background case only.
5. **The parent transcript does NOT link `agent_id` at hook time** — measured
   in-hook, `0` matching lines in an 18-line parent transcript while the
   subagent's own 4-line transcript was readable. The `tool_result` carrying
   `agentId` is written *after* `SubagentStop` fires. Any `agent_id` pairing
   must therefore be written by a **dispatch-time** writer; it cannot be
   recovered afterwards from the parent transcript.
6. `session_id` is identical across the dispatch and completion events and
   equals the transcript basename, so both sides key state off their own
   payload with no token resolver and no singleton fallback.
7. **Neither hook is guaranteed to run first**, and this killed the first
   design. Measured end-to-end with both REAL hooks registered and timestamped:

   | dispatch mode | order |
   |---|---|
   | `run_in_background: true` | dispatch fires **1.44s before** completion |
   | `run_in_background: false` | completion fires **~30ms before** dispatch (3 of 3) |

   A "dispatch writes the pairing, completion reads it" design is therefore a
   systematic no-op for every FOREGROUND dispatch. Not theorised — the first
   cut was built, and the live probe recorded `reviewer-ran` with **no**
   `reviewer-returned` for a foreground reviewer.

## What Changes

1. **`hooks/reviewer-completion-hook.sh`** (new) — a `SubagentStop` hook that
   records a `reviewer-returned` milestone into the per-(repo+branch) branch
   ledger when a **reviewer** subagent runs to completion. Same posture as the
   existing recorder: emits nothing on stdout, sets no `permissionDecision`,
   exits 0 on every failure path, and is deliberately NOT in
   `_GATE_ENFORCE_LIBS`.

2. **`hooks/lib/reviewer-pairing.sh`** (new) — owns the pairing file format and
   key derivation in ONE place, so the two hooks cannot drift.

3. **`hooks/reviewer-evidence-hook.sh`** — additionally records the dispatched
   `agent_id` and the branch ledger key when, and only when, it has already
   judged the dispatch to be a reviewer, and completes the join if the subagent
   has already finished. No change to its predicate, its ledger write, or its
   exit behaviour.

4. **`hooks/hooks.json`** — one new `SubagentStop` registration.

5. **`hooks/session-start-hook.sh`** — both pairing halves join the existing
   7-day state GC, each with the current session excluded.

6. **Nothing in `hooks/openspec-guard.sh`.** The new milestone is recorded and
   not read by any gate in this change.

## The join

Classification lives in the **dispatch** hook for both arms, because that is
where the measured `description` predicate and the `subagent_type` allowlist
already are. The completion hook owns the completion fact. Neither credits
alone, and because neither is guaranteed to run first (measured fact 7), the
join is **symmetric**: each hook writes its own half, then looks for the other,
and whichever runs second records the milestone.

The existing word-boundary predicate is therefore never re-pointed at new input.
It stays on `tool_input.description`, the short label it was fitted on
(9/9 recall at 1/7 false positives). Applying it to the subagent's full
multi-paragraph task prompt would have been a different population — its
`*[Rr]eview[!a-zA-Z]*` arm matches the word anywhere followed by a non-letter,
so against long prose it structurally degenerates into the substring variant
that measured 4/7 false positives, while looking unchanged in the diff.

A reader-side reconstruction is not available as an alternative: measured
in-hook, at `SubagentStop` time the parent transcript contains **zero** lines
mentioning `agent_id`, because the `tool_result` carrying it is written
afterwards.

## Branch binding

`branch_ledger_record` derives its key from the cwd at CALL time. A backgrounded
reviewer completes on the parent session's clock, and that session is free to
`git checkout` something else meanwhile — so an unbound credit would write
`reviewer-returned` into the ledger of a branch the reviewer never looked at.
That is not a miss but a **wrong-target hit**, into evidence the push gate
treats as durable cross-session proof.

The key is therefore recorded at dispatch and compared at completion. A mismatch
records nothing and leaves a `# branch-mismatch` diagnostic line, so a refused
credit is distinguishable from "no reviewer ran" — a silent miss is exactly how
the foreground ordering defect nearly shipped.

## What this does NOT establish

The honest label is **"observed completion"**, never "reviewed". This shows that
a reviewer-shaped subagent ran to completion and produced output. It does not
show that the output was a real review, that it examined this diff, that any
finding was correct, or that anything was acted on. A model can still dispatch a
reviewer prompted to rubber-stamp, and the human `!`/terminal bypass writes no
record at all and cannot be instrumented.

## Capabilities

### Modified Capabilities
- `pdlc-safety`: reviewer evidence gains an observed-completion signal distinct
  from observed dispatch, recorded but not yet gate-wired.

## Impact

- `hooks/reviewer-completion-hook.sh` — new, diagnostic-only recorder.
- `hooks/lib/reviewer-pairing.sh` — new, owns the pairing format/keys.
- `hooks/reviewer-evidence-hook.sh` — pairing write + backward join only.
- `hooks/hooks.json` — one `SubagentStop` registration.
- `hooks/session-start-hook.sh` — two GC names + two exclusions.
- `tests/test-reviewer-completion-hook.sh` — new, 27 cells, every credit path
  asserted in BOTH firing orders.
- `tests/test-state-file-cleanup.sh` — C6a/C6b for both pairing halves.
- No change to any deny decision in this change.

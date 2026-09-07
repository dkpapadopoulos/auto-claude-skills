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

## What Changes

1. **`hooks/reviewer-completion-hook.sh`** (new) — a `SubagentStop` hook that
   records a `reviewer-returned` milestone into the per-(repo+branch) branch
   ledger when a **reviewer** subagent runs to completion. Same posture as the
   existing recorder: emits nothing on stdout, sets no `permissionDecision`,
   exits 0 on every failure path, and is deliberately NOT in
   `_GATE_ENFORCE_LIBS`.

2. **`hooks/reviewer-evidence-hook.sh`** — additionally appends the dispatched
   `agent_id` to a session-scoped pairing file when, and only when, it has
   already judged the dispatch to be a reviewer. No change to its predicate, its
   ledger write, or its exit behaviour.

3. **`hooks/hooks.json`** — one new `SubagentStop` registration.

4. **`hooks/session-start-hook.sh`** — the pairing file joins the existing
   7-day state GC, with the current session excluded.

5. **Nothing in `hooks/openspec-guard.sh`.** The new milestone is recorded and
   not read by any gate in this change.

## Reviewer identification

Two arms, and they are not symmetric:

- **Allowlist arm** — `agent_type` matched against the same reviewer allowlist
  `reviewer-evidence-hook.sh` uses. Transfers with zero change, because
  `SubagentStop` carries the qualified type verbatim. No pairing needed.
- **`general-purpose` arm** — `SubagentStop` does not carry the dispatch
  `description`, and the existing word-boundary predicate
  (`*[Rr]eview|*[Rr]eview[!a-zA-Z]*`, measured 9/9 recall at 1/7 false
  positives) was **fitted on that short label**. Against a full multi-paragraph
  task prompt its second arm matches "review" anywhere followed by a non-letter,
  i.e. it structurally degenerates into the substring variant that measured 4/7
  false positives. The predicate is therefore NOT re-pointed at prompt text.
  Instead the `agent_id` written at dispatch is looked up — an exact key, no
  heuristic, and the predicate stays on the input it was measured against.

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
- `hooks/reviewer-evidence-hook.sh` — pairing write only.
- `hooks/hooks.json` — one `SubagentStop` registration.
- `hooks/session-start-hook.sh` — one GC name + one exclusion.
- `tests/test-reviewer-completion-hook.sh` — new.
- No change to any deny decision in this change.
